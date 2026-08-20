import Combine
import AppKit

/// 服务状态与控制：无菜单栏图标后，状态展示与服务操作都收敛到设置对话框。
/// Agent 启动时把真实动作注入 ServiceHub 闭包；对话框菜单/底栏读写 status。

/// 呼出设置对话框的系统保留手势：长按 菜单 键（按住超过 holdMs 触发）。
/// 时长判定与单击零歧义、双方零延迟——曾用双击 TV，但单击/双击共存必有
/// 时间窗歧义（连点单击会误触双击），故改为长按；菜单语义也贴切。
/// 菜单键的长按与连发位在配置界面锁定（两者共享"按住"语义，均被系统占用）。
public enum ServiceGesture {
    public static let key: RemoteKey = .menu
    public static let kind = "hold"
}

@MainActor public final class ServiceStatus: ObservableObject {
    public init() {}
    @Published public var connected = false
    @Published public var paused = false
    @Published public var note = ""

    public var statusLine: String {
        if paused { return "已暂停" }
        return connected ? "已接管" : "等待遥控器…"
    }
}

@MainActor public final class ServiceHub {
    public init() {}
    public static let shared = ServiceHub()
    public let status = ServiceStatus()
    public var onTogglePause: (@MainActor () -> Void)?
    public var onReloadConfig: (@MainActor () -> Void)?
    public var onQuit: (@MainActor () -> Void)?
    /// 检查更新
    public var onCheckForUpdates: (@MainActor () -> Void)?
    /// 进程内配置直通：设置界面保存后立即应用到引擎（不依赖文件监听）
    public var onConfigSaved: (@MainActor (Config) -> Void)?
}

/// 开机自启：应用初始化时安装 LaunchAgent（登录 RunAtLoad 自启；崩溃自动拉起，
/// 干净退出不拉起——KeepAlive SuccessfulExit=false）。仅对 .app 内的正式安装生效，
/// 开发用裸二进制（.build/rckeys）跳过。取消自启：删除 plist 后退出即可。
public enum AutoStart {
    static let label = "com.kuaner.rckeys"
    public static var plistURL: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LaunchAgents/\(label).plist")
    }

    public static func install() {
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
