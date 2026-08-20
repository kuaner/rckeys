import Foundation

/// 手势引擎：tap（未配 double 时零延迟）/ hold / repeat（长按连发）/ double（双击）。
/// 系统已哑化 → 设备不产生自动重复，连发完全由本引擎的定时器驱动。
/// 时钟可注入（Scheduler）：生产用主队列真实时钟；测试注入虚拟时钟确定性推进
/// （见 EngineTests.swift，--self-test 覆盖边缘用例）。
public final class GestureEngine: @unchecked Sendable {
    public struct Timings {
        var holdMs: Int
        var doubleMs: Int
        var repeatMs: Int
        var repeatDelayMs: Int
    }

    /// 可注入调度器：当前时间 + 可取消的延迟执行。
    /// fire 经 Task 盒传递（闭包属性类型的参数无法声明 @escaping，
    /// 故由 schedule() 方法装箱——方法声明的参数可以）。
    public struct Scheduler: Sendable {
        public struct Ticket: Sendable { let cancel: @Sendable () -> Void }
        public struct Task: Sendable { let call: @Sendable () -> Void }
        public let now: @Sendable () -> DispatchTime
        public let after: @Sendable (_ ms: Int, _ task: Task) -> Ticket

        public func schedule(_ ms: Int, _ fire: @escaping @Sendable () -> Void) -> Ticket {
            after(ms, Task(call: fire))
        }

        /// 生产时钟：主队列真实时间
        public static let main = Scheduler(now: mainNow, after: mainAfter)
    }

    private final class St {
        var down = false
        var downAt: DispatchTime?
        var holdFired = false
        var holdTask: Scheduler.Ticket?
        var repeatTask: Scheduler.Ticket?
        var tapTask: Scheduler.Ticket?
        var lastTapAt: DispatchTime?
    }

    public var timings: Timings
    public var configs: [RemoteKey: KeyConfig]
    /// kind: tap / hold / repeat / double
    public var fire: (Action, RemoteKey, String) -> Void
    /// 系统保留手势（长按菜单 = 呼出设置）：命中时走此回调，不执行用户配置的动作
    public var onSystemGesture: (@Sendable (RemoteKey, String) -> Void)?
    /// 裸修饰键按压（注入点：测试替换以免真实注入事件）
    public var pressModifier: @Sendable (String, Bool) -> Void = Actions.pressModifier

    /// hold 配置为裸修饰键（如 fn）时进入"按住"模式：holdReached 发 down，keyUp 发 up
    private var heldModifiers: [RemoteKey: String] = [:]

    private var st: [RemoteKey: St] = [:]
    let clock: Scheduler

    public init(config: Config, fire: @escaping @Sendable (Action, RemoteKey, String) -> Void,
                clock: Scheduler = .main) {
        self.timings = Timings(holdMs: config.settings.holdMs,
                               doubleMs: config.settings.doubleMs,
                               repeatMs: config.settings.repeatMs,
                               repeatDelayMs: config.settings.repeatDelayMs)
        self.configs = config.keys.mapKeys { RemoteKey(rawValue: $0) }
        self.fire = fire
        self.clock = clock
    }

    public func updateConfig(_ config: Config) {
        timings = Timings(holdMs: config.settings.holdMs,
                          doubleMs: config.settings.doubleMs,
                          repeatMs: config.settings.repeatMs,
                          repeatDelayMs: config.settings.repeatDelayMs)
        configs = config.keys.mapKeys { RemoteKey(rawValue: $0) }
    }

    private func state(_ k: RemoteKey) -> St {
        if let s = st[k] { return s }
        let s = St(); st[k] = s; return s
    }

    public func keyDown(_ k: RemoteKey) {
        let s = state(k)
        guard !s.down else { return }
        s.down = true
        s.downAt = clock.now()
        s.holdFired = false
        s.tapTask?.cancel(); s.tapTask = nil

        let cfg = configs[k]
        // 系统保留键（长按菜单=呼出设置）：无论用户是否配置，都按 holdMs 起计时
        let reserved = (k == ServiceGesture.key)
        let holdDelay = reserved ? timings.holdMs
            : (cfg?.hold != nil) ? timings.holdMs
            : ((cfg?.repeatAction != nil) ? timings.repeatDelayMs : -1)
        guard holdDelay > 0 else { return }
        s.holdTask = clock.schedule(holdDelay) { [weak self] in self?.holdReached(k) }
    }

    private func holdReached(_ k: RemoteKey) {
        let s = state(k)
        guard s.down, !s.holdFired else { return }
        s.holdFired = true
        // 系统保留手势：长按菜单 = 呼出设置，优先于任何用户配置
        if k == ServiceGesture.key {
            onSystemGesture?(k, "hold")
            return
        }
        if let a = configs[k]?.hold {
            // 裸修饰键：按下持续到松手（供"长按 fn 说话"类场景），不走一次性 fire
            if a.type == "key", Actions.isBareModifier(a.combo), let combo = a.combo {
                heldModifiers[k] = combo
                pressModifier(combo, true)
                return
            }
            fire(a, k, "hold")
        } else if let a = configs[k]?.repeatAction {
            fire(a, k, "repeat")
            scheduleRepeat(k, a)
        }
    }

    private func scheduleRepeat(_ k: RemoteKey, _ a: Action) {
        let s = state(k)
        guard s.down, s.holdFired else { return }
        s.repeatTask = clock.schedule(timings.repeatMs) { [weak self] in
            guard let self else { return }
            let s = self.state(k)
            guard s.down, s.holdFired else { return }
            self.fire(a, k, "repeat")
            self.scheduleRepeat(k, a)
        }
    }

    public func keyUp(_ k: RemoteKey) {
        let s = state(k)
        guard s.down else { return }
        s.down = false
        // 先释放"按住模式"的修饰键（无论后续走哪个分支都必须放掉）
        if let combo = heldModifiers.removeValue(forKey: k) {
            pressModifier(combo, false)
        }
        s.holdTask?.cancel(); s.holdTask = nil
        s.repeatTask?.cancel(); s.repeatTask = nil
        guard !s.holdFired else { return }

        // 按压时长 ≥ 长按判定：这就是一次"长按"（无论是否配置长按动作、
        // 甚至长按位为空），不回退触发单击、不计入双击，并打断双击序列
        if let downAt = s.downAt, msBetween(downAt, clock.now()) >= timings.holdMs {
            s.downAt = nil
            s.lastTapAt = nil
            return
        }
        s.downAt = nil

        // 双击判定：只影响配置了 double 的键（其余键 tap 零延迟直发）
        if configs[k]?.double != nil {
            let t = clock.now()
            if let last = s.lastTapAt,
               msBetween(last, t) < timings.doubleMs {
                s.lastTapAt = nil
                fire(configs[k]!.double!, k, "double")
                return
            }
            s.lastTapAt = t
            s.tapTask = clock.schedule(timings.doubleMs) { [weak self] in
                guard let self else { return }
                let s = self.state(k)
                guard !s.down, s.lastTapAt != nil else { return }
                s.lastTapAt = nil
                if let a = self.configs[k]?.tap { self.fire(a, k, "tap") }
            }
        } else if let a = configs[k]?.tap {
            fire(a, k, "tap")
        }
    }

    /// 设备断开/接管暂停时清空全部按键状态与定时器，并释放按住中的修饰键
    public func reset() {
        for (k, combo) in heldModifiers {
            pressModifier(combo, false)
            heldModifiers[k] = nil
        }
        for (_, s) in st {
            s.holdTask?.cancel(); s.repeatTask?.cancel(); s.tapTask?.cancel()
            s.down = false; s.holdFired = false; s.lastTapAt = nil; s.downAt = nil
        }
    }

    private func msBetween(_ a: DispatchTime, _ b: DispatchTime) -> Int {
        Int((b.uptimeNanoseconds - a.uptimeNanoseconds) / 1_000_000)
    }
}

private extension Dictionary where Key == String, Value == KeyConfig {
    func mapKeys(_ transform: (String) -> RemoteKey?) -> [RemoteKey: KeyConfig] {
        var out: [RemoteKey: KeyConfig] = [:]
        for (k, v) in self { if let rk = transform(k) { out[rk] = v } }
        return out
    }
}


private func mainNow() -> DispatchTime { DispatchTime.now() }

/// DispatchWorkItem 非 Sendable：主队列限定盒子
private final class WorkItemBox: @unchecked Sendable {
    let item: DispatchWorkItem
    init(_ item: DispatchWorkItem) { self.item = item }
}

private func mainAfter(_ ms: Int, _ task: GestureEngine.Scheduler.Task) -> GestureEngine.Scheduler.Ticket {
    let item = DispatchWorkItem(block: task.call)
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(ms), execute: item)
    let box = WorkItemBox(item)
    return GestureEngine.Scheduler.Ticket { box.item.cancel() }
}
