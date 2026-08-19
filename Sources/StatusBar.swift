import AppKit

/// 菜单栏状态：◉ 已接管 / ○ 未连接 / ⏸ 已暂停。菜单：暂停切换、重载配置、清理并退出。
final class StatusBarController: NSObject, NSMenuDelegate {
    private let item: NSStatusItem
    var onTogglePause: (() -> Void)?
    var onReloadConfig: (() -> Void)?
    var onOpenConfig: (() -> Void)?
    var onQuit: (() -> Void)?

    private(set) var paused = false
    private var connected = false
    private var note = ""

    override init() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        item.button?.font = .monospacedSystemFont(ofSize: 14, weight: .medium)
        rebuildMenu()
        render()
    }

    func setConnected(_ c: Bool) { connected = c; render() }
    func setNote(_ n: String) { note = n; render() }

    func setPaused(_ p: Bool) {
        paused = p
        rebuildMenu()
        render()
    }

    private func render() {
        let title: String
        if paused { title = "⏸" }
        else if connected { title = "◉" }
        else { title = "○" }
        item.button?.title = title
        item.button?.toolTip = note.isEmpty ? "RCKeys" : "RCKeys — \(note)"
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        let status = NSMenuItem(title: statusLine, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        if !note.isEmpty {
            let n = NSMenuItem(title: note, action: nil, keyEquivalent: "")
            n.isEnabled = false
            menu.addItem(n)
        }
        menu.addItem(.separator())

        let pause = NSMenuItem(title: paused ? "恢复接管" : "暂停接管",
                               action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        menu.addItem(pause)

        let editor = NSMenuItem(title: "配置界面…", action: #selector(openConfig), keyEquivalent: ",")
        editor.target = self
        menu.addItem(editor)

        let reload = NSMenuItem(title: "重载配置", action: #selector(reloadConfig), keyEquivalent: "")
        reload.target = self
        menu.addItem(reload)

        let edit = NSMenuItem(title: "编辑配置…", action: #selector(editConfig), keyEquivalent: "")
        edit.target = self
        menu.addItem(edit)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "清理映射并退出", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
    }

    private var statusLine: String {
        if paused { return "RCKeys · 已暂停" }
        return connected ? "RCKeys · 遥控器已接管" : "RCKeys · 等待遥控器…"
    }

    @objc private func togglePause() { onTogglePause?() }
    @objc private func reloadConfig() { onReloadConfig?() }
    @objc private func openConfig() { onOpenConfig?() }
    @objc private func editConfig() {
        NSWorkspace.shared.open(Config.configURL)
    }
    @objc private func quit() { onQuit?() }
}
