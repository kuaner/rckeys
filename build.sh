#!/bin/zsh
# rckeys 构建（统一走 SPM；测试用 `swift test`）
set -e
cd "$(dirname "$0")"
swift build -c release --product rckeys
mkdir -p .build
cp .build/release/rckeys .build/rckeys
FW=$(find .build -type d -name "Sparkle.framework" -ipath "*release*" | head -1)
[ -n "${FW}" ] && { rm -rf .build/Sparkle.framework; cp -R "${FW}" .build/; }
[ -d Resources ] && cp -R Resources .build/ 2>/dev/null
echo "构建完成: .build/rckeys"
