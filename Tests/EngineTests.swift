import Testing
import Foundation
@testable import RCKeys

// 手势引擎边缘用例：虚拟时钟确定性推进，无真实等待。
// Rig 模拟一次按压 = keyDown → advance(pressMs) → keyUp。

/// 虚拟时钟：按到期时间（同刻按注册序）执行任务
final class VirtualClock {
    private var nowMs = 0
    private var nextId = 0
    private var jobs: [(id: Int, due: Int, fire: () -> Void)] = []

    var scheduler: GestureEngine.Scheduler {
        GestureEngine.Scheduler(
            now: { DispatchTime(uptimeNanoseconds: UInt64(self.nowMs) * 1_000_000) },
            after: { ms, fire in
                let id = self.nextId
                self.nextId += 1
                self.jobs.append((id, self.nowMs + ms, fire))
                return GestureEngine.Scheduler.Ticket { self.jobs.removeAll { $0.id == id } }
            })
    }

    func advance(_ ms: Int) {
        let target = nowMs + ms
        while let job = jobs.filter({ $0.due <= target }).min(by: { ($0.due, $0.id) < ($1.due, $1.id) }) {
            nowMs = job.due
            jobs.removeAll { $0.id == job.id }
            job.fire()
        }
        nowMs = target
    }
}

/// 测试台：收集触发记录（key.kind(actionType)）、系统手势、修饰键按压
final class Rig {
    let clock = VirtualClock()
    var fired: [String] = []
    var system: [String] = []
    var mods: [String] = []
    var engine: GestureEngine!
    let holdMs: Int

    init(keys: [String: KeyConfig], holdMs: Int = 350, doubleMs: Int = 250,
         repeatMs: Int = 100, repeatDelayMs: Int = 350) {
        self.holdMs = holdMs
        var cfg = Config()
        cfg.settings = Settings(holdMs: holdMs, doubleMs: doubleMs,
                                repeatMs: repeatMs, repeatDelayMs: repeatDelayMs)
        cfg.keys = keys
        engine = GestureEngine(
            config: cfg,
            fire: { [weak self] a, k, kind in self?.fired.append("\(k.rawValue).\(kind)(\(a.type))") },
            clock: clock.scheduler)
        engine.onSystemGesture = { [weak self] k, kind in self?.system.append("\(k.rawValue).\(kind)") }
        engine.pressModifier = { [weak self] n, d in self?.mods.append(n + (d ? "↓" : "↑")) }
    }

    /// 模拟一次按压（按下 → pressMs 毫秒 → 松开）
    func press(_ k: RemoteKey, forMs pressMs: Int) {
        engine.keyDown(k)
        clock.advance(pressMs)
        engine.keyUp(k)
    }
}

// MARK: - 单击 / 长按边界

@Test func tapFiresImmediatelyWhenNoDouble() {
    let r = Rig(keys: ["ok": KeyConfig(tap: .key("return"), hold: nil, double: nil, repeatAction: nil)])
    r.press(.ok, forMs: 100)
    #expect(r.fired == ["ok.tap(key)"])
}

@Test func tapSuppressedWhenReleaseAtOrAfterHoldThresholdNoHoldConfig() {
    // 长按位空着：按压达到阈值再松手也不回退触发单击
    let r = Rig(keys: ["ok": KeyConfig(tap: .key("return"), hold: nil, double: nil, repeatAction: nil)])
    r.press(.ok, forMs: r.holdMs)
    r.clock.advance(1000)
    #expect(r.fired.isEmpty)
}

@Test func tapBoundaryJustBelowThreshold() {
    let r = Rig(keys: ["ok": KeyConfig(tap: .key("return"), hold: nil, double: nil, repeatAction: nil)])
    r.press(.ok, forMs: r.holdMs - 1)
    #expect(r.fired == ["ok.tap(key)"])
}

@Test func holdFiresOnceAtThresholdAndSuppressesTap() {
    let r = Rig(keys: ["ok": KeyConfig(tap: .key("return"), hold: .key("esc"), double: nil, repeatAction: nil)])
    r.engine.keyDown(.ok)
    r.clock.advance(r.holdMs)
    #expect(r.fired == ["ok.hold(key)"])
    r.engine.keyUp(.ok)
    r.clock.advance(1000)
    #expect(r.fired == ["ok.hold(key)"])  // 只触发一次、无单击
}

@Test func holdNoneStillClassifiedAsLongPress() {
    // 长按 = 无动作：hold 回调携带 none（运行时不执行），松手不触发单击
    let r = Rig(keys: ["ok": KeyConfig(tap: .key("return"), hold: Action.none, double: nil, repeatAction: nil)])
    r.press(.ok, forMs: r.holdMs + 100)
    #expect(r.fired == ["ok.hold(none)"])
}

// MARK: - 连发

@Test func repeatFiresAtDelayThenIntervalAndStopsOnRelease() {
    let r = Rig(keys: ["volup": KeyConfig(tap: .media("volume_up"), hold: nil, double: nil,
                                          repeatAction: .media("volume_up"))])
    r.engine.keyDown(.volUp)
    r.clock.advance(350)   // repeatDelayMs → 第 1 次
    r.clock.advance(300)   // 3 个 repeatMs
    r.engine.keyUp(.volUp)
    r.clock.advance(1000)  // 松手后不再连发
    #expect(r.fired.filter { $0.hasPrefix("volup.repeat") }.count == 4)
    #expect(!r.fired.contains { $0.hasPrefix("volup.tap") })
}

// MARK: - 双击

@Test func doubleWithinWindowFiresDoubleAndNoTapsLeak() {
    let r = Rig(keys: ["ok": KeyConfig(tap: .key("return"), hold: nil,
                                       double: .key("space"), repeatAction: nil)])
    r.press(.ok, forMs: 50)
    r.press(.ok, forMs: 50)
    r.clock.advance(1000)
    #expect(r.fired == ["ok.double(key)"])   // 两次单击的延迟 tap 均被吞
}

@Test func doubleSlowSecondPressYieldsTwoTaps() {
    let r = Rig(keys: ["ok": KeyConfig(tap: .key("return"), hold: nil,
                                       double: .key("space"), repeatAction: nil)])
    r.press(.ok, forMs: 50)
    r.clock.advance(300)   // 第一次 tap 在窗口结束后触发
    r.press(.ok, forMs: 50)
    r.clock.advance(300)
    #expect(r.fired == ["ok.tap(key)", "ok.tap(key)"])
}

@Test func longPressBreaksDoubleSequence() {
    // holdMs < doubleMs 的危险区间：长按后紧跟快速单击，不得拼成双击
    let r = Rig(keys: ["ok": KeyConfig(tap: .key("return"), hold: nil,
                                       double: .key("space"), repeatAction: nil)],
                holdMs: 150, doubleMs: 800)
    r.press(.ok, forMs: 50)          // 第一次快速单击，tapTask 待决
    r.press(.ok, forMs: 200)         // 长按（≥150）：打断序列、清 lastTapAt
    r.press(.ok, forMs: 50)          // 再一次快速单击
    r.clock.advance(1000)
    // 无 double（长按清掉了 lastTapAt，这是本用例防的回归）。
    // 第一次单击的 tap 被双击检测取消后由长按吞掉（定义如此，不回溯补发）；
    // 第三次单击正常触发。
    #expect(r.fired == ["ok.tap(key)"])
}

@Test func doubleSecondPressHeldBecomesHold() {
    // 双击序列的第二下按住不放 → 变长按：无 tap 无 double
    let r = Rig(keys: ["ok": KeyConfig(tap: .key("return"), hold: .key("esc"),
                                       double: .key("space"), repeatAction: nil)])
    r.press(.ok, forMs: 50)
    r.engine.keyDown(.ok)
    r.clock.advance(400)
    r.engine.keyUp(.ok)
    r.clock.advance(1000)
    #expect(r.fired == ["ok.hold(key)"])
}

// MARK: - 系统保留手势（长按菜单 = 呼出设置）

@Test func menuHoldTriggersSystemGestureOverUserConfig() {
    // 即使用户给菜单配了长按动作，也以系统手势优先
    let r = Rig(keys: ["menu": KeyConfig(tap: Action(type: "mouse", name: "right"),
                                         hold: .key("esc"), double: nil, repeatAction: nil)])
    r.engine.keyDown(.menu)
    r.clock.advance(r.holdMs)
    #expect(r.system == ["menu.hold"])
    #expect(r.fired.isEmpty)
    r.engine.keyUp(.menu)
    r.clock.advance(1000)
    #expect(r.fired.isEmpty)   // 松手也不触发单击
}

@Test func menuQuickTapStillFiresUserAction() {
    let r = Rig(keys: ["menu": KeyConfig(tap: Action(type: "mouse", name: "right"),
                                         hold: nil, double: nil, repeatAction: nil)])
    r.press(.menu, forMs: 100)
    #expect(r.fired == ["menu.tap(mouse)"])
    #expect(r.system.isEmpty)
}

// MARK: - 裸修饰键（按住语义）

@Test func bareModifierHoldPressesDownAndReleasesOnKeyUp() {
    let r = Rig(keys: ["voice": KeyConfig(tap: nil, hold: .key("fn"), double: nil, repeatAction: nil)])
    r.engine.keyDown(.voice)
    r.clock.advance(r.holdMs)
    #expect(r.mods == ["fn↓"])
    #expect(r.fired.isEmpty)
    r.engine.keyUp(.voice)
    #expect(r.mods == ["fn↓", "fn↑"])
}

@Test func resetReleasesHeldModifierAndCancelsTimers() {
    let r = Rig(keys: ["voice": KeyConfig(tap: nil, hold: .key("fn"), double: nil, repeatAction: nil),
                       "ok": KeyConfig(tap: .key("return"), hold: .key("esc"), double: nil, repeatAction: nil)])
    r.engine.keyDown(.voice)
    r.clock.advance(r.holdMs)          // fn 按下
    r.engine.keyDown(.ok)
    r.engine.reset()
    #expect(r.mods == ["fn↓", "fn↑"])
    r.clock.advance(5000)
    #expect(r.fired.isEmpty)           // 挂起的 hold 定时器全部取消
    r.press(.ok, forMs: 50)            // reset 后可正常工作
    #expect(r.fired == ["ok.tap(key)"])
}

// MARK: - 输入健壮性

@Test func duplicateKeyDownIgnored() {
    let r = Rig(keys: ["ok": KeyConfig(tap: .key("return"), hold: .key("esc"), double: nil, repeatAction: nil)])
    r.engine.keyDown(.ok)
    r.engine.keyDown(.ok)              // 固件重复 down 报告
    r.clock.advance(r.holdMs)
    r.engine.keyUp(.ok)
    r.clock.advance(1000)
    #expect(r.fired == ["ok.hold(key)"])   // 恰好一次
}

@Test func strayKeyUpIgnored() {
    let r = Rig(keys: ["ok": KeyConfig(tap: .key("return"), hold: nil, double: nil, repeatAction: nil)])
    r.engine.keyUp(.ok)                // 未按下就松开
    #expect(r.fired.isEmpty)
    r.press(.ok, forMs: 50)            // 之后仍正常
    #expect(r.fired == ["ok.tap(key)"])
}

// MARK: - 配置热更新

@Test func updateConfigTakesEffectImmediately() {
    let r = Rig(keys: ["ok": KeyConfig(tap: .key("return"), hold: nil, double: nil, repeatAction: nil)])
    var cfg = Config()
    cfg.settings = Settings(holdMs: r.holdMs, doubleMs: 250, repeatMs: 100, repeatDelayMs: 350)
    cfg.keys = ["ok": KeyConfig(tap: .media("mute"), hold: nil, double: nil, repeatAction: nil)]
    r.engine.updateConfig(cfg)
    r.press(.ok, forMs: 50)
    #expect(r.fired == ["ok.tap(media)"])
}
