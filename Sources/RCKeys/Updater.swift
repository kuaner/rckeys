import AppKit

#if canImport(Sparkle)
import Sparkle

/// Sparkle 自动更新。仅打包构建（build_app.sh 带 -framework Sparkle）编译此模块；
/// 开发用 build.sh（无框架）时 canImport 为 false，检查更新入口变为提示不可用。
enum Updater {
    static let controller = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil)

    /// 应用启动时在主线程触发懒加载，开启自动检查计划
    static func start() { _ = controller }

    static func check() {
        if Thread.isMainThread {
            controller.checkForUpdates(nil)
        } else {
            DispatchQueue.main.async { check() }
        }
    }
}
#endif
