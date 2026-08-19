import Foundation
import CoreBluetooth

// RC003 无损侦察：枚举全部 GATT 服务/特征，读所有可读特征。
// 只读、不写、不订阅、不碰 DFU 控制点。结果存 /tmp/rc003-probe/。
final class GattDumper: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let atvv = CBUUID(string: "AB5E0001-5A21-4F05-BC7D-AF01F617B664")

    static let serviceNames: [String: String] = [
        "1800": "Generic Access", "1801": "Generic Attribute",
        "180A": "Device Information", "180F": "Battery", "1812": "HID",
        "FE59": "Nordic Secure DFU",
        "AB5E0001-5A21-4F05-BC7D-AF01F617B664": "ATVV voice (Google)",
    ]
    static let charNames: [String: String] = [
        "2A00": "Device Name", "2A01": "Appearance", "2A24": "Model Number",
        "2A25": "Serial Number", "2A26": "Firmware Revision",
        "2A27": "Hardware Revision", "2A28": "Software Revision",
        "2A29": "Manufacturer Name", "2A50": "PnP ID", "2A19": "Battery Level",
        "2A4A": "HID Information", "2A4B": "Report Map",
        "2A4C": "HID Control Point", "2A4D": "Report",
        "8EC90001-F315-4F60-9FB8-838830DAEA50": "DFU Packet",
        "8EC90002-F315-4F60-9FB8-838830DAEA50": "DFU Control Point",
        "8EC90003-F315-4F60-9FB8-838830DAEA50": "DFU Buttonless?",
        "8EC90004-F315-4F60-9FB8-838830DAEA50": "DFU Version?",
    ]

    var central: CBCentralManager!
    var peripheral: CBPeripheral?
    var pending = 0
    var finished = false
    var quietTicks = 0
    var started = Date()
    var lines: [String] = []
    var records: [[String: Any]] = []

    func hex(_ d: Data) -> String {
        d.map { String(format: "%02x", $0) }.joined(separator: " ")
    }
    func ascii(_ d: Data) -> String {
        String(data: d, encoding: .utf8).flatMap { s in
            s.allSatisfy { !$0.isNewline && ($0.isASCII && ($0.isLetter || $0.isNumber || " .-_/:()".contains($0))) } ? s : nil
        } ?? ""
    }
    func name(of uuid: CBUUID, table: [String: String]) -> String {
        table[uuid.uuidString] ?? ""
    }

    func run() {
        central = CBCentralManager(delegate: self, queue: nil)
        RunLoop.main.run()
    }

    // MARK: CBCentralManagerDelegate
    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        guard c.state == .poweredOn else {
            print("!! 蓝牙不可用: state=\(c.state.rawValue)（若为 3=unauthorized，请给终端 App 授予蓝牙权限）")
            exit(2)
        }
        let found = c.retrieveConnectedPeripherals(withServices: [Self.atvv, CBUUID(string: "1812")])
        if let p = found.first(where: { ($0.name ?? "").contains("遥控") || ($0.name ?? "").contains("MI RC") }) ?? found.first {
            connect(p)
        } else {
            print(".. 已连接列表未找到，扫描 15 秒（请按一下遥控器任意键唤醒）")
            c.scanForPeripherals(withServices: [Self.atvv], options: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
                if self.peripheral == nil { self.finish(note: "扫描超时未发现设备") }
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        scanStop(); connect(peripheral)
    }
    func scanStop() { if central.isScanning { central.stopScan() } }

    func connect(_ p: CBPeripheral) {
        guard peripheral == nil else { return }
        peripheral = p
        p.delegate = self
        print("== 连接: \(p.name ?? "?") \(p.identifier.uuidString)")
        central.connect(p, options: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) {
            if self.pending > 0 { self.finish(note: "全局超时，输出部分结果") }
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        pending += 1
        peripheral.discoverServices(nil)
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("!! 断开: \(error.map { "\($0)" } ?? "无错误")")
        finish(note: "连接中断")
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        finish(note: "连接失败 \(error.map { "\($0)" } ?? "")")
    }

    // MARK: CBPeripheralDelegate
    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        pending -= 1
        guard let services = p.services else { tick(); return }
        print("== 发现 \(services.count) 个服务")
        for s in services {
            pending += 1
            p.discoverCharacteristics(nil, for: s)
        }
        tick()
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        pending -= 1
        let sname = Self.serviceNames[service.uuid.uuidString] ?? ""
        let header = "SERVICE \(service.uuid.uuidString)\(sname.isEmpty ? "" : " (\(sname))")"
        lines.append(header)
        records.append(["type": "service", "uuid": service.uuid.uuidString, "name": sname])
        for c in service.characteristics ?? [] {
            let cname = Self.charNames[c.uuid.uuidString] ?? ""
            let props = [
                c.properties.contains(.read) ? "read" : nil,
                c.properties.contains(.write) ? "write" : nil,
                c.properties.contains(.writeWithoutResponse) ? "writeNR" : nil,
                c.properties.contains(.notify) ? "notify" : nil,
                c.properties.contains(.indicate) ? "indicate" : nil,
            ].compactMap { $0 }.joined(separator: ",")
            lines.append("  CHAR \(c.uuid.uuidString)\(cname.isEmpty ? "" : " [\(cname)]") {\(props)}")
            records.append(["type": "char", "service": service.uuid.uuidString,
                            "uuid": c.uuid.uuidString, "name": cname, "props": props])
            if c.properties.contains(.read) {
                pending += 1
                p.readValue(for: c)
            }
        }
        tick()
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor c: CBCharacteristic, error: Error?) {
        pending -= 1
        if let e = error {
            lines.append("      read error: \(e.localizedDescription)")
        } else if let d = c.value {
            var rec: [String: Any] = ["type": "value", "uuid": c.uuid.uuidString,
                                      "hex": d.map { String(format: "%02x", $0) }.joined(separator: "")]
            let a = ascii(d)
            if !a.isEmpty { rec["ascii"] = a }
            records.append(rec)
            let dlen = d.count
            let preview = dlen > 24 ? hex(d.prefix(24)) + " …(\(dlen)B)" : hex(d)
            lines.append("      = \(preview)\(a.isEmpty ? "" : "  \"\(a)\"")")
            if c.uuid.uuidString == "2A4B" {
                try? d.write(to: URL(fileURLWithPath: "/tmp/rc003-probe/report_map.bin"))
                lines.append("      (Report Map 已存 /tmp/rc003-probe/report_map.bin, \(dlen) 字节)")
            }
        }
        tick()
    }

    // 安静退出：所有挂起操作清零后再等 1.5s
    func tick() {
        quietTicks = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.watch() }
    }
    func watch() {
        guard !finished else { return }
        if pending > 0 { quietTicks = 0; return }
        quietTicks += 1
        if quietTicks >= 15 { finish(note: "完成") }
        else { DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.watch() } }
    }

    func finish(note: String) {
        guard !finished else { return }
        finished = true
        print("\n===== GATT DUMP (\(note)) =====")
        lines.forEach { print($0) }
        let json: [String: Any] = ["date": Date().description, "lines": lines, "records": records]
        let data = try! JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted])
        try? data.write(to: URL(fileURLWithPath: "/tmp/rc003-probe/gatt.json"))
        print("\n已存 /tmp/rc003-probe/gatt.json")
        exit(0)
    }
}

let dumper = GattDumper()
dumper.run()
