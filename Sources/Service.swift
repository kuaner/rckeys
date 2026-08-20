import Combine
import AppKit

/// 服务状态与控制：无菜单栏图标后，状态展示与服务操作都收敛到设置对话框。
/// Agent 启动时把真实动作注入 ServiceHub 闭包；对话框菜单/底栏读写 status。

/// 呼出设置对话框的系统保留手势：双击 TV 键。
/// 手势引擎强制生效、不可被用户配置覆盖（用户配了 tv.double 也以系统手势优先）；
/// 配置界面锁定该触发位。TV 键单击因此会延迟到双击窗口结束才触发（引擎既有行为）。
/// （曾用双击菜单，但菜单单击默认是右键、快速连点右键常见，冲突；TV 双击默认空置。）
enum ServiceGesture {
    static let key: RemoteKey = .tv
    static let kind = "double"
}

final class ServiceStatus: ObservableObject {
    @Published var connected = false
    @Published var paused = false
    @Published var note = ""

    var statusLine: String {
        if paused { return "已暂停" }
        return connected ? "已接管" : "等待遥控器…"
    }
}

final class ServiceHub {
    static let shared = ServiceHub()
    let status = ServiceStatus()
    var onTogglePause: (() -> Void)?
    var onReloadConfig: (() -> Void)?
    var onQuit: (() -> Void)?
}
