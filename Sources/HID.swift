import Foundation
import IOKit
import IOKit.hid

// RC003 真机 usage 表（多方实测一致；report = reportID 1 字节 + N×小端 u16 usage 槽）
enum RC003 {
    static let vendorID = 0x2717
    static let productID = 0x32B8

    static let usageByKey: [UInt32: RemoteKey] = [
        0x52: .up, 0x51: .down, 0x50: .left, 0x4F: .right,
        0x28: .ok, 0xF1: .back, 0x4A: .home, 0x65: .menu,
        0x35: .tv, 0x66: .power, 0x80: .volUp, 0x81: .volDown,
        0x3E: .voice,
    ]
}

/// 纯监听通道：IOHIDManager 非独占打开 + 原始报告回调 → 按键边沿。
/// 原始报告不经 UserKeyMapping 翻译，系统哑化不影响本通道（真机验证）。
final class KeyListener {
    private let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private var pressed: Set<RemoteKey> = []
    private var started = false

    var onEvent: ((RemoteKey, Bool) -> Void)?
    var onDevice: ((Bool) -> Void)?
    var log: ((String) -> Void)?

    /// 打开监听；返回是否成功（失败通常是「输入监控」权限未授予）。
    @discardableResult
    func start() -> Bool {
        guard !started else { return true }
        started = true
        let match: [String: Any] = [
            kIOHIDVendorIDKey as String: RC003.vendorID,
            kIOHIDProductIDKey as String: RC003.productID,
        ]
        IOHIDManagerSetDeviceMatching(mgr, match as CFDictionary)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputReportCallback(mgr, Self.reportCB, ctx)
        IOHIDManagerRegisterDeviceMatchingCallback(mgr, Self.matchedCB, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(mgr, Self.removedCB, ctx)
        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        let r = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        log?(String(format: "HID 监听 open -> 0x%08X %@", r, r == kIOReturnSuccess ? "（正常）" : "（需在 系统设置>隐私与安全性>输入监控 授权运行本程序的 App）"))
        return r == kIOReturnSuccess
    }

    func stop() {
        guard started else { return }
        started = false
        IOHIDManagerUnscheduleFromRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        pressed = []
    }

    private func handleReport(_ report: UnsafeMutablePointer<UInt8>, _ len: Int) {
        guard len > 1 else { return }
        var now: Set<RemoteKey> = []
        var i = 1 // 首字节是 reportID
        while i + 1 < len {
            let usage = UInt32(report[i]) | (UInt32(report[i + 1]) << 8)
            if let key = RC003.usageByKey[usage] { now.insert(key) }
            i += 2
        }
        for k in now.subtracting(pressed) { onEvent?(k, true) }
        for k in pressed.subtracting(now) { onEvent?(k, false) }
        pressed = now
    }

    private func deviceChanged(_ connected: Bool) {
        pressed = []
        onDevice?(connected)
    }

    // C 回调蹦床
    private static let reportCB: IOHIDReportCallback = { ctx, _, _, _, _, report, len in
        Unmanaged<KeyListener>.fromOpaque(ctx!).takeUnretainedValue()
            .handleReport(report, len)
    }
    private static let matchedCB: IOHIDDeviceCallback = { ctx, _, _, _ in
        Unmanaged<KeyListener>.fromOpaque(ctx!).takeUnretainedValue().deviceChanged(true)
    }
    private static let removedCB: IOHIDDeviceCallback = { ctx, _, _, _ in
        Unmanaged<KeyListener>.fromOpaque(ctx!).takeUnretainedValue().deviceChanged(false)
    }
}
