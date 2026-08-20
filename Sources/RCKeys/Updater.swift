import Sparkle

/// Sparkle 自动更新（SPM 依赖随包提供，全部构建均可用）。
/// 引擎与 UI 均在主线程驱动；start() 在应用启动时调用以开启定时检查。
@MainActor public enum Updater {
    static let controller = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil)

    /// 应用启动时在主线程触发懒加载，开启自动检查计划
    public static func start() { _ = controller }

    public static func check() {
        if Thread.isMainThread {
            controller.checkForUpdates(nil)
        } else {
            Task { @MainActor in check() }
        }
    }
}
