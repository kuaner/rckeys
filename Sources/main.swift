import Foundation
import AppKit
import ApplicationServices
import Carbon.HIToolbox

// RCKeys：小米遥控器 2 Pro (RC003) 按键自定义接管
// 架构（真机验证）：hidutil 设备级哑化(usage 0) + IOHID 纯监听 + 软件手势引擎 + CGEvent 注入。
// 无 CGEventTap、无抑制器、无 seize。权限：输入监控（读键）+ 辅助功能（注入）。

let args = Array(CommandLine.arguments.dropFirst())
setvbuf(stdout, nil, _IONBF, 0) // nohup 场景下日志实时落盘

// ---- CLI 子命令 ----
if args.contains("--fix") {
    // 清理崩溃残留的哑化映射
    let ok = Remap.clear()
    print(ok ? "已清除 RC003 的残留映射，遥控器恢复系统默认行为。" : "清除失败（hidutil 错误）")
    exit(ok ? 0 : 1)
}
if args.contains("--version") { print("rckeys 0.1.0"); exit(0) }
if args.contains("--help") {
    print("""
    rckeys — 小米遥控器 2 Pro (RC003) 按键自定义
    无参数     启动菜单栏常驻接管
    --test     12 秒试运行（应用映射并打印按键解码，不注入动作）
    --fix      清理崩溃残留的哑化映射
    配置文件:  \(Config.configURL.path)
    """)
    exit(0)
}

// ---- 纯逻辑自检：报告解析 / 配置默认值 ----
if args.contains("--self-test") {
    var failed = 0
    func expect(_ cond: Bool, _ name: String) {
        print("\(cond ? "✅" : "❌") \(name)")
        if !cond { failed += 1 }
    }
    // 1) usage 表完备：13 键一一对应
    expect(Set(RC003.usageByKey.values) == Set(RemoteKey.allCases), "usage 表覆盖 13 键")
    // 2) 哑化 payload 含 12 键且不含 back(0xF1)
    expect(Remap.neuters.count == 12 && !Remap.neuters.contains(0xF1), "哑化表 12 键、排除 0xF1")
    expect(Remap.payload.contains("0x700000052") && Remap.payload.contains("0x70000003E"), "payload 生成")
    // 3) 默认配置可编码往返
    let cfg = Config.defaultConfig()
    let data = try! JSONEncoder.pretty.encode(cfg)
    let back = try! JSONDecoder().decode(Config.self, from: data)
    expect(back == cfg, "默认配置 JSON 往返一致")
    expect(back.keys.count == RemoteKey.allCases.count, "默认配置覆盖 13 键")
    // 4) 键码表常用项
    expect(Actions.codes["return"] == CGKeyCode(kVK_Return)
           && Actions.codes["arrowup"] == CGKeyCode(kVK_UpArrow)
           && Actions.codes["a"] == CGKeyCode(kVK_ANSI_A), "键码表")
    // 5) 媒体键
    expect(Actions.mediaKeys["volume_up"] == 0 && Actions.mediaKeys["mute"] == 7, "媒体键码")
    exit(failed == 0 ? 0 : 1)
}

// ---- 试运行模式：应用映射 → 监听打印 → 恢复 ----
if args.contains("--test") {
    print("应用哑化映射…（前台对遥控器应零反应）")
    guard Remap.apply() else { print("映射应用失败"); exit(1) }
    let listener = KeyListener()
    var count = 0
    listener.log = { print("HID: \($0)") }
    listener.onEvent = { key, down in
        count += 1
        print("  [\(count)] \(key.rawValue)\(down ? " ▼" : " ▲")")
    }
    listener.onDevice = { print($0 ? "设备接入" : "设备移除") }
    listener.start()
    print("监听 12 秒，请按遥控器任意键……")
    DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
        Remap.clear()
        print("窗口结束（\(count) 个边沿事件），映射已恢复。")
        exit(0)
    }
    RunLoop.main.run()
}

// ---- 常驻模式 ----

// 单实例锁：防止双实例互相覆盖映射/双发动作
func acquireSingleInstanceLock() -> Int32? {
    try? FileManager.default.createDirectory(at: Config.configDir, withIntermediateDirectories: true)
    let path = Config.configDir.appendingPathComponent("agent.lock").path
    let fd = open(path, O_CREAT | O_RDWR, 0o600)
    guard fd >= 0 else { return nil }
    return flock(fd, LOCK_EX | LOCK_NB) == 0 ? fd : nil
}

final class Agent: NSObject, NSApplicationDelegate {
    let status = StatusBarController()
    var engine: GestureEngine!
    var paused = false

    func run() {
        guard acquireSingleInstanceLock() != nil else {
            print("已有 rckeys 实例在运行，退出。")
            exit(0)
        }
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

        let listener = KeyListener()
        listener.log = { print($0) }
        listener.onDevice = { [weak self] connected in
            guard let self else { return }
            self.status.setConnected(connected)
            if connected && !self.paused {
                self.status.setNote(Remap.apply() ? "" : "映射应用失败（--fix 可清理）")
                print("遥控器接入，哑化映射已重新应用")
            } else if connected && self.paused {
                print("遥控器接入（已暂停，不接管）")
            } else {
                self.engine.reset()
                Remap.clear()
                print("遥控器移除，映射已清除、手势状态已复位")
            }
        }
        listener.onEvent = { [weak self] key, down in
            guard let self, !self.paused else { return }
            if down { self.engine.keyDown(key) } else { self.engine.keyUp(key) }
        }

        status.onTogglePause = { [weak self] in
            guard let self else { return }
            self.paused.toggle()
            self.engine.reset()
            if self.paused {
                Remap.clear()
                print("已暂停：映射清除，遥控器恢复系统默认")
            } else {
                Remap.apply()
                print("已恢复接管")
            }
            self.status.setPaused(self.paused)
        }
        status.onOpenConfig = { ConfigWindowController.shared.show() }
        status.onReloadConfig = { [weak self] in
            guard let self else { return }
            if let cfg = Config.reload() {
                self.engine.updateConfig(cfg)
                print("配置已重载")
            } else {
                print("配置重载失败：JSON 解析错误，保留旧配置")
            }
        }
        status.onQuit = { [weak self] in
            self?.shutdown()
        }

        watchConfigFile()
        listener.start()
        watchSignals()

        print("rckeys 已启动。配置: \(Config.configURL.path)")
        app.run()
    }

    private func watchConfigFile() {
        let fd = open(Config.configURL.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write], queue: .main)
        src.setEventHandler { [weak self] in
            // 防编辑器多次原子写触发抖动：延迟 300ms 合并
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                guard let self, let cfg = Config.reload() else { return }
                self.engine.updateConfig(cfg)
                print("配置文件变更已热加载")
            }
        }
        src.resume()
    }

    private func watchSignals() {
        for sig in [SIGTERM, SIGHUP] {
            signal(sig, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler { [weak self] in self?.shutdown() }
            src.resume()
        }
        signal(SIGINT, SIG_IGN)
        let intSrc = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        intSrc.setEventHandler { [weak self] in self?.shutdown() }
        intSrc.resume()
    }

    @objc func shutdown() {
        Remap.clear()
        print("已清理映射，退出。")
        NSApp.terminate(nil)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Remap.clear()
        return .terminateNow
    }
}

Agent().run()
