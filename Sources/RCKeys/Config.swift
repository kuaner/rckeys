import Foundation

/// 版本单一来源：打包构建读 Info.plist（build_app.sh 注入）；
/// 开发构建回退硬编码（与 build_app.sh 的 VERSION 默认值保持同步）
public enum AppInfo {
    public static let version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.3.3"
}

// 13 个逻辑键（与 RC003 的 HID usage 对应关系见 HID.swift）
public enum RemoteKey: String, CaseIterable, Sendable {
    case up, down, left, right, ok
    case back, home, menu, tv, power
    case volUp = "volup", volDown = "voldown"
    case voice
}

// 单个动作。type: key | media | open | shell | mouse | none
public struct Action: Codable, Equatable, Sendable {
    public var type: String
    public var combo: String?     // type=key: "ctrl+cmd+q" / "arrowup" / "cmd"
    public var name: String?      // type=media: volume_up…; type=open: App 名（显示用）; type=mouse: right/left
    public var command: String?   // type=shell: 命令; type=open: bundle id（open -b 优先，缺省回退 open -a name）

    public static func key(_ combo: String) -> Action { Action(type: "key", combo: combo) }
    public static func media(_ name: String) -> Action { Action(type: "media", name: name) }
    public static let none = Action(type: "none")
}

// 每键触发配置：tap 即时（未配 double 时零延迟）、hold 长按、repeat 长按连发、double 双击。
// hold 与 repeat 互斥，同时配置时 hold 优先。
public struct KeyConfig: Codable, Equatable, Sendable {
    public var tap: Action?
    public var hold: Action?
    public var double: Action?
    public var repeatAction: Action?

    enum CodingKeys: String, CodingKey {
        case tap, hold, double
        case repeatAction = "repeat"
    }
}

public struct Settings: Codable, Equatable, Sendable {
    var holdMs: Int = 350
    var doubleMs: Int = 250   // 双击判定窗口（可调 150-800）
    var repeatMs: Int = 100
    var repeatDelayMs: Int = 350
}

public struct Config: Codable, Equatable, Sendable {
    public var settings = Settings()
    public var keys: [String: KeyConfig] = [:]

    public static let configDir = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("RCKeys", isDirectory: true)
    public static var configURL: URL { configDir.appendingPathComponent("config.json") }

    // 出厂默认：行为贴近原生遥控器，全部可改
    static func defaultConfig() -> Config {
        var c = Config()
        c.keys = [
            "up":     KeyConfig(tap: .key("arrowup"),    repeatAction: .key("arrowup")),
            "down":   KeyConfig(tap: .key("arrowdown"),  repeatAction: .key("arrowdown")),
            "left":   KeyConfig(tap: .key("arrowleft"),  repeatAction: .key("arrowleft")),
            "right":  KeyConfig(tap: .key("arrowright"), repeatAction: .key("arrowright")),
            "ok":     KeyConfig(tap: .key("return")),
            "back":   KeyConfig(tap: .key("delete"), hold: .key("esc")),
            "home":   KeyConfig(tap: .key("missioncontrol"), hold: .key("ctrl+arrowup")),
            "menu":   KeyConfig(tap: Action(type: "mouse", name: "right")),
            "tv":     KeyConfig(tap: .key("cmd+tab"), hold: .key("cmd+shift+tab")),
            "power":  KeyConfig(tap: .key("ctrl+cmd+q"),
                                hold: Action(type: "shell", command: "pmset displaysleepnow")),
            "volup":  KeyConfig(tap: .media("volume_up"),   repeatAction: .media("volume_up")),
            "voldown":KeyConfig(tap: .media("volume_down"), repeatAction: .media("volume_down")),
            "voice":  KeyConfig(tap: Action.none),
        ]
        return c
    }

    public static func loadOrDefault() -> (Config, created: Bool) {
        let url = configURL
        if let data = try? Data(contentsOf: url),
           let cfg = try? JSONDecoder().decode(Config.self, from: data) {
            return (cfg, false)
        }
        let cfg = defaultConfig()
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder.pretty.encode(cfg) {
            try? data.write(to: url, options: .atomic)
        }
        return (cfg, true)
    }

    public static func reload() -> Config? {
        guard let data = try? Data(contentsOf: configURL) else { return nil }
        return try? JSONDecoder().decode(Config.self, from: data)
    }
}

extension JSONEncoder {
    static var pretty: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
}
