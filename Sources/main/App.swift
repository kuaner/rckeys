import Foundation
import AppKit
import ApplicationServices
import RCKeysCore

// RCKeys：小米遥控器 2 Pro (RC003) 按键自定义接管
// 架构（真机验证）：hidutil 设备级哑化(usage 0) + IOHID 纯监听 + 软件手势引擎 + CGEvent 注入。
// 无 CGEventTap、无抑制器、无 seize。权限：输入监控（读键）+ 辅助功能（注入）。

@main
enum RCKeysApp {
    @MainActor static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        setvbuf(stdout, nil, _IONBF, 0) // nohup 场景下日志实时落盘

        // ---- CLI 子命令 ----
        if args.contains("--fix") {
            // 清理崩溃残留的哑化映射
            let ok = Remap.clear()
            print(ok ? "已清除 RC003 的残留映射，遥控器恢复系统默认行为。" : "清除失败（hidutil 错误）")
            exit(ok ? 0 : 1)
        }
        if args.contains("--version") { print("rckeys \(AppInfo.version)"); exit(0) }
        if args.contains("--help") {
            print("""
            rckeys — 小米遥控器 2 Pro (RC003) 按键自定义
            无参数     启动后台服务（无菜单栏图标；遥控器长按 菜单 键打开设置）
            --test     12 秒试运行（应用映射并打印按键解码，不注入动作）
            --fix      清理崩溃残留的哑化映射
            配置文件:  \(Config.configURL.path)
            """)
            exit(0)
        }
        if args.contains("--test") { runDeviceTrial(); return }

        Agent(args: args).run()
    }

    // ---- 试运行模式：应用映射 → 监听打印 → 恢复 ----
    private static func runDeviceTrial() {
        print("应用哑化映射…（前台对遥控器应零反应）")
        guard Remap.apply() else { print("映射应用失败"); exit(1) }
        final class Counter: @unchecked Sendable { var n = 0 }
        let count = Counter()
        let listener = KeyListener()
        listener.log = { print("HID: \($0)") }
        listener.onEvent = { key, down in
            count.n += 1
            print("  [\(count.n)] \(key.rawValue)\(down ? " ▼" : " ▲")")
        }
        listener.onDevice = { print($0 ? "设备接入" : "设备移除") }
        listener.start()
        print("监听 12 秒，请按遥控器任意键……")
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
            Remap.clear()
            print("窗口结束（\(count.n) 个边沿事件），映射已恢复。")
            exit(0)
        }
        RunLoop.main.run()
    }
}

@MainActor final class Agent: NSObject, NSApplicationDelegate {
    private let args: [String]
    var engine: GestureEngine!
    var paused = false
    private var lastConfigOpen = DispatchTime(uptimeNanoseconds: 0)
    /// 必须持有 dispatch source，否则对象释放即失效（信号监听会被静默丢弃）
    private var signalSources: [DispatchSourceSignal] = []
    /// 防 App Nap：持有活动句柄，后台无窗口时定时器不被系统节流
    private var activity: NSObjectProtocol?

    init(args: [String]) { self.args = args }

    func run() {
        guard Self.acquireSingleInstanceLock() != nil else {
            // 无参数启动（点击 .app）= 唤醒已运行实例的设置窗口；CLI 用途则直接退出
            if args.isEmpty {
                Self.wakeRunningInstance()
                print("rckeys 已在运行，已请求其打开设置窗口。")
            } else {
                print("已有 rckeys 实例在运行，退出。")
            }
            exit(0)
        }
        try? "\(getpid())".write(to: Self.pidFileURL, atomically: true, encoding: .utf8)
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled], reason: "RCKeys HID 接管服务")
        AutoStart.install()
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.delegate = self

        // 辅助功能授权（注入动作需要；首次弹窗）
        _ = AXIsProcessTrustedWithOptions(
            ["AXTrustedCheckOptionPrompt": true] as CFDictionary)

        let (cfg, created) = Config.loadOrDefault()
        if created { print("已生成默认配置: \(Config.configURL.path)") }

        engine = GestureEngine(config: cfg) { action, key, kind in
            print("[动作] \(key.rawValue).\(kind) -> \(Actions.describe(action))")
            Actions.perform(action)
        }
        // 系统保留手势：长按菜单 → 呼出设置
        engine.onSystemGesture = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.openConfigFromRemote() } }

        let listener = KeyListener()
        listener.log = { print($0) }
        listener.onDevice = { [weak self] connected in
            MainActor.assumeIsolated {
                guard let self else { return }
                ServiceHub.shared.status.connected = connected
                if connected && !self.paused {
                    ServiceHub.shared.status.note = Remap.apply() ? "" : "映射应用失败（--fix 可清理）"
                    print("遥控器接入，哑化映射已重新应用")
                } else if connected && self.paused {
                    print("遥控器接入（已暂停，不接管）")
                } else {
                    self.engine.reset()
                    Remap.clear()
                    print("遥控器移除，映射已清除、手势状态已复位")
                }
            }
        }
        listener.onEvent = { [weak self] key, down in
            MainActor.assumeIsolated {
                guard let self, !self.paused else { return }
                if down { self.engine.keyDown(key) } else { self.engine.keyUp(key) }
            }
        }

        ServiceHub.shared.onTogglePause = { [weak self] in self?.togglePause() }
        ServiceHub.shared.onReloadConfig = { [weak self] in self?.reloadConfigNow() }
        ServiceHub.shared.onQuit = { [weak self] in self?.shutdown() }
        // 设置界面保存 → 引擎即时生效（进程内直通，绕开文件监听）
        ServiceHub.shared.onConfigSaved = { [weak self] cfg in
            self?.engine.updateConfig(cfg)
        }
        Updater.start()
        ServiceHub.shared.onCheckForUpdates = { Updater.check() }

        if !listener.start() {
            ServiceHub.shared.status.note = "输入监控权限未授予：系统设置→隐私与安全性→输入监控，勾选 RCKeys 后重启 App"
        }
        watchSignals()

        // 点击应用图标启动 = 服务 + 设置窗口；开机自启（LaunchAgent 注入
        // RCKEYS_SILENT_START）= 静默后台，不弹窗
        if ProcessInfo.processInfo.environment["RCKEYS_SILENT_START"] != "1" {
            DispatchQueue.main.async { ConfigWindowController.shared.show() }
        }

        print("rckeys 已启动（后台服务，无菜单栏/Dock 图标）。长按 菜单 键或再次打开 App 可打开设置。配置: \(Config.configURL.path)")
        app.run()
    }

    // ---- 单实例锁与唤醒 ----

    /// 单实例锁：防止双实例互相覆盖映射/双发动作
    private static func acquireSingleInstanceLock() -> Int32? {
        try? FileManager.default.createDirectory(at: Config.configDir, withIntermediateDirectories: true)
        let path = Config.configDir.appendingPathComponent("agent.lock").path
        let fd = open(path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { return nil }
        return flock(fd, LOCK_EX | LOCK_NB) == 0 ? fd : nil
    }

    private static var pidFileURL: URL { Config.configDir.appendingPathComponent("rckeys.pid") }

    /// 唤醒已运行的服务实例：读 pidfile 向其发 SIGUSR1（服务收到后弹出设置窗口）。
    /// 兜底路径——正常情况下 .app 已在运行时 macOS 直接发 reopen 事件，不会走到这里。
    private static func wakeRunningInstance() {
        guard let text = try? String(contentsOf: pidFileURL, encoding: .utf8),
              let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 1 else { return }
        kill(pid, SIGUSR1)
    }

    // ---- 服务控制 ----

    /// 系统保留手势（长按菜单）呼出设置窗口（1 秒防抖）
    private func openConfigFromRemote() {
        let now = DispatchTime.now()
        guard now.uptimeNanoseconds > lastConfigOpen.uptimeNanoseconds + 1_000_000_000 else { return }
        lastConfigOpen = now
        ConfigWindowController.shared.show()
        print("系统保留手势触发：呼出设置界面")
    }

    private func togglePause() {
        paused.toggle()
        engine.reset()
        if paused {
            Remap.clear()
            print("已暂停：映射清除，遥控器恢复系统默认")
        } else {
            Remap.apply()
            print("已恢复接管")
        }
        ServiceHub.shared.status.paused = paused
    }

    /// 手动重载：配置文件只在启动与这里被读取（无文件监听）
    private func reloadConfigNow() {
        if let cfg = Config.reload() {
            engine.updateConfig(cfg)
            print("配置已重载")
        } else {
            print("配置重载失败：JSON 解析错误，保留旧配置")
        }
    }

    private func watchSignals() {
        for sig in [SIGTERM, SIGHUP, SIGINT] {
            signal(sig, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.shutdown() } }
            src.resume()
            signalSources.append(src)
        }
        // SIGUSR1 = 唤醒：再次启动 .app 的兜底路径（正常运行走 reopen 事件）
        signal(SIGUSR1, SIG_IGN)
        let usr1 = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        usr1.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.openConfigFromRemote() } }
        usr1.resume()
        signalSources.append(usr1)
    }

    @objc func shutdown() {
        Remap.clear()
        try? FileManager.default.removeItem(at: Self.pidFileURL)
        print("已清理映射，退出。")
        NSApp.terminate(nil)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Remap.clear()
        return .terminateNow
    }

    /// 已在运行时再次点击 .app：macOS 发 reopen 事件，弹出设置窗口（不新起进程）。
    /// 注意必须返回 Bool——Void 签名不满足委托方法，事件会被静默丢弃。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        ConfigWindowController.shared.show()
        return true
    }
}
