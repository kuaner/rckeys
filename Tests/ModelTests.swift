import Testing
import Foundation
import Carbon.HIToolbox
@testable import RCKeysCore

// 配置模型 / 键位表 / 可读描述 / 哑化 payload 的纯逻辑测试（原 --self-test 迁移并扩充）

// MARK: - HID 表与哑化

@Test func usageTableCoversAll13Keys() {
    #expect(RC003.usageByKey.count == 13)
    #expect(Set(RC003.usageByKey.values) == Set(RemoteKey.allCases))
    #expect(RC003.usageByKey[0x28] == .ok)
    #expect(RC003.usageByKey[0xF1] == .back)
}

@Test func neuterListExcludesBackKey() {
    // back(0xF1) 超出键盘页，hidutil 不接受映射，无需哑化
    #expect(Remap.neuters.count == 12)
    #expect(!Remap.neuters.contains(0xF1))
    #expect(Remap.neuters.contains(0x52))   // 方向
    #expect(Remap.neuters.contains(0x3E))   // 语音
}

@Test func hidutilPayloadAndMatching() {
    #expect(Remap.payload.contains("0x700000052"))
    #expect(Remap.payload.contains("0x70000003E"))
    #expect(Remap.payload.contains("0x700000000"))   // 目标 usage 0
    #expect(Remap.matching.contains("10007") && Remap.matching.contains("12984"))  // 十进制 VID/PID
}

// MARK: - 配置模型

@Test func defaultConfigRoundTripsThroughJSON() throws {
    let cfg = Config.defaultConfig()
    let data = try JSONEncoder.pretty.encode(cfg)
    let back = try JSONDecoder().decode(Config.self, from: data)
    #expect(back == cfg)
    #expect(back.keys.count == RemoteKey.allCases.count)
}

@Test func repeatActionEncodesAsRepeatKey() throws {
    // JSON 字段名必须是 "repeat"（README 示例与旧配置兼容）
    let kc = KeyConfig(tap: nil, hold: nil, double: nil, repeatAction: .key("arrowup"))
    let json = String(data: try JSONEncoder.pretty.encode(kc), encoding: .utf8)!
    #expect(json.contains("\"repeat\""))
    let back = try JSONDecoder().decode(KeyConfig.self, from: Data(json.utf8))
    #expect(back.repeatAction == .key("arrowup"))
}

@Test func decodesLegacyHandWrittenJSON() throws {
    let legacy = """
    {"settings":{"holdMs":400,"doubleMs":300,"repeatMs":80,"repeatDelayMs":300},
     "keys":{"back":{"tap":{"type":"key","combo":"delete"},"hold":{"type":"key","combo":"esc"}},
             "volup":{"tap":{"type":"media","name":"volume_up"},"repeat":{"type":"media","name":"volume_up"}},
             "voice":{"hold":{"type":"key","combo":"fn"}},
             "menu":{"tap":{"type":"mouse","name":"right"}},
             "power":{"hold":{"type":"shell","command":"pmset displaysleepnow"}}}}
    """
    let cfg = try JSONDecoder().decode(Config.self, from: Data(legacy.utf8))
    #expect(cfg.settings.holdMs == 400)
    #expect(cfg.keys["back"]?.hold == .key("esc"))
    #expect(cfg.keys["volup"]?.repeatAction?.name == "volume_up")
    #expect(cfg.keys["voice"]?.hold == .key("fn"))
    #expect(cfg.keys["power"]?.hold?.command == "pmset displaysleepnow")
}

@Test func settingsDefaults() {
    let s = Settings()
    #expect(s.holdMs == 350)
    #expect(s.doubleMs == 250)
    #expect(s.repeatMs == 100)
    #expect(s.repeatDelayMs == 350)
}

@Test func remoteKeyRawValuesAreStableAndLowercase() {
    #expect(RemoteKey.allCases.count == 13)
    #expect(RemoteKey.volUp.rawValue == "volup")
    #expect(RemoteKey.volDown.rawValue == "voldown")
    #expect(RemoteKey.allCases.allSatisfy { $0.rawValue == $0.rawValue.lowercased() })
}

// MARK: - 动作键位表

@Test func keyCodeTable() {
    #expect(Actions.codes["return"] == CGKeyCode(kVK_Return))
    #expect(Actions.codes["arrowup"] == CGKeyCode(kVK_UpArrow))
    #expect(Actions.codes["arrowleft"] == CGKeyCode(kVK_LeftArrow))
    #expect(Actions.codes["a"] == CGKeyCode(kVK_ANSI_A))
    #expect(Actions.codes["f1"] == CGKeyCode(kVK_F1))
    #expect(Actions.codes["f12"] == CGKeyCode(kVK_F12))
    #expect(Actions.codes["missioncontrol"] == 160)
}

@Test func modifierMasksIncludeFnAndAliases() {
    #expect(Actions.modifierMasks["fn"] == .maskSecondaryFn)
    #expect(Actions.modifierMasks["option"] == .maskAlternate)
    #expect(Actions.isBareModifier("fn"))
    #expect(Actions.isBareModifier("shift"))
    #expect(!Actions.isBareModifier("fn+arrowup"))
    #expect(!Actions.isBareModifier("space"))
}

@Test func mediaKeyCodes() {
    #expect(Actions.mediaKeys["volume_up"] == 0)
    #expect(Actions.mediaKeys["volume_down"] == 1)
    #expect(Actions.mediaKeys["mute"] == 7)
    #expect(Actions.mediaKeys["play"] == 16)
    #expect(Actions.mediaKeys["fast"] == 19 && Actions.mediaKeys["rewind"] == 20)
}

@Test func describeFormat() {
    #expect(Actions.describe(.key("ctrl+cmd+q")) == "key ctrl+cmd+q")
    #expect(Actions.describe(.media("mute")) == "media mute")
    #expect(Actions.describe(Action(type: "open", name: "Safari")) == "open Safari")
}

// MARK: - 可读描述（Pretty）

@Test func prettyActionKeyWithModifierNames() {
    #expect(Pretty.action(.key("ctrl+cmd+q")) == "⌃ control ⌘ command Q")
    #expect(Pretty.action(.key("fn")) == "🌐 fn")
    #expect(Pretty.action(.key("")) == "未设置组合")
}

@Test func prettyActionMediaNames() {
    #expect(Pretty.action(.media("volume_up")) == "音量+")
    #expect(Pretty.action(.media("rewind")) == "快退")
    #expect(Pretty.action(.media("unknown")) == "媒体键")
}

@Test func prettyActionOtherTypes() {
    #expect(Pretty.action(Action(type: "mouse", name: "left")) == "左键点击")
    #expect(Pretty.action(Action(type: "open", name: "NeteaseMusic")) == "打开 NeteaseMusic")
    #expect(Pretty.action(Action(type: "open", name: "")) == "未选择 App")
    #expect(Pretty.action(Action(type: "shell", command: "pmset")) == "▶ pmset")
    #expect(Pretty.action(Action.none) == "无动作")   // 注意不能写 .none（Action? 上下文会变成 nil）
    #expect(Pretty.action(nil) == "—")
}

@Test func prettyShellCommandTruncated() {
    let long = String(repeating: "x", count: 50)
    let out = Pretty.action(Action(type: "shell", command: long))
    #expect(out == "▶ " + String(repeating: "x", count: 30) + "…")
}

@Test func comboPartsParsesModifiersAndKeys() {
    #expect(Pretty.comboParts("cmd+shift+tab") == ["⌘ command", "⇧ shift", "⇥"])
    #expect(Pretty.comboParts("ctrl+alt+delete") == ["⌃ control", "⌥ option", "⌫"])
    #expect(Pretty.comboParts("fn") == ["🌐 fn"])          // 裸修饰键单键帽
    #expect(Pretty.comboParts("cmd") == ["⌘ command"])
    #expect(Pretty.comboParts("f5") == ["F5"])
    #expect(Pretty.comboParts("a") == ["A"])
    #expect(Pretty.comboParts("missioncontrol") == ["调度中心"])
    #expect(Pretty.comboParts("").isEmpty)
    #expect(Pretty.comboParts(nil).isEmpty)
}

@Test func keyDisplayHandlesAliasesAndCase() {
    #expect(Pretty.keyDisplay("control") == "⌃ control")   // 别名归一
    #expect(Pretty.keyDisplay("ALT") == "⌥ option")
    #expect(Pretty.keyDisplay("f9") == "F9")
    #expect(Pretty.keyDisplay("q") == "Q")
    #expect(Pretty.keyDisplay("unknownkey") == "unknownkey")
}

// MARK: - 触发位

@Test func triggerKindRoundTripsAllSlots() {
    let kc = KeyConfig(tap: .key("return"), hold: .key("esc"),
                       double: .key("space"), repeatAction: .key("arrowup"))
    #expect(TriggerKind.tap.action(in: kc) == .key("return"))
    #expect(TriggerKind.hold.action(in: kc) == .key("esc"))
    #expect(TriggerKind.double.action(in: kc) == .key("space"))
    #expect(TriggerKind.repeatAction.action(in: kc) == .key("arrowup"))
}

@Test func systemGestureIsMenuHold() {
    #expect(ServiceGesture.key == .menu)
    #expect(ServiceGesture.kind == "hold")
}
