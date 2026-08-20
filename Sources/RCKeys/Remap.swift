import Foundation

/// 设备级哑化：hidutil 把遥控器按键映射到键盘页 usage 0（No Event），
/// 系统从此对这台设备零反应（含 Secure Input 期间——没有系统事件就无所谓泄漏）。
/// 作用域用 --matching 限定 VID/PID，真键盘不受影响。
/// 注意：蓝牙重连后 HID 服务的 registry 实例是新的，必须重新应用（由设备回调驱动）。
enum Remap {
    static let hidutil = "/usr/bin/hidutil"
    static let matching = "{\"VendorID\":\(RC003.vendorID),\"ProductID\":\(RC003.productID)}"

    // back(0xF1) 超出标准键盘 usage，hidutil 不认、系统本身也不处理，无需映射。
    static let neuters: [UInt32] = [
        0x52, 0x51, 0x50, 0x4F, // 方向
        0x28,                    // OK
        0x4A, 0x65, 0x35, 0x66,  // home menu tv power
        0x80, 0x81,              // 音量
        0x3E,                    // 语音键（不处理语音则 F5 会漏进前台，一并哑化）
    ]

    static var payload: String {
        let entries = neuters
            .map { String(format: "{\"HIDKeyboardModifierMappingSrc\":0x7000000%02X,\"HIDKeyboardModifierMappingDst\":0x700000000}", $0) }
            .joined(separator: ",")
        return "{\"UserKeyMapping\":[\(entries)]}"
    }

    @discardableResult
    private static func run(_ args: [String]) -> Int32 {
        guard let p = Process().with(hidutil, args) else { return -1 }
        try? p.run(); p.waitUntilExit()
        return p.terminationStatus
    }

    /// 应用哑化。返回是否成功。
    static func apply() -> Bool {
        run(["property", "--matching", matching, "--set", payload]) == 0
    }

    /// 清除本设备的映射（退出/暂停时调用；`rckeys --fix` 亦可手动清残留）。
    static func clear() -> Bool {
        run(["property", "--matching", matching, "--set", "{\"UserKeyMapping\":[]}"]) == 0
    }
}

private extension Process {
    func with(_ path: String, _ args: [String]) -> Process? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        executableURL = URL(fileURLWithPath: path)
        arguments = args
        standardOutput = Pipe()
        standardError = Pipe()
        return self
    }
}
