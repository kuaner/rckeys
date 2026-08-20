#!/bin/bash
# RCKeys 应用打包：swiftc 双架构 + lipo 通用二进制 → RCKeys.app → ad-hoc 签名 → DMG
# 用法：scripts/build_app.sh [build|sign|dmg|release|help]
# 版本可用 VERSION=v0.2.0 覆盖（CI 从 tag 取）。

set -euo pipefail

APP_NAME="RCKeys"
BUNDLE_ID="com.kuaner.rckeys"
VERSION="${VERSION:-0.2.2}"
MIN_MACOS="14.0"
DIST="dist"
APP_DIR="${DIST}/${APP_NAME}.app"
DMG_PATH="${DIST}/RCKeys-${VERSION}-universal.dmg"

# Sparkle 自动更新
SPARKLE_VERSION="2.9.1"
SPARKLE_CACHE=".sparkle-cache"
# EdDSA 公钥（私钥在钥匙串 / GitHub secret SPARKLE_PRIVATE_ED_KEY，用于 appcast 签名）
SPARKLE_PUBLIC_ED_KEY="jd8kYhK9YOkMi7ch2M66E8ndRf0ReEGvwSrFLQOdEk0="
SU_FEED_URL="https://kuaner.github.io/rckeys/appcast.xml"

G='\033[0;32m'; Y='\033[1;33m'; NC='\033[0m'
log() { echo -e "${G}$1${NC}"; }
warn() { echo -e "${Y}$1${NC}"; }

# 本地密钥（.secret.env，gitignore）：配置了则 Developer ID 签名 + 公证，否则 ad-hoc
[ -f .secret.env ] && source .secret.env

# Sparkle 二进制发行版缓存（含通用 Sparkle.framework 与 sign_update 工具）
ensure_sparkle() {
    if [ ! -d "${SPARKLE_CACHE}/Sparkle.framework" ]; then
        log "下载 Sparkle ${SPARKLE_VERSION}…"
        mkdir -p "${SPARKLE_CACHE}"
        curl -sL "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz" \
            -o "${SPARKLE_CACHE}/sparkle.tar.xz"
        tar xf "${SPARKLE_CACHE}/sparkle.tar.xz" -C "${SPARKLE_CACHE}"
        rm -f "${SPARKLE_CACHE}/sparkle.tar.xz"
    fi
}

build() {
    ensure_sparkle
    log "=== 构建 ${APP_NAME} v${VERSION}（arm64 + x86_64 通用） ==="
    local fw="-F ${SPARKLE_CACHE} -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks"
    mkdir -p .build/universal
    swiftc -O -target "arm64-apple-macos${MIN_MACOS}" ${fw} Sources/RCKeys/*.swift Sources/main.swift -o .build/universal/rckeys-arm64
    swiftc -O -target "x86_64-apple-macos${MIN_MACOS}" ${fw} Sources/RCKeys/*.swift Sources/main.swift -o .build/universal/rckeys-x64
    lipo -create .build/universal/rckeys-arm64 .build/universal/rckeys-x64 \
        -output .build/universal/rckeys-universal

    log "=== 组装 ${APP_DIR} ==="
    rm -rf "${APP_DIR}"
    mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources" "${APP_DIR}/Contents/Frameworks"
    cp .build/universal/rckeys-universal "${APP_DIR}/Contents/MacOS/${APP_NAME}"
    cp -R "${SPARKLE_CACHE}/Sparkle.framework" "${APP_DIR}/Contents/Frameworks/"
    cp assets/AppIcon.icns "${APP_DIR}/Contents/Resources/"
    cp Resources/RC003-remote-photo.png "${APP_DIR}/Contents/Resources/"
    cat > "${APP_DIR}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSUIElement</key><true/>
    <key>LSMinimumSystemVersion</key><string>${MIN_MACOS}</string>
    <key>NSHumanReadableCopyright</key><string>MIT License</string>
    <key>NSSupportsAutomaticTermination</key><false/>
    <key>NSSupportsSuddenTermination</key><false/>
    <key>SUFeedURL</key><string>${SU_FEED_URL}</string>
    <key>SUPublicEDKey</key><string>${SPARKLE_PUBLIC_ED_KEY}</string>
    <key>SUEnableAutomaticChecks</key><true/>
    <key>SUScheduledCheckInterval</key><integer>86400</integer>
</dict>
</plist>
PLIST
    log "${APP_DIR} 构建完成"
}

# Sparkle 框架签名：公证要求框架内每个嵌套组件（XPC 服务、子 app、辅助二进制）
# 都单独带 Developer ID 签名 + 时间戳，须由内往外逐个签，最后签框架本体
sign_sparkle() {
    local id="$1"
    local b="${APP_DIR}/Contents/Frameworks/Sparkle.framework/Versions/B"
    for nested in "$b/XPCServices/Downloader.xpc" "$b/XPCServices/Installer.xpc" \
                  "$b/Updater.app" "$b/Autoupdate"; do
        [ -e "$nested" ] && codesign --force --options runtime --timestamp --sign "$id" "$nested"
    done
    codesign --force --options runtime --timestamp --sign "$id" "$b/../.."
}

sign() {
    if [ -n "${APPLE_SIGNING_IDENTITY:-}" ]; then
        log "=== 签名（Developer ID） ==="
        sign_sparkle "${APPLE_SIGNING_IDENTITY}"
        codesign --force --options runtime --timestamp \
            --sign "${APPLE_SIGNING_IDENTITY}" "${APP_DIR}"
        codesign --verify --strict "${APP_DIR}"
        log "Developer ID 签名通过"
    else
        warn "未配置 APPLE_SIGNING_IDENTITY，降级为 ad-hoc 签名"
        sign_sparkle "-"
        codesign --force --sign - "${APP_DIR}"
        codesign --verify --strict "${APP_DIR}"
        log "ad-hoc 签名通过"
    fi
}

dmg() {
    log "=== 制作 DMG ==="
    local temp="${DIST}/temp_dmg"
    rm -rf "${temp}" "${DMG_PATH}"
    mkdir -p "${temp}"
    cp -R "${APP_DIR}" "${temp}/"
    ln -sf /Applications "${temp}/Applications"
    hdiutil create -volname "${APP_NAME}" -srcfolder "${temp}" \
        -ov -format UDZO "${DMG_PATH}"
    rm -rf "${temp}"
    if [ -n "${APPLE_SIGNING_IDENTITY:-}" ]; then
        codesign --force --sign "${APPLE_SIGNING_IDENTITY}" "${DMG_PATH}"
        codesign --verify "${DMG_PATH}"
    fi
    log "DMG: ${DMG_PATH}"
}

notarize() {
    if [ -z "${APPLE_ID:-}" ] || [ -z "${APPLE_APP_SPECIFIC_PASSWORD:-}" ] || [ -z "${APPLE_TEAM_ID:-}" ]; then
        warn "未配置公证凭据（APPLE_ID / APPLE_APP_SPECIFIC_PASSWORD / APPLE_TEAM_ID），跳过公证"
        return 0
    fi
    log "=== 公证（notarytool --wait，可能需要几分钟） ==="
    xcrun notarytool submit "${DMG_PATH}" --wait \
        --apple-id "${APPLE_ID}" \
        --password "${APPLE_APP_SPECIFIC_PASSWORD}" \
        --team-id "${APPLE_TEAM_ID}"
    xcrun stapler staple "${DMG_PATH}"
    spctl --assess --type open --context context:primary-signature --verbose "${DMG_PATH}"
    log "公证完成并已 staple"
}

case "${1:-build}" in
    build)     build ;;
    sign)      sign ;;
    dmg)       dmg ;;
    notarize)  notarize ;;
    release)   build; sign; dmg; notarize ;;
    help|--help|-h)
        echo "Usage: scripts/build_app.sh [command]"
        echo "  build    构建 RCKeys.app（通用二进制）"
        echo "  sign     签名（配置 .secret.env 时为 Developer ID，否则 ad-hoc）"
        echo "  dmg      制作并签名 DMG"
        echo "  notarize 公证 + staple（需 .secret.env）"
        echo "  release  build + sign + dmg + notarize"
        ;;
    *) echo "未知命令: $1"; exit 1 ;;
esac
