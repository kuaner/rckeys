// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "rckeys",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.1"),
    ],
    targets: [
        // 逻辑库：全部业务代码（测试经 @testable 访问内部成员）
        .target(name: "RCKeysCore", dependencies: [.product(name: "Sparkle", package: "Sparkle")],
                path: "Sources/RCKeys"),
        // CLI / App 入口（唯一消费者，用 public API）
        .executableTarget(name: "rckeys", dependencies: ["RCKeysCore"], path: "Sources/main"),
        .testTarget(name: "RCKeysTests", dependencies: ["RCKeysCore"], path: "Tests"),
    ]
)
