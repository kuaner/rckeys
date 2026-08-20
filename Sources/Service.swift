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

/// 开机自启：应用初始化时安装 LaunchAgent（登录 RunAtLoad 自启；崩溃自动拉起，
/// 干净退出不拉起——KeepAlive SuccessfulExit=false）。仅对 .app 内的正式安装生效，
/// 开发用裸二进制（.build/rckeys）跳过。取消自启：删除 plist 后退出即可。
enum AutoStart {
    static let label = "com.kuaner.rckeys"
    static var plistURL: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LaunchAgents/\(label).plist")
    }

    static func install() {
        guard let exe = Bundle.main.executableURL,
              Bundle.main.bundlePath.hasSuffix(".app") else {
            print("开发运行（非 .app 安装），跳过开机自启")
            return
        }
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key><string>\(label)</string>
            <key>ProgramArguments</key>
            <array><string>\(exe.path)</string></array>
            <key>RunAtLoad</key><true/>
            <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
            <key>StandardOutPath</key><string>\(NSHomeDirectory())/Library/Logs/rckeys.log</string>
            <key>StandardErrorPath</key><string>\(NSHomeDirectory())/Library/Logs/rckeys.log</string>
        </dict>
        </plist>
        """
        do {
            try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try plist.write(to: plistURL, atomically: true, encoding: .utf8)
            print("已安装开机自启: \(plistURL.path)")
        } catch {
            print("LaunchAgent 安装失败: \(error)")
        }
    }
}
