import AppKit
// Renders AppIcon.iconset: Notchling, a little notch with arms and legs, waving hello.
let sizes = [16, 32, 64, 128, 256, 512, 1024]
let iconset = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func oval(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> NSBezierPath {
    NSBezierPath(ovalIn: NSRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
}

/// Notch silhouette: nearly square top corners, generously rounded bottom.
func notchBody(_ r: NSRect, top: CGFloat, bottom: CGFloat) -> NSBezierPath {
    let p = NSBezierPath()
    p.move(to: NSPoint(x: r.minX + top, y: r.maxY))
    p.line(to: NSPoint(x: r.maxX - top, y: r.maxY))
    p.appendArc(withCenter: NSPoint(x: r.maxX - top, y: r.maxY - top), radius: top, startAngle: 90, endAngle: 0, clockwise: true)
    p.line(to: NSPoint(x: r.maxX, y: r.minY + bottom))
    p.appendArc(withCenter: NSPoint(x: r.maxX - bottom, y: r.minY + bottom), radius: bottom, startAngle: 0, endAngle: -90, clockwise: true)
    p.line(to: NSPoint(x: r.minX + bottom, y: r.minY))
    p.appendArc(withCenter: NSPoint(x: r.minX + bottom, y: r.minY + bottom), radius: bottom, startAngle: -90, endAngle: -180, clockwise: true)
    p.line(to: NSPoint(x: r.minX, y: r.maxY - top))
    p.appendArc(withCenter: NSPoint(x: r.minX + top, y: r.maxY - top), radius: top, startAngle: 180, endAngle: 90, clockwise: true)
    p.close()
    return p
}

func limb(_ points: [NSPoint], width: CGFloat) -> NSBezierPath {
    let p = NSBezierPath()
    p.move(to: points[0])
    p.curve(to: points[3], controlPoint1: points[1], controlPoint2: points[2])
    p.lineWidth = width
    p.lineCapStyle = .round
    return p
}

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    func P(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x * s, y: y * s) }
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let ink = rgb(0x1C1B29)

    // Tile
    let inset = s * 0.1
    let tile = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)
    NSGradient(starting: rgb(0xFFD6E5), ending: rgb(0xB9A2FF))!.draw(in: tilePath, angle: -90)
    NSGradient(colors: [rgb(0xFFFFFF, 0.45), rgb(0xFFFFFF, 0)], atLocations: [0, 1], colorSpace: .sRGB)!
        .draw(in: tilePath, relativeCenterPosition: NSPoint(x: 0, y: 0.2))

    // Ground shadow
    rgb(0x5B3FA8, 0.22).setFill()
    oval(0.5 * s, 0.225 * s, 0.17 * s, 0.03 * s).fill()

    // Legs and feet
    ink.setStroke(); ink.setFill()
    limb([P(0.44, 0.40), P(0.44, 0.33), P(0.43, 0.29), P(0.42, 0.255)], width: s * 0.034).stroke()
    limb([P(0.56, 0.40), P(0.56, 0.33), P(0.57, 0.29), P(0.58, 0.255)], width: s * 0.034).stroke()
    oval(0.405 * s, 0.24 * s, 0.045 * s, 0.024 * s).fill()
    oval(0.595 * s, 0.24 * s, 0.045 * s, 0.024 * s).fill()

    // Arms: left one waving, right one on a little hip-out curve
    limb([P(0.27, 0.54), P(0.22, 0.56), P(0.19, 0.61), P(0.185, 0.67)], width: s * 0.032).stroke()
    oval(0.185 * s, 0.685 * s, 0.03 * s, 0.03 * s).fill()
    limb([P(0.73, 0.50), P(0.78, 0.48), P(0.80, 0.44), P(0.795, 0.40)], width: s * 0.032).stroke()
    oval(0.795 * s, 0.39 * s, 0.03 * s, 0.03 * s).fill()

    // Body with soft shadow and a sheen across the top
    let body = notchBody(NSRect(x: 0.25 * s, y: 0.37 * s, width: 0.5 * s, height: 0.33 * s), top: s * 0.035, bottom: s * 0.13)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = rgb(0x3A2580, 0.35)
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.02)
    shadow.shadowBlurRadius = s * 0.035
    shadow.set()
    ink.setFill()
    body.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [rgb(0x3A3852), rgb(0x1C1B29), rgb(0x14131E)], atLocations: [0, 0.45, 1], colorSpace: .sRGB)!.draw(in: body, angle: -90)

    // Camera lens on the forehead
    rgb(0x0B0B14).setFill()
    oval(0.5 * s, 0.655 * s, 0.024 * s, 0.024 * s).fill()
    rgb(0x2E3A8C).setFill()
    oval(0.5 * s, 0.655 * s, 0.014 * s, 0.014 * s).fill()
    rgb(0x7CF5C4, 0.9).setFill()
    oval(0.495 * s, 0.66 * s, 0.005 * s, 0.005 * s).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for px in sizes {
    if px <= 512 { try! render(px).write(to: iconset.appendingPathComponent("icon_\(px)x\(px).png")) }
    if px >= 32 { try! render(px).write(to: iconset.appendingPathComponent("icon_\(px / 2)x\(px / 2)@2x.png")) }
}
