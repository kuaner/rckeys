// RCKeys 应用图标生成器：渐变圆角矩形 + SF Symbol remote.fill 白色前景。
// 用法：swift scripts/make_icon.swift   （在仓库根目录执行，产出 assets/AppIcon.icns）

import AppKit

/// 在显式位图上下文中绘制（不依赖 NSImage.lockFocus，小尺寸更可靠）
func withBitmapRep(px: Int, draw: () -> Void) -> NSBitmapImageRep? {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    rep.size = NSSize(width: px, height: px)
    NSGraphicsContext.saveGraphicsState()
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
        NSGraphicsContext.restoreGraphicsState()
        return nil
    }
    NSGraphicsContext.current = ctx
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func iconPNG(px: Int) -> Data? {
    let side = CGFloat(px)
    let rep = withBitmapRep(px: px) {
        let rect = NSRect(origin: .zero, size: NSSize(width: side, height: side))
        let radius = side * 0.2237

        // 背景：深蓝 → 亮蓝渐变的圆角矩形（macOS 图标比例）
        NSGradient(starting: NSColor(srgbRed: 0.13, green: 0.19, blue: 0.33, alpha: 1),
                   ending: NSColor(srgbRed: 0.28, green: 0.47, blue: 0.86, alpha: 1))?
            .draw(in: NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius), angle: -90)

        // 前景：手绘遥控器（机身 + 电源键 + OK 圆环 + 音量条），等比居中约 58%
        let fgSide = side * 0.58
        let fgRect = NSRect(x: (side - fgSide) / 2, y: (side - fgSide) / 2,
                            width: fgSide, height: fgSide)
        NSGraphicsContext.current?.cgContext.saveGState()
        NSGraphicsContext.current?.cgContext.translateBy(x: fgRect.minX, y: fgRect.minY)
        let w = fgSide, h = fgSide
        let accent = NSColor(srgbRed: 0.24, green: 0.42, blue: 0.80, alpha: 1)

        // 机身：竖向胶囊
        let bodyW = w * 0.44
        NSColor.white.setFill()
        NSBezierPath(roundedRect: NSRect(x: (w - bodyW) / 2, y: 0, width: bodyW, height: h),
                     xRadius: bodyW * 0.5, yRadius: bodyW * 0.5).fill()

        // 细节用背景同色系蓝，形成"镂空"质感
        // 电源键（顶部圆点）
        accent.setFill()
        NSBezierPath(ovalIn: NSRect(x: w / 2 - bodyW * 0.10, y: h * 0.86,
                                    width: bodyW * 0.20, height: bodyW * 0.20)).fill()
        // OK 键（圆环）
        accent.setStroke()
        let ringR = bodyW * 0.26
        let ring = NSBezierPath(ovalIn: NSRect(x: w / 2 - ringR, y: h * 0.48 - ringR,
                                               width: ringR * 2, height: ringR * 2))
        ring.lineWidth = bodyW * 0.10
        ring.stroke()
        // 音量条（两根短横条）
        accent.setFill()
        NSRect(x: w / 2 - bodyW * 0.17, y: h * 0.22, width: bodyW * 0.34, height: bodyW * 0.10).fill()
        NSRect(x: w / 2 - bodyW * 0.17, y: h * 0.08, width: bodyW * 0.34, height: bodyW * 0.10).fill()

        NSGraphicsContext.current?.cgContext.restoreGState()
    }
    return rep?.representation(using: .png, properties: [:])
}

let fm = FileManager.default
let root = URL(fileURLWithPath: "assets")
let iconset = root.appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)

let entries: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
    ("icon_1024x1024.png", 1024),
]
for (name, px) in entries {
    guard let data = iconPNG(px: px) else { fatalError("渲染 \(name) 失败") }
    try! data.write(to: iconset.appendingPathComponent(name))
}

// 预览图留档（肉眼检查用）
try? iconPNG(px: 512).map { try? $0.write(to: root.appendingPathComponent("icon-preview.png")) }

let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("AppIcon.icns").path]
try! proc.run()
proc.waitUntilExit()
try? fm.removeItem(at: iconset)
print("assets/AppIcon.icns 生成完毕（iconutil exit \(proc.terminationStatus)）")
