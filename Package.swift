// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "rckeys",
    platforms: [.macOS(.v14)],
    targets: [
        // 逻辑库：仅供 swift test 使用（@testable 免 public）。
        // 生产二进制不走 SPM——build.sh / build_app.sh 用 swiftc 把
        // Sources/RCKeys/*.swift 与 Sources/main.swift 编成单一模块。
        // 语言模式固定 v5：与 swiftc 直编一致，避免 Swift 6 严格并发误报。
        .target(name: "RCKeys", path: "Sources/RCKeys",
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "RCKeysTests", dependencies: ["RCKeys"], path: "Tests",
                    swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
