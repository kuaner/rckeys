import SwiftUI
import AppKit
import UniformTypeIdentifiers

// 单触发编辑器：动作类型大卡片 + 各类型聚焦的参数编辑 + 统一操作行（试一试/清除）。
// 设计原则：一次只编辑一个触发；主交互 = 点选 + 真键盘录制。

// MARK: - 可读描述（卡片摘要、左侧键摘要共用；self-test 覆盖）

enum Pretty {
    /// 修饰键显示名（与实体键盘印字一致：符号 + 名称，便于对应物理键）
    static let modDisplays = [
        "ctrl": "⌃ control", "control": "⌃ control",
        "alt": "⌥ option", "option": "⌥ option",
        "shift": "⇧ shift",
        "cmd": "⌘ command", "command": "⌘ command",
        "fn": "🌐 fn",
    ]
    static let keyNames: [String: String] = [
        "arrowup": "↑", "arrowdown": "↓", "arrowleft": "←", "arrowright": "→",
        "return": "↩", "delete": "⌫", "forwarddelete": "⌦", "esc": "esc", "tab": "⇥",
        "space": "空格", "capslock": "⇪", "home": "↖", "end": "↘",
        "pageup": "⇞", "pagedown": "⇟", "help": "help",
        "missioncontrol": "调度中心", "launchpad": "启动台",
        "cmdright": "右⌘", "ctrlright": "右⌃", "shiftright": "右⇧", "optright": "右⌥",
    ]
    static let mediaNames = [
        "volume_up": "音量+", "volume_down": "音量−", "mute": "静音",
        "brightness_up": "亮度+", "brightness_down": "亮度−",
        "play": "播放/暂停", "next": "下一首", "prev": "上一首",
        "fast": "快进", "rewind": "快退",
    ]

    static func keyDisplay(_ raw: String) -> String {
        let k = raw.lowercased()
        if let s = modDisplays[k] { return s }
        if let n = keyNames[k] { return n }
        if k.count == 1, let c = k.first, c.isLetter { return k.uppercased() }
        if k.hasPrefix("f"), Int(k.dropFirst()) != nil { return k.uppercased() }
        return raw
    }

    /// combo -> 键帽部件序列（"ctrl+cmd+q" -> ["⌃","⌘","Q"]；裸修饰键 "fn" -> ["🌐"]）
    static func comboParts(_ combo: String?) -> [String] {
        guard let combo, !combo.isEmpty else { return [] }
        let parts = combo.split(separator: "+").map(String.init)
        if parts.count == 1, let s = modDisplays[parts[0].lowercased()] { return [s] }
        return parts.map(keyDisplay)
    }

    static func action(_ a: Action?) -> String {
        guard let a else { return "—" }
        switch a.type {
        case "key":
            let parts = comboParts(a.combo)
            return parts.isEmpty ? "未设置组合" : parts.joined(separator: " ")
        case "media": return mediaNames[a.name ?? ""] ?? "媒体键"
        case "mouse": return (a.name == "left") ? "左键点击" : "右键点击"
        case "open":
            guard let n = a.name, !n.isEmpty else { return "未选择 App" }
            return "打开 \(n)"
        case "shell":
            guard let c = a.command, !c.isEmpty else { return "Shell（空命令）" }
            return "▶ " + (c.count > 30 ? String(c.prefix(30)) + "…" : c)
        default: return "无动作"
        }
    }
}

extension Text {
    /// 显示串渲染：🌐 emoji 替换为单色 SF Symbol，与 ⌃⌥⇧⌘ 线性符号一致（键盘印字同款风格）。
    /// 仅渲染层替换，Pretty 里的字符串值不变。
    static func display(_ s: String) -> Text {
        guard s.contains("🌐") else { return Text(verbatim: s) }
        var t: Text?
        for (i, piece) in s.components(separatedBy: "🌐").enumerated() {
            var seg = Text(verbatim: piece)
            if i > 0 { seg = Text(Image(systemName: "globe")) + seg }
            t = t == nil ? seg : t! + seg
        }
        return t ?? Text(verbatim: s)
    }
}

// MARK: - 单触发编辑器

/// 类型卡 = 纯视图切换（tab）：点选只查看该类型的参数界面，不写任何数据。
/// 保存的 action 是唯一状态；只有在参数区做出明确选择（点芯片/录制/点媒体键/
/// 选 App/输入命令/点「设为无动作」）时才写入，类型随首个选择一起落盘。
struct TriggerEditor: View {
    let kind: TriggerKind
    @Binding var action: Action?
    /// 当前展示的类型页；空 = 跟随已保存类型（未配置时落在「按键」页）
    @State private var tab: String = ""

    private var activeTab: String { tab.isEmpty ? (action?.type ?? "key") : tab }

    static let types: [(type: String, label: String, icon: String)] = [
        ("key", "按键", "keyboard"),
        ("media", "媒体键", "speaker.wave.2.fill"),
        ("mouse", "鼠标", "computermouse"),
        ("open", "打开App", "app.dashed"),
        ("shell", "Shell", "terminal"),
        ("none", "无动作", "nosign"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                ForEach(Self.types, id: \.type) { t in
                    typeCard(t)
                }
            }

            switch activeTab {
            case "key": KeyParamEditor(action: $action)
            case "media": MediaParamEditor(action: $action)
            case "mouse": MouseParamEditor(action: $action)
            case "open": OpenParamEditor(action: $action)
            case "shell": ShellParamEditor(action: $action)
            default: noneEditor
            }

            if let a = action {
                HStack {
                    Button {
                        Actions.perform(a)
                    } label: {
                        Label("试一试", systemImage: "play.fill")
                    }
                    .disabled(!canTest)
                    Spacer()
                    Button(role: .destructive) {
                        action = nil
                    } label: {
                        Label("清除", systemImage: "trash")
                    }
                }
            }
        }
    }

    private var noneEditor: some View {
        VStack(spacing: 10) {
            Text(action?.type == "none"
                 ? "此触发当前为「无动作」：引擎不执行任何操作。"
                 : "「无动作」= 手势触发时不执行任何操作。")
                .font(.callout).foregroundStyle(.secondary)
            if action?.type != "none" {
                Button("设为无动作") { action = .none }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private func typeCard(_ t: (type: String, label: String, icon: String)) -> some View {
        let isSel = activeTab == t.type
        return Button {
            tab = t.type // 纯视图切换，不写配置
        } label: {
            VStack(spacing: 6) {
                Image(systemName: t.icon).font(.title3)
                Text(t.label).font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isSel ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(isSel ? Color.accentColor : Color(nsColor: .separatorColor).opacity(0.5),
                        lineWidth: isSel ? 1.5 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var canTest: Bool {
        guard let a = action else { return false }
        switch a.type {
        case "key": return !(a.combo ?? "").isEmpty
        case "media": return a.name != nil
        case "open": return !(a.name ?? "").isEmpty
        case "shell": return !(a.command ?? "").isEmpty
        default: return false
        }
    }
}

// MARK: - 按键编辑（键帽显示 + 录制为主交互 + 折叠键位面板）

// MARK: - 按键编辑（键帽显示当前组合；分组点选面板为主交互；底部真键盘录制）

struct KeyParamEditor: View {
    @Binding var action: Action?
    @State private var recording = false

    /// 仅当已保存类型是按键时显示其组合，浏览其他类型页时不虚构数据
    private var combo: String {
        (action?.type == "key" ? action?.combo : nil) ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !Pretty.comboParts(combo).isEmpty {
                KeyCapRow(parts: Pretty.comboParts(combo))
            }
            KeyPalette(combo: Binding(get: { combo },
                                      set: { action = Action(type: "key", combo: $0) }))
            Button {
                toggleRecording()
            } label: {
                Label(recording ? "Esc 取消" : "用真键盘录制",
                      systemImage: recording ? "stop.circle.fill" : "record.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(recording ? .red : .accentColor)
            if recording {
                Text("按下要录制的组合键；按住单个修饰键 0.7 秒 = 录为单修饰键动作")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        // 上下文切走时结束录制，避免补录写到旧上下文
        .onDisappear { ComboRecorder.shared.stop() }
    }

    private func toggleRecording() {
        if recording {
            ComboRecorder.shared.stop()
            recording = false
        } else {
            recording = true
            ComboRecorder.shared.record { c in
                recording = false
                if let c = c { action = Action(type: "key", combo: c) }
            }
        }
    }
}

/// 键帽式组合键显示（如 ⌃ ⌘ Q 三个圆角块）
struct KeyCapRow: View {
    let parts: [String]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(parts.indices, id: \.self) { i in
                Text.display(parts[i])
                    .font(.system(size: 16, weight: .medium))
                    .padding(.horizontal, 9).padding(.vertical, 6)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor)))
                    .shadow(color: .black.opacity(0.06), radius: 1, y: 1)
            }
        }
    }
}

/// 简易流式布局：子视图按自身宽度换行排列（键帽芯片用）
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width
            ?? subviews.reduce(CGFloat(0)) { $0 + $1.sizeThatFits(.unspecified).width + spacing }
        return CGSize(width: width, height: arrange(width: width, subviews: subviews).height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (i, sub) in subviews.enumerated() {
            let p = arrange(width: bounds.width, subviews: subviews).positions[i]
            sub.place(at: CGPoint(x: bounds.minX + p.x, y: bounds.minY + p.y),
                      anchor: .topLeading, proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (positions: [CGPoint], height: CGFloat) {
        var positions: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0; y += rowH + spacing; rowH = 0
            }
            positions.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
        return (positions, y + rowH)
    }
}

/// 折叠键位面板：按组分类的键帽点选（修饰键/方向/常用/功能键）+ 手动输入
struct KeyPalette: View {
    @Binding var combo: String
    @State private var mods: Set<String> = []
    @State private var mainKey: String = ""

    static let modOrder = ["ctrl", "alt", "shift", "cmd", "fn"]
    static let navKeys: [(label: String, value: String)] = [
        ("←", "arrowleft"), ("↑", "arrowup"), ("↓", "arrowdown"), ("→", "arrowright"),
        ("home", "home"), ("end", "end"), ("pg↑", "pageup"), ("pg↓", "pagedown"),
    ]
    static let commonKeys: [(label: String, value: String)] = [
        ("esc", "esc"), ("↩", "return"), ("⌫", "delete"), ("⇥", "tab"), ("空格", "space"),
        ("任务", "missioncontrol"), ("启动台", "launchpad"),
    ]
    static let fKeys: [(label: String, value: String)] = (1...12).map { ("F\($0)", "f\($0)") }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            group("修饰键", Self.modOrder.map { (Pretty.modDisplays[$0] ?? $0, $0) },
                  isActive: { mods.contains($0) }, onClick: { toggleMod($0) })
            group("方向 / 翻页", Self.navKeys,
                  isActive: { mainKey == $0 }, onClick: { setMain($0) })
            group("常用键", Self.commonKeys,
                  isActive: { mainKey == $0 }, onClick: { setMain($0) })
            group("功能键", Self.fKeys,
                  isActive: { mainKey == $0 }, onClick: { setMain($0) })
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onAppear { parse(combo) }
        .onChange(of: combo) { _, new in parse(new) }
    }

    private func group(_ title: String, _ keys: [(label: String, value: String)],
                       isActive: @escaping (String) -> Bool,
                       onClick: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption2).foregroundStyle(.tertiary)
            FlowLayout(spacing: 6) {
                ForEach(keys, id: \.value) { k in
                    chip(k.label, active: isActive(k.value)) { onClick(k.value) }
                }
            }
        }
    }

    private func chip(_ label: String, active: Bool, onClick: @escaping () -> Void) -> some View {
        Button(action: onClick) {
            Text.display(label)
                .font(.system(size: 12, weight: active ? .semibold : .regular))
                .frame(minWidth: 36)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(active ? Color.accentColor.opacity(0.15)
                                   : Color(nsColor: .windowBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(active ? Color.accentColor : Color(nsColor: .separatorColor),
                            lineWidth: active ? 1.5 : 1))
                .shadow(color: .black.opacity(0.05), radius: 1, y: 1)
        }
        .buttonStyle(.plain)
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
        combo = mainKey.isEmpty ? ordered.joined(separator: "+")
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
}

// MARK: - 媒体键编辑（图标网格，含引擎已支持的快进/快退）

struct MediaParamEditor: View {
    @Binding var action: Action?

    static let items: [(name: String, label: String, icon: String)] = [
        ("volume_up", "音量+", "speaker.wave.3.fill"),
        ("volume_down", "音量−", "speaker.wave.1.fill"),
        ("mute", "静音", "speaker.slash.fill"),
        ("brightness_up", "亮度+", "sun.max.fill"),
        ("brightness_down", "亮度−", "sun.min.fill"),
        ("play", "播放/暂停", "playpause.fill"),
        ("prev", "上一首", "backward.end.fill"),
        ("next", "下一首", "forward.end.fill"),
        ("rewind", "快退", "backward.fill"),
        ("fast", "快进", "forward.fill"),
    ]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(78), spacing: 8), count: 5),
                  alignment: .leading, spacing: 8) {
            ForEach(Self.items, id: \.name) { item in
                let isSel = action?.type == "media" && action?.name == item.name
                Button { action = .media(item.name) } label: {
                    VStack(spacing: 6) {
                        Image(systemName: item.icon).font(.title3)
                        Text(item.label).font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(isSel ? Color.accentColor.opacity(0.12)
                                      : Color(nsColor: .controlBackgroundColor))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isSel ? Color.accentColor : Color(nsColor: .separatorColor).opacity(0.5)))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - 鼠标编辑

struct MouseParamEditor: View {
    @Binding var action: Action?

    var body: some View {
        HStack(spacing: 12) {
            option("左键点击", "left", "computermouse")
            option("右键点击", "right", "computermouse.fill")
        }
    }

    private func option(_ label: String, _ value: String, _ icon: String) -> some View {
        let isSel = action?.type == "mouse" && action?.name == value
        return Button { action = Action(type: "mouse", name: value) } label: {
            Label(label, systemImage: icon)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(isSel ? Color.accentColor.opacity(0.12)
                                  : Color(nsColor: .controlBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSel ? Color.accentColor : Color(nsColor: .separatorColor).opacity(0.5)))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 打开 App 编辑（含已选 App 图标）

struct OpenParamEditor: View {
    @Binding var action: Action?

    /// 仅当已保存类型是 open 时显示其 App 名
    private var appName: String {
        action?.type == "open" ? (action?.name ?? "") : ""
    }

    private var appIcon: NSImage? {
        guard !appName.isEmpty else { return nil }
        for dir in ["/Applications", NSHomeDirectory() + "/Applications"] {
            let p = "\(dir)/\(appName).app"
            if FileManager.default.fileExists(atPath: p) { return NSWorkspace.shared.icon(forFile: p) }
        }
        return nil
    }

    var body: some View {
        HStack(spacing: 14) {
            if let icon = appIcon {
                Image(nsImage: icon).resizable().frame(width: 40, height: 40)
            } else {
                Image(systemName: "app.dashed").font(.title).foregroundStyle(.tertiary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(appName.isEmpty ? "未选择 App" : appName).font(.body.weight(.medium))
                Text(appName.isEmpty
                     ? "从 /Applications 选择要打开的应用"
                     : "执行 open -b \(action?.command ?? appName)（bundle id）")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("选择…") { pick() }
            if !appName.isEmpty {
                Button { action = nil } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            // name 留作显示；command 存 bundle id（open -b），改名/更新不影响
            action = Action(type: "open",
                            name: url.deletingPathExtension().lastPathComponent,
                            command: Bundle(url: url)?.bundleIdentifier)
        }
    }
}

// MARK: - Shell 编辑

struct ShellParamEditor: View {
    @Binding var action: Action?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("如 pmset displaysleepnow", text: Binding(
                get: { (action?.type == "shell" ? action?.command : nil) ?? "" },
                set: { action = Action(type: "shell", command: $0) }))
                .textFieldStyle(.roundedBorder)
            Text("以 /bin/zsh -c 执行").font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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

        // keyDown：修饰键 + 主键。
        // fn 在 flags 里常是设备标志（笔记本方向键/Home/End/F 区等自带 SecondaryFn），
        // 不代表用户按了 fn 键——录制组合键时忽略，避免出现幽灵 🌐；
        // 裸 fn 动作仍由上方 flagsChanged 的「按住 0.7 秒」路径录制。
        let code = CGKeyCode(truncatingIfNeeded: e.getIntegerValueField(.keyboardEventKeycode))
        guard let name = Actions.codeNames[code] else { return }
        let mods = Self.modNames(in: e.flags).filter { $0 != "fn" }
        if name == "esc" && mods.isEmpty { finish(nil); return } // 裸 Esc = 取消
        finish((mods.filter { $0 != name } + [name]).joined(separator: "+"))
    }
}
