// Renders the app icon as vector drawing at every size macOS needs, then packs Resources/AppIcon.icns.
//
//   swift scripts/make-icon.swift            writes Resources/AppIcon.icns
//   swift scripts/make-icon.swift --preview out.png   also writes a 1024 px PNG preview
//
// Layout follows Apple's macOS icon grid: 1024 canvas, 824 px rounded-square body, soft drop shadow.
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let output = root.appendingPathComponent("Resources/AppIcon.icns")

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

// Same colors as the panel tiles (Palette in PopoverView.swift), ordered low → high around the dial.
let segmentColors: [CGColor] = [rgb(0x40D18C), rgb(0x3399FF), rgb(0xAD7AFF), rgb(0xFF7359)]

func degrees(_ d: CGFloat) -> CGFloat { d * .pi / 180 }

func drawIcon(in ctx: CGContext) {
    // Everything below is in 1024-unit space; origin bottom-left.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // Drop shadow under the body.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0x000000, 0.35))
    ctx.addPath(bodyPath)
    ctx.setFillColor(rgb(0x16182F))
    ctx.fillPath()
    ctx.restoreGState()

    // Body: deep indigo vertical gradient.
    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()
    // Painted as one solid band per row instead of CGGradient: CoreGraphics dithers gradients,
    // and that per-pixel noise makes the PNGs several times larger.
    let top: (CGFloat, CGFloat, CGFloat) = (0x2D, 0x32, 0x63)
    let bottom: (CGFloat, CGFloat, CGFloat) = (0x12, 0x14, 0x2B)
    for row in 0..<824 {
        let t = CGFloat(row) / 823  // 0 at bottom, 1 at top
        let mix = { (a: CGFloat, b: CGFloat) in (a + (b - a) * t) / 255 }
        ctx.setFillColor(CGColor(srgbRed: mix(bottom.0, top.0), green: mix(bottom.1, top.1),
                                 blue: mix(bottom.2, top.2), alpha: 1))
        ctx.fill(CGRect(x: 100, y: 100 + CGFloat(row), width: 824, height: 1.0001))
    }
    // (No radial glow: it makes every pixel unique and bloats the PNGs ~4x for little visual gain.)
    ctx.restoreGState()

    // Hairline highlight on the body edge.
    ctx.addPath(CGPath(roundedRect: body.insetBy(dx: 2, dy: 2), cornerWidth: 183, cornerHeight: 183, transform: nil))
    ctx.setStrokeColor(rgb(0xFFFFFF, 0.10))
    ctx.setLineWidth(4)
    ctx.strokePath()

    // Dial: four colored segments over a 240° sweep (210° → -30°), round caps, small gaps.
    let center = CGPoint(x: 512, y: 455)
    let radius: CGFloat = 262
    let sweepStart: CGFloat = 210
    let segment: CGFloat = 60
    let gap: CGFloat = 20  // round caps add ~7° per end, so ~6° stays visible
    ctx.setLineWidth(66)
    ctx.setLineCap(.round)
    for (i, color) in segmentColors.enumerated() {
        let from = sweepStart - CGFloat(i) * segment - gap / 2
        let to = from - segment + gap
        ctx.addArc(center: center, radius: radius, startAngle: degrees(from), endAngle: degrees(to), clockwise: true)
        ctx.setStrokeColor(color)
        ctx.strokePath()
    }

    // Needle pointing into the purple (≈ 70%) zone, tapered, with a subtle shadow.
    let angle = degrees(48)
    let tip = CGPoint(x: center.x + cos(angle) * 225, y: center.y + sin(angle) * 225)
    let normal = CGPoint(x: -sin(angle), y: cos(angle))
    let baseHalf: CGFloat = 26
    let tipHalf: CGFloat = 7
    let needle = CGMutablePath()
    needle.move(to: CGPoint(x: center.x + normal.x * baseHalf, y: center.y + normal.y * baseHalf))
    needle.addLine(to: CGPoint(x: tip.x + normal.x * tipHalf, y: tip.y + normal.y * tipHalf))
    needle.addArc(center: tip, radius: tipHalf, startAngle: angle + .pi / 2, endAngle: angle - .pi / 2, clockwise: true)
    needle.addLine(to: CGPoint(x: center.x - normal.x * baseHalf, y: center.y - normal.y * baseHalf))
    needle.closeSubpath()

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: rgb(0x000000, 0.45))
    ctx.addPath(needle)
    ctx.setFillColor(rgb(0xFFFFFF))
    ctx.fillPath()
    ctx.addEllipse(in: CGRect(x: center.x - 52, y: center.y - 52, width: 104, height: 104))
    ctx.fillPath()
    ctx.restoreGState()

    // Hub center.
    ctx.addEllipse(in: CGRect(x: center.x - 20, y: center.y - 20, width: 40, height: 40))
    ctx.setFillColor(rgb(0x1C1F3D))
    ctx.fillPath()
}

func renderPNG(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    ctx.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
    ctx.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    ctx.setShouldAntialias(true)
    drawIcon(in: ctx)
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let iconset = fm.temporaryDirectory.appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: iconset) }

for points in [16, 32, 128, 256, 512] {
    try renderPNG(pixels: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try renderPNG(pixels: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
print("✓ \(output.path)")

let args = CommandLine.arguments
if let i = args.firstIndex(of: "--preview"), i + 1 < args.count {
    try renderPNG(pixels: 1024).write(to: URL(fileURLWithPath: args[i + 1]))
    print("✓ preview \(args[i + 1])")
}
