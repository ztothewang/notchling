import AppKit
// Frames raw app renders (notch.png, editor.png in <dir>) into README images in <out>:
// hero.png puts the notch panel at the top of a desktop; editor.png rounds and shadows the window.
let dir = CommandLine.arguments[1], out = CommandLine.arguments[2]
let variant = CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : "light"

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func canvas(_ w: Int, _ h: Int, _ draw: (CGFloat, CGFloat) -> Void) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(CGFloat(w), CGFloat(h))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

func image(_ name: String) -> (NSImage, NSSize) {
    let rep = NSImageRep(contentsOfFile: "\(dir)/\(name)")!
    let img = NSImage(size: NSSize(width: rep.pixelsWide, height: rep.pixelsHigh))
    img.addRepresentation(rep)
    return (img, img.size)
}

// Hero: top of a screen with a menu bar, the notch panel hanging from the top edge.
let (notch, ns) = image("notch.png")
let hero = canvas(2400, 440) { w, h in
    let screen = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: w, height: h), xRadius: 40, yRadius: 40)
    screen.addClip()
    NSGradient(colors: [rgb(0xFFC9DD), rgb(0xD5B8FF), rgb(0x8FA8FF)], atLocations: [0, 0.55, 1], colorSpace: .sRGB)!.draw(in: screen, angle: -60)
    let barH: CGFloat = 76 // notch height at 2x
    rgb(0xFFFFFF, 0.35).setFill()
    NSRect(x: 0, y: h - barH, width: w, height: barH).fill()
    let left = ["", "Notchling", "Edit", "Prompter", "Window"]
    var x: CGFloat = 56
    for (i, item) in left.enumerated() {
        let font = i == 1 ? NSFont.systemFont(ofSize: 27, weight: .bold) : NSFont.systemFont(ofSize: 27)
        let s = NSAttributedString(string: item, attributes: [.font: font, .foregroundColor: rgb(0x1C1B29, 0.85)])
        s.draw(at: NSPoint(x: x, y: h - barH + 22))
        x += s.size().width + (item.isEmpty ? 0 : 44)
    }
    let clock = NSAttributedString(string: "Mon Nov 9  4:20 PM", attributes: [.font: NSFont.systemFont(ofSize: 27), .foregroundColor: rgb(0x1C1B29, 0.85)])
    clock.draw(at: NSPoint(x: w - clock.size().width - 56, y: h - barH + 22))
    notch.draw(in: NSRect(x: (w - ns.width) / 2, y: h - ns.height, width: ns.width, height: ns.height))
}
if variant == "light" { try! hero.write(to: URL(fileURLWithPath: "\(out)/hero.png")) }

// Editor: the render already includes the window frame and traffic lights; add rounding and a shadow.
let (editor, es) = image("editor.png")
let pad: CGFloat = 80
let framed = canvas(Int(es.width + pad * 2), Int(es.height + pad * 2)) { w, h in
    let win = NSRect(x: pad, y: pad, width: es.width, height: es.height)
    let path = NSBezierPath(roundedRect: win, xRadius: 24, yRadius: 24)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = rgb(0x000000, 0.22)
    shadow.shadowOffset = NSSize(width: 0, height: -16)
    shadow.shadowBlurRadius = 48
    shadow.set()
    rgb(0xFFFFFF).setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()
    path.addClip()
    editor.draw(in: win)
    rgb(0x000000, 0.12).setStroke()
    path.lineWidth = 2
    path.stroke()
}
try! framed.write(to: URL(fileURLWithPath: "\(out)/editor-\(variant).png"))
