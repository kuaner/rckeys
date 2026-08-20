import Foundation
import AppKit
import Carbon.HIToolbox
import CoreGraphics

/// 动作执行：CGEvent 合成按键/组合键、NX_SYSDEFINED 媒体键、鼠标点击、打开 App、shell。
/// 注入需要「辅助功能」权限（首次运行会弹授权提示）。
public enum Actions {

    // 键名 -> 虚拟键码（编译期由 SDK 常量保证正确）
    static let codes: [String: CGKeyCode] = {
        var t: [String: CGKeyCode] = [
            "return": CGKeyCode(kVK_Return), "esc": CGKeyCode(kVK_Escape),
            "delete": CGKeyCode(kVK_Delete), "forwarddelete": CGKeyCode(kVK_ForwardDelete),
            "tab": CGKeyCode(kVK_Tab), "space": CGKeyCode(kVK_Space),
            "capslock": CGKeyCode(kVK_CapsLock),
            "arrowup": CGKeyCode(kVK_UpArrow), "arrowdown": CGKeyCode(kVK_DownArrow),
            "arrowleft": CGKeyCode(kVK_LeftArrow), "arrowright": CGKeyCode(kVK_RightArrow),
            "home": CGKeyCode(kVK_Home), "end": CGKeyCode(kVK_End),
            "pageup": CGKeyCode(kVK_PageUp), "pagedown": CGKeyCode(kVK_PageDown),
            "help": CGKeyCode(kVK_Help),
            // kVK_MissionControl/kVK_LaunchPad 本 SDK 未导出，用公认键码（Karabiner 文档一致）
            "missioncontrol": 160, "launchpad": 131,
            "cmd": CGKeyCode(kVK_Command), "cmdright": CGKeyCode(kVK_RightCommand),
            "ctrl": CGKeyCode(kVK_Control), "ctrlright": CGKeyCode(kVK_RightControl),
            "shift": CGKeyCode(kVK_Shift), "shiftright": CGKeyCode(kVK_RightShift),
            "alt": CGKeyCode(kVK_Option), "optright": CGKeyCode(kVK_RightOption),
        ]
        let fKeys = ["f1": kVK_F1, "f2": kVK_F2, "f3": kVK_F3, "f4": kVK_F4, "f5": kVK_F5,
                     "f6": kVK_F6, "f7": kVK_F7, "f8": kVK_F8, "f9": kVK_F9, "f10": kVK_F10,
                     "f11": kVK_F11, "f12": kVK_F12, "f13": kVK_F13, "f14": kVK_F14,
                     "f15": kVK_F15, "f16": kVK_F16, "f17": kVK_F17, "f18": kVK_F18,
                     "f19": kVK_F19, "f20": kVK_F20]
        for (n, c) in fKeys { t[n] = CGKeyCode(c) }
        let ansi: [(String, Int)] = [
            ("a", kVK_ANSI_A), ("b", kVK_ANSI_B), ("c", kVK_ANSI_C), ("d", kVK_ANSI_D),
            ("e", kVK_ANSI_E), ("f", kVK_ANSI_F), ("g", kVK_ANSI_G), ("h", kVK_ANSI_H),
            ("i", kVK_ANSI_I), ("j", kVK_ANSI_J), ("k", kVK_ANSI_K), ("l", kVK_ANSI_L),
            ("m", kVK_ANSI_M), ("n", kVK_ANSI_N), ("o", kVK_ANSI_O), ("p", kVK_ANSI_P),
            ("q", kVK_ANSI_Q), ("r", kVK_ANSI_R), ("s", kVK_ANSI_S), ("t", kVK_ANSI_T),
            ("u", kVK_ANSI_U), ("v", kVK_ANSI_V), ("w", kVK_ANSI_W), ("x", kVK_ANSI_X),
            ("y", kVK_ANSI_Y), ("z", kVK_ANSI_Z),
            ("1", kVK_ANSI_1), ("2", kVK_ANSI_2), ("3", kVK_ANSI_3), ("4", kVK_ANSI_4),
            ("5", kVK_ANSI_5), ("6", kVK_ANSI_6), ("7", kVK_ANSI_7), ("8", kVK_ANSI_8),
            ("9", kVK_ANSI_9), ("0", kVK_ANSI_0),
            ("-", kVK_ANSI_Minus), ("=", kVK_ANSI_Equal), ("[", kVK_ANSI_LeftBracket),
            ("]", kVK_ANSI_RightBracket), ("\\", kVK_ANSI_Backslash), (";", kVK_ANSI_Semicolon),
            ("'", kVK_ANSI_Quote), ("`", kVK_ANSI_Grave), (",", kVK_ANSI_Comma),
            (".", kVK_ANSI_Period), ("/", kVK_ANSI_Slash),
        ]
        for (n, c) in ansi { t[n] = CGKeyCode(c) }
        return t
    }()

    static let modifierMasks: [String: CGEventFlags] = [
        "cmd": .maskCommand, "command": .maskCommand,
        "ctrl": .maskControl, "control": .maskControl,
        "shift": .maskShift,
        "alt": .maskAlternate, "option": .maskAlternate,
        "fn": .maskSecondaryFn,
    ]

    /// 反查表（录制器用）：键码 -> 键名
    static let codeNames: [CGKeyCode: String] = {
        var t: [CGKeyCode: String] = [:]
        for (name, code) in codes where t[code] == nil { t[code] = name }
        return t
    }()

    // NX_SYSDEFINED 媒体键码（IOKit/hidsystem/ev_keymap.h）
    static let mediaKeys: [String: Int32] = [
        "volume_up": 0, "volume_down": 1, "brightness_up": 2, "brightness_down": 3,
        "mute": 7, "play": 16, "next": 17, "prev": 18, "fast": 19, "rewind": 20,
    ]

    // MARK: - 执行

    public static func perform(_ action: Action) {
        switch action.type {
        case "key":
            if let combo = action.combo { postCombo(combo) }
        case "media":
            if let n = action.name, let code = mediaKeys[n] { postMedia(code) }
        case "mouse":
            postMouseClick(action.name == "left" ? .left : .right)
        case "open":
            if let app = action.name, !app.isEmpty { openApp(app, bundleID: action.command) }
        case "shell":
            if let cmd = action.command, !cmd.isEmpty { runShell(cmd) }
        default:
            break
        }
    }

    public static func describe(_ a: Action) -> String {
        switch a.type {
        case "key": return "key \(a.combo ?? "?")"
        case "media": return "media \(a.name ?? "?")"
        case "mouse": return "mouse \(a.name ?? "?")"
        case "open": return "open \(a.name ?? "?")"
        case "shell": return "shell"
        default: return "none"
        }
    }

    // MARK: - 按键合成

    static func postCombo(_ combo: String) {
        let parts = combo.split(separator: "+").map(String.init).map { $0.lowercased() }
        guard let last = parts.last else { return }
        var flags: CGEventFlags = []
        for m in parts.dropLast() {
            if let f = modifierMasks[m] { flags.insert(f) }
        }
        guard let src = CGEventSource(stateID: .hidSystemState) else { return }

        // 裸修饰键（如长按某个修饰键触发听写类工具）：flagsChanged down/up
        if let mask = modifierMasks[last], parts.count == 1 {
            postFlags(mask, down: true, src: src)
            postFlags(mask, down: false, src: src)
            return
        }
        guard let code = codes[last] else { return }
        for down in [true, false] {
            guard let ev = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down) else { continue }
            if !flags.isEmpty { ev.flags = flags }
            ev.post(tap: .cghidEventTap)
        }
    }

    private static func postFlags(_ mask: CGEventFlags, down: Bool, src: CGEventSource) {
        guard let ev = CGEvent(keyboardEventSource: src, virtualKey: modifierKeycode(mask), keyDown: down) else { return }
        ev.flags = down ? mask : []
        ev.post(tap: .cghidEventTap)
    }

    private static func modifierKeycode(_ mask: CGEventFlags) -> CGKeyCode {
        if mask.contains(.maskCommand) { return CGKeyCode(kVK_Command) }
        if mask.contains(.maskControl) { return CGKeyCode(kVK_Control) }
        if mask.contains(.maskShift) { return CGKeyCode(kVK_Shift) }
        if mask.contains(.maskAlternate) { return CGKeyCode(kVK_Option) }
        return CGKeyCode(kVK_Function)
    }

    // MARK: - 媒体键（音量/亮度/播放）

    static func postMedia(_ key: Int32) {
        for down in [true, false] { postNX(key, down: down) }
    }

    private static func postNX(_ key: Int32, down: Bool) {
        // macOS 26 实测编码：键码在 16-23 位、状态(0xA按/0xB放)在 8-15 位。
        // 老配方(状态<<8|键码)的键码会落入被忽略的字段，所有媒体键都被当成音量加。
        let state = down ? 0xA : 0xB
        let data1 = (Int(key) << 16) | (state << 8)
        guard let ev = NSEvent.otherEvent(with: .systemDefined,
                                          location: .zero,
                                          modifierFlags: NSEvent.ModifierFlags(rawValue: 0xA00),
                                          timestamp: 0,
                                          windowNumber: 0,
                                          context: nil,
                                          subtype: 8,
                                          data1: data1,
                                          data2: -1),
              let cg = ev.cgEvent else { return }
        cg.post(tap: .cghidEventTap)
    }

    // MARK: - 修饰键按住生命周期（hold 触发"裸修饰键"时：按下时 down，松开时 up）

    static func isBareModifier(_ combo: String?) -> Bool {
        guard let c = combo, !c.contains("+") else { return false }
        return modifierMasks[c] != nil
    }

    static func pressModifier(_ name: String, down: Bool) {
        guard let mask = modifierMasks[name],
              let src = CGEventSource(stateID: .hidSystemState) else { return }
        guard let ev = CGEvent(keyboardEventSource: src,
                               virtualKey: modifierKeycode(mask),
                               keyDown: down) else { return }
        ev.flags = down ? mask : []
        ev.post(tap: .cghidEventTap)
    }

    // MARK: - 鼠标 / App / Shell

    static func postMouseClick(_ button: CGMouseButton) {
        guard let loc = CGEvent(source: nil)?.location,
              let src = CGEventSource(stateID: .hidSystemState) else { return }
        let kind: CGEventType = button == .left ? .leftMouseDown : .rightMouseDown
        let kindUp: CGEventType = button == .left ? .leftMouseUp : .rightMouseUp
        CGEvent(mouseEventSource: src, mouseType: kind, mouseCursorPosition: loc, mouseButton: button)?.post(tap: .cghidEventTap)
        CGEvent(mouseEventSource: src, mouseType: kindUp, mouseCursorPosition: loc, mouseButton: button)?.post(tap: .cghidEventTap)
    }

    /// 打开 App：优先 bundle id（`open -b`，App 改名/更新不影响），
    /// 失败或未配置时回退按名打开（`open -a`，兼容旧配置存的文件名）。
    @discardableResult
    static func openApp(_ name: String, bundleID: String? = nil) -> Bool {
        if let bid = bundleID, !bid.isEmpty, runOpen(["-b", bid]) { return true }
        return runOpen(["-a", name])
    }

    @discardableResult
    private static func runOpen(_ args: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = args
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    static func runShell(_ command: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-c", command]
        try? p.run()
    }
}
