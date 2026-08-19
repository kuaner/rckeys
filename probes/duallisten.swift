import Foundation
import IOKit
import IOKit.hid

// 双通道监听：同时验证 原始报告回调（raw report）与 值回调（input value）
// 在哑化映射生效时哪一层仍能收到按键。18 秒自动退出。
final class Dual {
    let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    var reports = 0
    var values = 0

    static let keyName: [UInt: String] = [
        0x52: "↑", 0x51: "↓", 0x50: "←", 0x4F: "→", 0x28: "OK", 0x4A: "home",
        0x65: "menu", 0x35: "TV", 0x66: "power", 0x3E: "voice",
        0x80: "vol+", 0x81: "vol-", 0xF1: "back",
    ]

    func run() {
        let match: [String: Any] = [
            kIOHIDVendorIDKey as String: 0x2717,
            kIOHIDProductIDKey as String: 0x32B8,
        ]
        IOHIDManagerSetDeviceMatching(mgr, match as CFDictionary)
        IOHIDManagerRegisterInputReportCallback(mgr, Self.report, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerRegisterInputValueCallback(mgr, Self.value, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        let r = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        print(String(format: "open -> 0x%08X —— 请按遥控器方向键/OK/音量（18 秒窗口）", r))
        DispatchQueue.main.asyncAfter(deadline: .now() + 18) {
            print("\n== 窗口结束 ==")
            print("原始报告回调: \(self.reports) 个报告")
            print("值回调(usage元素): \(self.values) 个事件")
            if self.reports > 0 && self.values == 0 {
                print(">> 结论：哑化只掐系统事件层，原始报告层完好 —— 轨道A 用 report 回调即可（家族项目的做法）")
            } else if self.reports > 0 && self.values > 0 {
                print(">> 结论：两层都活着 —— 值回调也可用")
            } else if self.reports == 0 {
                print(">> 没收到任何报告：遥控器可能在休眠，或未按键")
            }
            exit(0)
        }
        RunLoop.main.run()
    }

    func onReport(_ report: UnsafeMutablePointer<UInt8>, len: Int) {
        reports += 1
        var parts: [String] = []
        // report 格式：首字节 reportID，其后小端 u16 usage 数组
        var i = 1
        while i + 1 < len {
            let u = UInt(report[i]) | (UInt(report[i+1]) << 8)
            if u != 0 { parts.append(String(format: "%04x%@", u, Self.keyName[u] ?? "")) }
            i += 2
        }
        guard !parts.isEmpty else { return }
        print("  [报告#\(reports)] \(len)B: \(parts.joined(separator: " "))")
    }

    func onValue(_ v: IOHIDValue) {
        let e = IOHIDValueGetElement(v)
        let usage = IOHIDElementGetUsage(e)
        guard IOHIDElementGetUsagePage(e) == 7, usage != 0xFFFFFFFF else { return }
        values += 1
        print("  [值#\(values)] usage=0x\(String(usage, radix: 16)) \(Self.keyName[UInt(usage)] ?? "?")")
    }

    static let report: IOHIDReportCallback = { ctx, _, _, _, _, report, len in
        Unmanaged<Dual>.fromOpaque(ctx!).takeUnretainedValue().onReport(report, len: len)
    }
    static let value: IOHIDValueCallback = { ctx, _, _, v in
        Unmanaged<Dual>.fromOpaque(ctx!).takeUnretainedValue().onValue(v)
    }
}

Dual().run()
