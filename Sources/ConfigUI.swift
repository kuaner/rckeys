import SwiftUI
import AppKit
import Combine

// 可视化配置界面：三层认知 —— 左侧选键（实拍图 + 热点）、
// 右上 4 张触发卡（摘要 + 点选）、右下只编辑选中的那一个触发。
// 全局手感设置独立成 Sheet；改动自动保存（防抖写盘 → 主程序文件监听热加载）。
// 热点坐标与照片源自 HD838A/remote-mic-app（GPL-3.0）的 RemoteMappingLayout，致谢。

// MARK: - 窗口管理

final class ConfigWindowController {
    static let shared = ConfigWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 920, height: 620),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false)
            w.title = "RCKeys 按键配置"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: ConfigEditorView())
            window = w
        }
        // 后台/accessory 应用抢前台受限：多重手段确保窗口可见
        window?.deminiaturize(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
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

// MARK: - 触发位

enum TriggerKind: String, CaseIterable, Identifiable {
    case tap, hold, double
    case repeatAction = "repeat"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .tap: return "单击"
        case .hold: return "长按"
        case .double: return "双击"
        case .repeatAction: return "连发"
        }
    }

    var keyPath: WritableKeyPath<KeyConfig, Action?> {
        switch self {
        case .tap: return \.tap
        case .hold: return \.hold
        case .double: return \.double
        case .repeatAction: return \.repeatAction
        }
    }

    func action(in kc: KeyConfig) -> Action? { kc[keyPath: keyPath] }
}

// MARK: - 视图模型（自动保存：防抖 500ms 写盘，主程序文件监听随后热加载）

final class ConfigViewModel: ObservableObject {
    @Published var cfg: Config
    @Published var savedFlash = false
    private var lastSaved: Config
    private var cancellables = Set<AnyCancellable>()
    private var flashToken = UUID()

    init() {
        let (cfg, _) = Config.loadOrDefault()
        self.cfg = cfg
        self.lastSaved = cfg
        $cfg
            .dropFirst()
            .removeDuplicates()
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] in self?.persist($0) }
            .store(in: &cancellables)
    }

    private func persist(_ c: Config) {
        guard c != lastSaved else { return }
        try? FileManager.default.createDirectory(at: Config.configDir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder.pretty.encode(c) {
            try? data.write(to: Config.configURL, options: .atomic)
            lastSaved = c
            savedFlash = true
            let token = UUID()
            flashToken = token
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                if self?.flashToken == token { self?.savedFlash = false }
            }
        }
    }
}

// MARK: - 主界面

struct ConfigEditorView: View {
    @StateObject private var model = ConfigViewModel()
    @ObservedObject private var service = ServiceHub.shared.status
    @State private var selected: RemoteKey = .ok
    @State private var selectedTrigger: TriggerKind = .tap
    @State private var hovered: RemoteKey?
    @State private var notice: String?
    @State private var noticeToken = UUID()
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                remotePane
                    .frame(width: 300)
                    .background(Color(nsColor: .windowBackgroundColor))
                Divider()
                editorPane
                    .frame(minWidth: 500)
            }
            footerBar
        }
        .sheet(isPresented: $showSettings) { SettingsSheet(cfg: $model.cfg) }
    }

    // MARK: 底部状态条：呼出提示 + 服务状态

    private var footerBar: some View {
        HStack(spacing: 8) {
            Text("遥控器：双击 TV 键打开此窗口")
            Spacer()
            Text(service.statusLine)
            if !service.note.isEmpty {
                Text("· \(service.note)").foregroundStyle(.orange)
            }
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(Divider(), alignment: .top)
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
                    .onTapGesture {
                        selected = hs.key
                        selectedTrigger = .tap // 换键固定回到单击位，不沿用上个键的触发选择
                    }
                    .onHover { h in withAnimation(.easeInOut(duration: 0.12)) { hovered = h ? hs.key : nil } }
                    .position(x: 202 * hs.anchor.x, y: 410 * hs.anchor.y)
                }
            }
            .frame(width: 202, height: 410)
            Text.display(keySummary(selected))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
    }

    private func keySummary(_ k: RemoteKey) -> String {
        guard let kc = model.cfg.keys[k.rawValue] else { return "未配置" }
        let parts = TriggerKind.allCases.compactMap { kind -> String? in
            guard let a = kind.action(in: kc) else { return nil }
            return "\(kind.label) \(Pretty.action(a))"
        }
        return parts.isEmpty ? "未配置任何动作" : parts.joined(separator: "  ")
    }

    // MARK: 右侧：触发卡 + 单编辑器

    private var editorPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Text("「\(keyLabel(selected))」键")
                        .font(.title3.weight(.semibold))
                    if model.savedFlash {
                        Label("已保存", systemImage: "checkmark.circle.fill")
                            .font(.caption).foregroundStyle(.green)
                            .transition(.opacity)
                    }
                    Spacer()
                    Button { showSettings = true } label: {
                        Label("手感设置", systemImage: "slider.horizontal.3")
                    }
                    Menu {
                        Section(service.statusLine) {}
                        Button(service.paused ? "恢复接管" : "暂停接管") {
                            ServiceHub.shared.onTogglePause?()
                        }
                        Button("重载配置") {
                            ServiceHub.shared.onReloadConfig?()
                        }
                        Button("检查更新…") {
                            if ServiceHub.shared.onCheckForUpdates != nil {
                                ServiceHub.shared.onCheckForUpdates?()
                            } else {
                                showNotice("此构建未包含更新组件（开发构建）")
                            }
                        }
                        Button("编辑配置文件…") {
                            NSWorkspace.shared.open(Config.configURL)
                        }
                        Divider()
                        Button("清理映射并退出", role: .destructive) {
                            ServiceHub.shared.onQuit?()
                        }
                    } label: {
                        Label("服务", systemImage: "ellipsis.circle")
                    }
                    .fixedSize()
                    Button { resetKey() } label: {
                        Label("恢复此键默认", systemImage: "arrow.counterclockwise")
                    }
                }

                if let notice {
                    Text(notice)
                        .font(.callout).foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 10) {
                    ForEach(TriggerKind.allCases) { kind in
                        // 菜单键的双击 = 系统保留手势（呼出设置），锁定不可配置
                        let reserved = (kind == .double && selected == ServiceGesture.key)
                        TriggerCard(kind: kind,
                                    action: reserved ? nil : kind.action(in: currentKC),
                                    isSelected: selectedTrigger == kind && !reserved,
                                    systemText: reserved ? "呼出设置（系统）" : nil) {
                            if reserved {
                                showNotice("双击「TV」为系统保留手势（呼出设置），不可修改")
                            } else {
                                selectedTrigger = kind
                            }
                        }
                    }
                }

                Divider()

                // 编辑上下文 = (键, 触发位)：一换整体重置，
                // 预览/录制/折叠面板等本地状态不会跨上下文泄漏
                TriggerEditor(kind: selectedTrigger, action: selectedTriggerAction)
                    .id("\(selected.rawValue)/\(selectedTrigger.rawValue)")
            }
            .padding(24)
        }
        .animation(.easeInOut(duration: 0.15), value: notice)
    }

    private var currentKC: KeyConfig {
        model.cfg.keys[selected.rawValue] ?? KeyConfig(tap: nil, hold: nil, double: nil, repeatAction: nil)
    }

    /// 选中键 + 选中触发的读写入口；写入经 writeAction 处理互斥。
    private var selectedTriggerAction: Binding<Action?> {
        let kp = selectedTrigger.keyPath
        return Binding(get: { currentKC[keyPath: kp] }, set: { writeAction($0) })
    }

    /// 写入当前 (键, 触发位) 的动作；系统保留位拒写；配置长按/连发时自动清掉另一方并提示。
    private func writeAction(_ newValue: Action?) {
        if selected == ServiceGesture.key && selectedTrigger == .double {
            showNotice("双击「TV」为系统保留手势（呼出设置），不可修改")
            return
        }
        var kc = currentKC
        kc[keyPath: selectedTrigger.keyPath] = newValue
        if newValue != nil {
            if selectedTrigger == .hold, kc.repeatAction != nil {
                kc.repeatAction = nil
                showNotice("已清除连发（长按与连发互斥）")
            } else if selectedTrigger == .repeatAction, kc.hold != nil {
                kc.hold = nil
                showNotice("已清除长按（连发与长按互斥）")
            }
        }
        model.cfg.keys[selected.rawValue] = kc
    }

    private func keyLabel(_ k: RemoteKey) -> String {
        hotspots.first { $0.key == k }?.label ?? k.rawValue
    }

    private func resetKey() {
        model.cfg.keys[selected.rawValue] = Config.defaultConfig().keys[selected.rawValue]
        showNotice("「\(keyLabel(selected))」已恢复出厂键位")
    }

    private func showNotice(_ text: String) {
        notice = text
        let token = UUID()
        noticeToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if noticeToken == token { notice = nil }
        }
    }
}

// MARK: - 触发卡（右上排，摘要 + 点选）

struct TriggerCard: View {
    let kind: TriggerKind
    let action: Action?
    let isSelected: Bool
    var systemText: String? = nil
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Circle()
                        .fill((systemText != nil || action != nil) ? Color.accentColor
                                                                   : Color(nsColor: .quaternaryLabelColor))
                        .frame(width: 6, height: 6)
                    Text(kind.label).font(.subheadline.weight(.semibold))
                    if systemText != nil {
                        Image(systemName: "lock.fill")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Text.display(systemText ?? Pretty.action(action))
                    .font(.callout)
                    .foregroundStyle((systemText != nil || action != nil) ? .primary : .tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(isSelected ? Color.accentColor.opacity(0.08)
                                   : Color(nsColor: .controlBackgroundColor))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? Color.accentColor : Color(nsColor: .separatorColor).opacity(0.5),
                        lineWidth: isSelected ? 1.5 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 手感设置 Sheet（从主界面移出的全局参数）

struct SettingsSheet: View {
    @Binding var cfg: Config
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("全局手感参数").font(.headline)
                    Spacer()
                    Button("完成") { dismiss() }
                }
                timingStepper("长按判定", "超过该时长算长按", $cfg.settings.holdMs, 150...800)
                timingStepper("双击窗口", "两次单击在该窗口内算双击；配置双击后，单击会延迟到窗口结束才触发", $cfg.settings.doubleMs, 150...500)
                timingStepper("连发间隔", "连发时相邻两次动作的间隔", $cfg.settings.repeatMs, 30...300)
                timingStepper("连发起始延迟", "按住超过该时长后开始连发", $cfg.settings.repeatDelayMs, 150...800)

                Divider()
                Text.display("组合键写法：ctrl+cmd+q、arrowup、return、f5。\n⚠️ 想用 fn 键：先把 系统设置>键盘>「按下 🌐 键时」改为「什么都不做」，否则会弹表情选择。")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Divider()
                HStack {
                    Spacer()
                    Button("恢复全部默认…", role: .destructive) { confirmResetAll() }
                }
            }
            .padding(20)
        }
        .frame(width: 460)
    }

    private func timingStepper(_ label: String, _ caption: String, _ value: Binding<Int>, _ range: ClosedRange<Int>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                Spacer()
                Stepper(value: value, in: range, step: 10) {
                    Text("\(value.wrappedValue) ms").monospacedDigit()
                }
            }
            Text(caption).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func confirmResetAll() {
        let alert = NSAlert()
        alert.messageText = "恢复全部默认键位？"
        alert.informativeText = "所有按键的自定义配置与手感参数将被清除，此操作不可撤销。"
        alert.addButton(withTitle: "恢复默认")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            cfg = Config.defaultConfig()
        }
    }
}
