import Foundation
import IOKit
import IOKit.hid

// seize 一锤定音探针：全新进程里尝试独占打开 RC003。
// 先报权限状态，再试设备级 seize；被拒则降级监听并统计 8 秒内能否收到按键事件。
final class SeizeProbe {
    let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    var device: IOHIDDevice?
    var events = 0
    var verdictPrinted = false
    var listenOnly = false

    func run() {
        // 触发输入监控授权弹窗（若已授权则静默通过）
        let req = IOHIDRequestType(rawValue: 1) // kIOHIDRequestTypeListenEvent
        let cur = IOHIDCheckAccess(req)
        print("输入监控状态 rawValue=\(cur.rawValue)（0=granted）")
        if cur.rawValue != 0 {
            let r = IOHIDRequestAccess(req)
            print("已请求授权 granted=\(r) —— 屏幕弹出授权窗请点「允许」；没弹窗就去 系统设置>隐私与安全性>输入监控 手动开启")
            var granted = false
            for _ in 0..<20 {
                Thread.sleep(forTimeInterval: 2)
                if IOHIDCheckAccess(req).rawValue == 0 { granted = true; break }
            }
            print(granted ? ">> 授权已生效，继续探测" : ">> 等待授权超时，仍按原样探测（结果可能仍是 NotPermitted）")
        }

        let match: [String: Any] = [
            kIOHIDVendorIDKey as String: 0x2717,
            kIOHIDProductIDKey as String: 0x32B8,
        ]
        IOHIDManagerSetDeviceMatching(mgr, match as CFDictionary)
        IOHIDManagerRegisterDeviceMatchingCallback(mgr, Self.matched, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerRegisterInputValueCallback(mgr, Self.input, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        let r = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        print(String(format: "IOHIDManagerOpen(listen) -> 0x%08X", r))

        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            if !self.verdictPrinted { self.report(hr: 0, note: "4 秒内未匹配到设备（遥控器可能休眠——请按任意键）") }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 14) { self.exitNow() }
        RunLoop.main.run()
    }

    func deviceArrived(_ dev: IOHIDDevice) {
        guard !verdictPrinted else { return }
        device = dev
        // 顺路抓 HID Report Descriptor（固件补丁路线的核心资产）
        if let d = IOHIDDeviceGetProperty(dev, "ReportDescriptor" as CFString) as? Data {
            try? d.write(to: URL(fileURLWithPath: "/tmp/rc003-probe/report_descriptor.bin"))
            print("ReportDescriptor \(d.count) 字节 -> /tmp/rc003-probe/report_descriptor.bin")
            print("  " + d.map { String(format: "%02x", $0) }.joined(separator: " "))
        }
        let hr = IOHIDDeviceOpen(dev, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        if hr == kIOReturnSuccess {
            report(hr: hr, note: "SEIZE 成功 ✅ —— 接下来 8 秒请按遥控器方向键/OK 若干次（事件应只进本进程，前台无反应）")
        } else {
            var hint = ""
            if hr == kern_return_t(bitPattern: 0xE00002C1) { hint = " = kIOReturnNotPrivileged（macOS 拒绝独占，与 MiRemote 作者 26.5 实测一致）" }
            report(hr: hr, note: "SEIZE 被拒 ❌\(hint)；降级监听模式——接下来 8 秒请按遥控器方向键/OK 若干次")
            listenOnly = true
            let r2 = IOHIDDeviceOpen(dev, IOOptionBits(kIOHIDOptionsTypeNone))
            print(String(format: "IOHIDDeviceOpen(listen) -> 0x%08X", r2))
        }
    }

    func report(hr: kern_return_t, note: String) {
        verdictPrinted = true
        print(String(format: "\nIOHIDDeviceOpen(seize) -> 0x%08X", hr))
        print(note)
    }

    func onInput(_ value: IOHIDValue) {
        events += 1
        let e = IOHIDValueGetElement(value)
        print("  [事件 #\(events)] page=\(IOHIDElementGetUsagePage(e)) usage=\(IOHIDElementGetUsage(e)) v=\(IOHIDValueGetIntegerValue(value))")
    }

    func exitNow() {
        print("\n===== 结论 =====")
        print("收到 HID 事件数: \(events)")
        if verdictPrinted {
            print(listenOnly
                ? "seize 被拒（macOS 26 禁独占）；监听通道\(events > 0 ? "正常工作" : "8 秒内无事件（可能没按/回调已被陷阱废掉）")"
                : "seize 可用！独占链路上事件正常进入本进程")
        }
        exit(0)
    }

    // C 回调蹦床
    static let matched: IOHIDDeviceCallback = { ctx, _, _, dev in
        Unmanaged<SeizeProbe>.fromOpaque(ctx!).takeUnretainedValue().deviceArrived(dev)
    }
    static let input: IOHIDValueCallback = { ctx, _, _, value in
        Unmanaged<SeizeProbe>.fromOpaque(ctx!).takeUnretainedValue().onInput(value)
    }
}

let probe = SeizeProbe()
probe.run()
