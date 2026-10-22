// Renders the 1024×1024 MedoTouchPar app icon.
// A glass Touch Bar holding app tiles, one being tapped (touch ring) and one
// carrying a notification badge, on a deep indigo macOS squircle.
// Usage: swift scripts/make_icon.swift <output.png>
import AppKit

let output = CommandLine.arguments.dropFirst().first ?? "icon_1024.png"
let canvas: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvas), pixelsHigh: Int(canvas),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// Superellipse ("squircle") like the macOS icon shape.
func squircle(_ rect: NSRect, exponent n: CGFloat = 5) -> NSBezierPath {
    let path = NSBezierPath()
    let a = rect.width / 2, b = rect.height / 2
    let steps = 720
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = a * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n)
        let y = b * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n)
        let p = NSPoint(x: rect.midX + x, y: rect.midY + y)
        i == 0 ? path.move(to: p) : path.line(to: p)
    }
    path.close()
    return path
}

func symbol(_ name: String, size: CGFloat, color: NSColor) -> NSImage {
    let config = NSImage.SymbolConfiguration(pointSize: size, weight: .semibold)
    let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)!.withSymbolConfiguration(config)!
    let tinted = NSImage(size: base.size)
    tinted.lockFocus()
    base.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
    color.set()
    NSRect(origin: .zero, size: base.size).fill(using: .sourceAtop)
    tinted.unlockFocus()
    return tinted
}

// MARK: Body

let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = squircle(body)

NSGraphicsContext.saveGraphicsState()
let drop = NSShadow()
drop.shadowColor = NSColor.black.withAlphaComponent(0.4)
drop.shadowOffset = NSSize(width: 0, height: -14)
drop.shadowBlurRadius = 30
drop.set()
rgb(0x0A0C1C).setFill()
shape.fill()
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.saveGraphicsState()
shape.addClip()
NSGradient(colors: [rgb(0x34408F), rgb(0x1A1F4F), rgb(0x090B18)], atLocations: [0, 0.48, 1],
           colorSpace: .sRGB)!.draw(in: body, angle: -90)
// Ambient glow under the bar (soft radial falloff, squashed vertically).
if let cg = NSGraphicsContext.current?.cgContext,
   let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                         colors: [rgb(0x6C8CFF, 0.5).cgColor, rgb(0x6C8CFF, 0.18).cgColor, rgb(0x6C8CFF, 0).cgColor] as CFArray,
                         locations: [0, 0.45, 1]) {
    cg.saveGState()
    cg.translateBy(x: 512, y: 516)
    cg.scaleBy(x: 1, y: 0.55)
    cg.drawRadialGradient(glow, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 440, options: [])
    cg.restoreGState()
}
// Top sheen.
NSGradient(colors: [NSColor.white.withAlphaComponent(0.16), NSColor.white.withAlphaComponent(0)])!
    .draw(in: NSRect(x: body.minX, y: body.maxY - 300, width: body.width, height: 300), angle: -90)
NSGraphicsContext.restoreGraphicsState()

// Fine inner rim.
NSGraphicsContext.saveGraphicsState()
let rim = squircle(body.insetBy(dx: 2, dy: 2))
NSColor.white.withAlphaComponent(0.10).setStroke()
rim.lineWidth = 3
rim.stroke()
NSGraphicsContext.restoreGraphicsState()

// MARK: Touch Bar

let bar = NSRect(x: 150, y: 430, width: 724, height: 172)
let barPath = NSBezierPath(roundedRect: bar, xRadius: 40, yRadius: 40)
NSGraphicsContext.saveGraphicsState()
let barShadow = NSShadow()
barShadow.shadowColor = NSColor.black.withAlphaComponent(0.6)
barShadow.shadowOffset = NSSize(width: 0, height: -10)
barShadow.shadowBlurRadius = 26
barShadow.set()
rgb(0x030409).setFill()
barPath.fill()
NSGraphicsContext.restoreGraphicsState()
NSGraphicsContext.saveGraphicsState()
barPath.addClip()
NSGradient(colors: [rgb(0x1A1C26), rgb(0x05060A)])!.draw(in: bar, angle: -90)
NSGradient(colors: [NSColor.white.withAlphaComponent(0.14), NSColor.white.withAlphaComponent(0)])!
    .draw(in: NSRect(x: bar.minX, y: bar.midY + 10, width: bar.width, height: bar.height / 2), angle: -90)
NSGraphicsContext.restoreGraphicsState()
let barRim = NSBezierPath(roundedRect: bar.insetBy(dx: 1.5, dy: 1.5), xRadius: 39, yRadius: 39)
NSColor.white.withAlphaComponent(0.22).setStroke()
barRim.lineWidth = 3
barRim.stroke()

// MARK: App tiles

struct Tile { let top: UInt32; let bottom: UInt32; let glyph: String }
let tiles = [
    Tile(top: 0x5BF675, bottom: 0x0EBE3A, glyph: "message.fill"),
    Tile(top: 0x5AC8FF, bottom: 0x0A6CFF, glyph: "safari.fill"),
    Tile(top: 0xFF6B8A, bottom: 0xF5224B, glyph: "music.note"),
    Tile(top: 0xFF5A4F, bottom: 0xD70F0F, glyph: "play.fill"),
    Tile(top: 0x7FB2FF, bottom: 0x2F6BFF, glyph: "envelope.fill"),
]
let side: CGFloat = 108
let gap: CGFloat = 24
let rowWidth = CGFloat(tiles.count) * side + CGFloat(tiles.count - 1) * gap
let startX = bar.midX - rowWidth / 2
let tileY = bar.midY - side / 2 + 8
var tileRects: [NSRect] = []

for (index, tile) in tiles.enumerated() {
    let rect = NSRect(x: startX + CGFloat(index) * (side + gap), y: tileY, width: side, height: side)
    tileRects.append(rect)
    let path = squircle(rect, exponent: 4.6)
    NSGraphicsContext.saveGraphicsState()
    let s = NSShadow()
    s.shadowColor = NSColor.black.withAlphaComponent(0.45)
    s.shadowOffset = NSSize(width: 0, height: -4)
    s.shadowBlurRadius = 8
    s.set()
    rgb(tile.bottom).setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    NSGradient(colors: [rgb(tile.top), rgb(tile.bottom)])!.draw(in: rect, angle: -90)
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.28), NSColor.white.withAlphaComponent(0)])!
        .draw(in: NSRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2), angle: -90)
    NSGraphicsContext.restoreGraphicsState()
    let glyph = symbol(tile.glyph, size: 52, color: .white)
    glyph.draw(in: NSRect(x: rect.midX - glyph.size.width / 2, y: rect.midY - glyph.size.height / 2,
                          width: glyph.size.width, height: glyph.size.height))
    // Running dot.
    NSColor.white.withAlphaComponent(0.9).setFill()
    NSBezierPath(ovalIn: NSRect(x: rect.midX - 6, y: bar.minY + 13, width: 12, height: 12)).fill()
}

// MARK: Touch ring on the browser tile

let touched = tileRects[1]
for (i, alpha) in [(0, 0.55), (1, 0.30), (2, 0.14)].map({ (CGFloat($0.0), CGFloat($0.1)) }) {
    let inset = -14 - i * 16
    let ring = NSBezierPath(roundedRect: touched.insetBy(dx: inset, dy: inset), xRadius: 40 + i * 14, yRadius: 40 + i * 14)
    rgb(0x9DB8FF, alpha).setStroke()
    ring.lineWidth = 5 - i
    ring.stroke()
}

// MARK: Badge on the messages tile

let badgeTile = tileRects[0]
let badge = NSRect(x: badgeTile.maxX - 40, y: badgeTile.maxY - 40, width: 64, height: 64)
NSGraphicsContext.saveGraphicsState()
let bs = NSShadow()
bs.shadowColor = NSColor.black.withAlphaComponent(0.5)
bs.shadowOffset = NSSize(width: 0, height: -3)
bs.shadowBlurRadius = 6
bs.set()
rgb(0xFF3B30).setFill()
NSBezierPath(ovalIn: badge).fill()
NSGraphicsContext.restoreGraphicsState()
let badgeRing = NSBezierPath(ovalIn: badge.insetBy(dx: 2, dy: 2))
rgb(0x0B0D17).setStroke()
badgeRing.lineWidth = 5
badgeRing.stroke()
let count = "3" as NSString
let countAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 40, weight: .heavy),
    .foregroundColor: NSColor.white,
]
let countSize = count.size(withAttributes: countAttrs)
count.draw(at: NSPoint(x: badge.midX - countSize.width / 2, y: badge.midY - countSize.height / 2 + 1), withAttributes: countAttrs)

// MARK: Keyboard hint below the bar

NSGraphicsContext.saveGraphicsState()
shape.addClip()
let keyWidth: CGFloat = 96, keyHeight: CGFloat = 64, keyGap: CGFloat = 16
for row in 0..<2 {
    let y = bar.minY - 70 - CGFloat(row) * (keyHeight + keyGap) - keyHeight
    let offset: CGFloat = row == 0 ? 0 : 44
    var x = bar.minX - 30 + offset
    while x < bar.maxX + 30 {
        let key = NSBezierPath(roundedRect: NSRect(x: x, y: y, width: keyWidth, height: keyHeight), xRadius: 14, yRadius: 14)
        NSColor.white.withAlphaComponent(row == 0 ? 0.07 : 0.04).setFill()
        key.fill()
        x += keyWidth + keyGap
    }
}
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("wrote \(output)")
