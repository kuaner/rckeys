import SwiftUI
import AppKit
import UniformTypeIdentifiers

// 可视化配置界面：左侧遥控器实拍图 + 热点选键，右侧编辑四个触发位。
// 热点坐标与照片源自 HD838A/remote-mic-app（GPL-3.0）的 RemoteMappingLayout，致谢。

// MARK: - 窗口管理

final class ConfigWindowController {
    static let shared = ConfigWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 880, height: 600),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false)
            w.title = "RCKeys 按键配置"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: ConfigEditorView())
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - 热点表（归一化坐标，照片按 .fill 裁切到 202×410 显示）

struct Hotspot: Identifiable {
    let key: RemoteKey
    let anchor: UnitPoint
    let label: String
    var id: RemoteKey { key }
}

let hotspots: [Hotspot] = [
    .init(key: .power,  anchor: UnitPoint(x: 0.386, y: 0.099), label: "电源"),
    .init(key: .voice,  anchor: UnitPoint(x: 0.630, y: 0.099), label: "语音"),
    .init(key: .up,     anchor: UnitPoint(x: 0.502, y: 0.179), label: "上"),
    .init(key: .ok,     anchor: UnitPoint(x: 0.502, y: 0.246), label: "OK"),
    .init(key: .down,   anchor: UnitPoint(x: 0.502, y: 0.317), label: "下"),
    .init(key: .left,   anchor: UnitPoint(x: 0.362, y: 0.246), label: "左"),
    .init(key: .right,  anchor: UnitPoint(x: 0.638, y: 0.246), label: "右"),
    .init(key: .back,   anchor: UnitPoint(x: 0.406, y: 0.389), label: "返回"),
    .init(key: .home,   anchor: UnitPoint(x: 0.406, y: 0.479), label: "主页"),
    .init(key: .menu,   anchor: UnitPoint(x: 0.406, y: 0.569), label: "菜单"),
    .init(key: .volUp,  anchor: UnitPoint(x: 0.604, y: 0.390), label: "音量+"),
    .init(key: .volDown,anchor: UnitPoint(x: 0.604, y: 0.480), label: "音量−"),
    .init(key: .tv,     anchor: UnitPoint(x: 0.604, y: 0.569), label: "TV"),
]

let remotePhoto: NSImage? = {
    guard let url = Bundle.main.url(forResource: "RC003-remote-photo",
                                    withExtension: "png", subdirectory: "Resources")
        ?? Bundle.main.url(forResource: "RC003-remote-photo", withExtension: "png")
        ?? Optional(URL(fileURLWithPath: "Resources/RC003-remote-photo.png")) else { return nil }
    return NSImage(contentsOf: url)
}()

// MARK: - 主界面

struct ConfigEditorView: View {
    @State private var cfg: Config = Config.loadOrDefault().0
    @State private var selected: RemoteKey = .ok
    @State private var hovered: RemoteKey?
    @State private var savedFlash = false

    var body: some View {
        HStack(spacing: 0) {
            remotePane
                .frame(width: 300)
                .background(Color(nsColor: .windowBackgroundColor))
            Divider()
            editorPane
                .frame(minWidth: 420)
        }
    }

    // MARK: 左侧：遥控器图 + 热点

    private var remotePane: some View {
        VStack(spacing: 16) {
            Text("点选按键进行配置")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 20)
            ZStack {
                Group {
                    if let photo = remotePhoto {
                        Image(nsImage: photo).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Rectangle().fill(Color.gray.opacity(0.25))
                    }
                }
                .frame(width: 202, height: 410)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                ForEach(hotspots) { hs in
                    let isSel = hs.key == selected
                    let isHov = hs.key == hovered
                    ZStack {
                        // 仅选中/悬停时出现柔和高亮，平时完全隐形
                        if isSel || isHov {
                            Circle()
                                .fill(Color.accentColor.opacity(isSel ? 0.35 : 0.16))
                                .blur(radius: isSel ? 0 : 3)
                            if isSel {
                                Circle().stroke(Color.accentColor, lineWidth: 1.8)
                            }
                        } else {
                            Color.clear
                        }
                    }
                    .frame(width: 46, height: 46)
                    .contentShape(Circle())
                    .onTapGesture { selected = hs.key }
                    .onHover { h in withAnimation(.easeInOut(duration: 0.12)) { hovered = h ? hs.key : nil } }
                    .position(x: 202 * hs.anchor.x, y: 410 * hs.anchor.y)
                }
            }
            .frame(width: 202, height: 410)
            Text(keySummary(selected))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 16)
        }
    }

    private func keySummary(_ k: RemoteKey) -> String {
        guard let kc = cfg.keys[k.rawValue] else { return "未配置" }
        var parts: [String] = []
        if let a = kc.tap { parts.append("单击:" + Actions.describe(a)) }
        if let a = kc.hold { parts.append("长按:" + Actions.describe(a)) }
        if let a = kc.double { parts.append("双击:" + Actions.describe(a)) }
        if let a = kc.repeatAction { parts.append("连发:" + Actions.describe(a)) }
        return parts.isEmpty ? "未配置任何动作" : parts.joined(separator: "  ")
    }

    // MARK: 右侧：编辑器

    private var editorPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("「\(hotspots.first { $0.key == selected }?.label ?? selected.rawValue)」键")
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Button(savedFlash ? "已保存 ✓" : "保存配置") { save() }
                        .disabled(savedFlash)
                    Button("恢复默认") { cfg = Config.defaultConfig() }
                }

                let kc = bindingFor(selected)
                TriggerRow(label: "单击（未配双击时零延迟）", action: subBinding(kc, \.tap))
                TriggerRow(label: "长按（\(cfg.settings.holdMs)ms）", action: subBinding(kc, \.hold),
                           conflictHint: (cfg.keys[selected.rawValue]?.repeatAction != nil && cfg.keys[selected.rawValue]?.hold != nil)
                            ? "长按与连发互斥，长按优先" : nil)
                TriggerRow(label: "双击（\(cfg.settings.doubleMs)ms 窗口，会给单击引入延迟）", action: subBinding(kc, \.double))
                TriggerRow(label: "长按连发（延迟 \(cfg.settings.repeatDelayMs)ms / 间隔 \(cfg.settings.repeatMs)ms）",
                           action: subBinding(kc, \.repeatAction),
                           conflictHint: (cfg.keys[selected.rawValue]?.repeatAction != nil && cfg.keys[selected.rawValue]?.hold != nil)
                            ? "长按与连发互斥，长按优先" : nil)

                Divider()
                Text("全局手感参数").font(.headline)
                timingStepper("长按判定", $cfg.settings.holdMs, 150...800, "ms")
                timingStepper("双击窗口", $cfg.settings.doubleMs, 150...500, "ms")
                timingStepper("连发间隔", $cfg.settings.repeatMs, 30...300, "ms")
                timingStepper("连发起始延迟", $cfg.settings.repeatDelayMs, 150...800, "ms")

                Divider()
                Text("组合键写法：ctrl+cmd+q、arrowup、return、f5。录制：按任意组合键即录；按住单个修饰键（含 fn/🌐）0.7 秒 = 录为单修饰键动作；Esc 取消。\n⚠️ 想用 fn 键：先把 系统设置>键盘>「按下 🌐 键时」改为「什么都不做」，否则会弹表情选择。")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(24)
        }
    }

    private func bindingFor(_ k: RemoteKey) -> Binding<KeyConfig> {
        Binding(
            get: { cfg.keys[k.rawValue] ?? KeyConfig(tap: nil, hold: nil, double: nil, repeatAction: nil) },
            set: { cfg.keys[k.rawValue] = $0 }
        )
    }

    private func subBinding(_ kc: Binding<KeyConfig>, _ keyPath: WritableKeyPath<KeyConfig, Action?>) -> Binding<Action?> {
        Binding(get: { kc.wrappedValue[keyPath: keyPath] },
                set: { var v = kc.wrappedValue; v[keyPath: keyPath] = $0; kc.wrappedValue = v })
    }

    private func timingStepper(_ label: String, _ value: Binding<Int>, _ range: ClosedRange<Int>, _ unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Stepper(value: value, in: range, step: 10) {
                Text("\(value.wrappedValue)\(unit)").monospacedDigit().frame(width: 90, alignment: .trailing)
            }
        }
        .frame(maxWidth: 360, alignment: .leading)
    }

    private func save() {
        if let data = try? JSONEncoder.pretty.encode(cfg) {
            try? FileManager.default.createDirectory(at: Config.configDir, withIntermediateDirectories: true)
            try? data.write(to: Config.configURL, options: .atomic)
            // 文件监听会自动热加载到引擎；这里直接闪提示
            savedFlash = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { savedFlash = false }
        }
    }
}

// MARK: - 单个触发位编辑

struct TriggerRow: View {
    let label: String
    @Binding var action: Action?
    var conflictHint: String? = nil
    @State private var recording = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle(isOn: Binding(
                    get: { action != nil },
                    set: { action = $0 ? Action.none : nil })) {
                    Text(label).font(.body.weight(.medium))
                }
                .toggleStyle(.switch)
                .frame(maxWidth: 460, alignment: .leading)
            }
            if let hint = conflictHint {
                Text(hint).font(.caption).foregroundStyle(.orange)
            }
            if action != nil {
                ActionEditor(action: Binding(
                    get: { action ?? Action.none },
                    set: { action = $0 }))
                    .padding(.leading, 8)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(nsColor: .separatorColor).opacity(0.5)))
    }
}

struct ActionEditor: View {
    @Binding var action: Action
    @State private var recording = false
    @State private var mods: Set<String> = []
    @State private var mainKey: String = ""

    // 显示名 -> 键值（键值与 Actions.codes 表一致）
    static let modOrder = ["ctrl", "alt", "shift", "cmd", "fn"]
    static let commonKeys: [(label: String, value: String)] = [
        ("esc", "esc"), ("↩", "return"), ("⌫", "delete"), ("tab", "tab"), ("space", "space"),
        ("←", "arrowleft"), ("↑", "arrowup"), ("↓", "arrowdown"), ("→", "arrowright"),
        ("home", "home"), ("end", "end"), ("pg↑", "pageup"), ("pg↓", "pagedown"),
        ("任务", "missioncontrol"), ("启动台", "launchpad"),
    ] + (1...12).map { ("f\($0)", "f\($0)") }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Picker("类型", selection: Binding(
                    get: { action.type },
                    set: { action.type = $0 })) {
                    Text("按键").tag("key")
                    Text("媒体键").tag("media")
                    Text("鼠标").tag("mouse")
                    Text("打开App").tag("open")
                    Text("Shell").tag("shell")
                    Text("无动作").tag("none")
                }
                .pickerStyle(.menu)
                .frame(width: 110)

                switch action.type {
                case "key": keyEditor
                case "media": mediaEditor
                case "mouse": mouseEditor
                case "open": openEditor
                case "shell": shellEditor
                default: EmptyView()
                }
            }
            if action.type == "key" { keyPalette }
        }
    }

    // MARK: 按键编辑（录入框 + 录制）

    private var keyEditor: some View {
        HStack(spacing: 10) {
            TextField("如 ctrl+cmd+q", text: nonOpt($action.combo))
                .textFieldStyle(.roundedBorder)
                .frame(width: 190)
                .onSubmit { parse(action.combo ?? "") }
                .dropDestination(for: String.self) { items, _ in
                    guard let v = items.first else { return false }
                    applyChip(v)
                    return true
                }
            Button(recording ? "● 录制中…（Esc 取消）" : "🎙 录制") {
                if recording { ComboRecorder.shared.stop(); recording = false; return }
                recording = true
                ComboRecorder.shared.record { combo in
                    recording = false
                    if let c = combo { action.combo = c }
                }
            }
        }
    }

    // 芯片面板：修饰键（点选/拖入=切换）+ 常用键（点选/拖入=设为主键）
    private var keyPalette: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ForEach(Self.modOrder, id: \.self) { m in
                    chip(m, active: mods.contains(m)) { toggleMod(m) }
                }
                Spacer()
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(46), spacing: 4), count: 10),
                      alignment: .leading, spacing: 4) {
                ForEach(Self.commonKeys, id: \.value) { k in
                    chip(k.label, active: mainKey == k.value) { setMain(k.value) }
                }
            }
            Text("点选或拖入输入框组合；修饰键按住录制 0.7s = 单修饰键")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .dropDestination(for: String.self) { items, _ in
            guard let v = items.first else { return false }
            applyChip(v)
            return true
        }
        .onAppear { parse(action.combo ?? "") }
        .onChange(of: action.combo) { _, new in parse(new ?? "") }
    }

    private func chip(_ label: String, active: Bool, onClick: @escaping () -> Void) -> some View {
        Button(action: onClick) {
            Text(label)
                .font(.system(size: 11, weight: active ? .semibold : .regular))
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(active ? Color.accentColor.opacity(0.30) : Color(nsColor: .quaternaryLabelColor).opacity(0.5))
                .overlay(Capsule().stroke(active ? Color.accentColor : .clear, lineWidth: 1))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .onDrag { NSItemProvider(object: label as NSString) }
    }

    // MARK: 芯片状态 <-> combo 字符串 同步

    private func applyChip(_ label: String) {
        let value = Self.commonKeys.first { $0.label == label }?.value ?? label
        if Self.modOrder.contains(value) { toggleMod(value) } else { setMain(value) }
    }

    private func toggleMod(_ m: String) {
        if mods.contains(m) { mods.remove(m) } else { mods.insert(m) }
        rebuild()
    }

    private func setMain(_ k: String) {
        mainKey = (mainKey == k) ? "" : k
        rebuild()
    }

    private func rebuild() {
        let ordered = Self.modOrder.filter { mods.contains($0) }
        action.combo = mainKey.isEmpty ? ordered.joined(separator: "+")
                                       : (ordered + [mainKey]).joined(separator: "+")
    }

    private func parse(_ combo: String) {
        let parts = combo.split(separator: "+").map(String.init).map { $0.lowercased() }
        var newMods: Set<String> = []
        var newMain = ""
        for (i, p) in parts.enumerated() {
            if Self.modOrder.contains(p) && i < parts.count - 1 { newMods.insert(p) }
            else if Self.modOrder.contains(p) && parts.count == 1 { newMods.insert(p) }
            else { newMain = p }
        }
        if newMods != mods { mods = newMods }
        if newMain != mainKey { mainKey = newMain }
    }

    // MARK: 其他类型

    private var mediaEditor: some View {
        Picker("", selection: nonOpt($action.name)) {
            ForEach(["volume_up", "volume_down", "mute", "brightness_up",
                     "brightness_down", "play", "next", "prev"], id: \.self) { Text($0) }
        }
        .frame(width: 220)
    }

    private var mouseEditor: some View {
        Picker("", selection: nonOpt($action.name)) {
            Text("左键").tag("left"); Text("右键").tag("right")
        }
        .frame(width: 120)
    }

    private var openEditor: some View {
        HStack(spacing: 10) {
            if let n = action.name, !n.isEmpty {
                Image(systemName: "app").foregroundStyle(.secondary)
                Text(n).lineLimit(1).truncationMode(.middle)
            } else {
                Text("未选择 App").foregroundStyle(.tertiary)
            }
            Button("选择…") {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [UTType.application]
                panel.directoryURL = URL(fileURLWithPath: "/Applications")
                panel.canChooseDirectories = false
                panel.allowsMultipleSelection = false
                panel.canChooseFiles = true
                if panel.runModal() == .OK, let url = panel.url {
                    action.name = url.deletingPathExtension().lastPathComponent
                }
            }
            if action.name?.isEmpty == false {
                Button { action.name = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.tertiary)
            }
        }
    }

    private var shellEditor: some View {
        TextField("命令", text: nonOpt($action.command))
            .textFieldStyle(.roundedBorder)
            .frame(width: 320)
    }

    private func nonOpt(_ binding: Binding<String?>) -> Binding<String> {
        Binding(get: { binding.wrappedValue ?? "" }, set: { binding.wrappedValue = $0 })
    }
}

// MARK: - 真键盘组合键录制（listen-only CGEventTap，10 秒超时；裸 Esc 取消）
// 修饰键（含 fn/🌐）按住不动 0.7 秒 = 录为单修饰键动作。
// 注意：系统默认"按下🌐键=显示表情"，需在 系统设置>键盘 里改为"什么都不做"。

final class ComboRecorder {
    static let shared = ComboRecorder()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var timeout: DispatchWorkItem?
    private var holdCheck: DispatchWorkItem?
    private var onDone: ((String?) -> Void)?
    private var lastFlags: CGEventFlags = []

    static let interest: CGEventMask =
        CGEventMask(1 << CGEventType.keyDown.rawValue)
        | CGEventMask(1 << CGEventType.flagsChanged.rawValue)

    static func modNames(in flags: CGEventFlags) -> [String] {
        var names: [String] = []
        if flags.contains(.maskControl) { names.append("ctrl") }
        if flags.contains(.maskAlternate) { names.append("alt") }
        if flags.contains(.maskShift) { names.append("shift") }
        if flags.contains(.maskCommand) { names.append("cmd") }
        if flags.contains(.maskSecondaryFn) { names.append("fn") }
        return names
    }

    static func flagFor(_ name: String) -> CGEventFlags? {
        Actions.modifierMasks[name]
    }

    func record(_ completion: @escaping (String?) -> Void) {
        stop()
        onDone = completion
        lastFlags = CGEventSource.flagsState(.hidSystemState)
        guard let t = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: Self.interest,
            callback: { _, type, event, ctx in
                let r = Unmanaged<ComboRecorder>.fromOpaque(ctx!).takeUnretainedValue()
                r.handle(type, event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            completion(nil)
            return
        }
        tap = t
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        let w = DispatchWorkItem { [weak self] in self?.finish(nil) }
        timeout = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: w)
    }

    func stop() { finish(nil) }

    private func finish(_ combo: String?) {
        holdCheck?.cancel(); holdCheck = nil
        if let t = tap {
            CGEvent.tapEnable(tap: t, enable: false)
            if let s = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
        }
        tap = nil; source = nil
        timeout?.cancel(); timeout = nil
        onDone?(combo)
        onDone = nil
    }

    private func handle(_ type: CGEventType, _ e: CGEvent) {
        holdCheck?.cancel(); holdCheck = nil

        if type == .flagsChanged {
            let f = e.flags
            let newMods = Self.modNames(in: f.subtracting(lastFlags))
            lastFlags = f
            if let m = newMods.first, let mask = Self.flagFor(m) {
                // 按住不动 0.7s：录为裸修饰键
                let w = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    let cur = CGEventSource.flagsState(.hidSystemState)
                    if cur.contains(mask) { self.finish(m) }
                }
                holdCheck = w
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: w)
            }
            return
        }

        // keyDown：修饰键（含 fn）+ 主键
        let code = CGKeyCode(truncatingIfNeeded: e.getIntegerValueField(.keyboardEventKeycode))
        guard let name = Actions.codeNames[code] else { return }
        let mods = Self.modNames(in: e.flags)
        if name == "esc" && mods.isEmpty { finish(nil); return } // 裸 Esc = 取消
        finish((mods.filter { $0 != name } + [name]).joined(separator: "+"))
    }
}
