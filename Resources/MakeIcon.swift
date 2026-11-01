// Renders the 1024×1024 app icon: an orange squircle with a cream "play window" glyph.
// Usage: swift MakeIcon.swift <output.png>
import AppKit

let out = CommandLine.arguments.dropFirst().first ?? "icon.png"
let side = 1024.0

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(side), pixelsHigh: Int(side),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// macOS icon grid: an 824pt body centred on the 1024 canvas.
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

let shadow = NSShadow()
shadow.shadowBlurRadius = 30
shadow.shadowOffset = NSSize(width: 0, height: -14)
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
NSGraphicsContext.saveGraphicsState()
shadow.set()
NSColor(red: 0.9, green: 0.32, blue: 0.1, alpha: 1).setFill()
shape.fill()
NSGraphicsContext.restoreGraphicsState()

NSGradient(colors: [
    NSColor(red: 1.0, green: 0.76, blue: 0.30, alpha: 1),
    NSColor(red: 1.0, green: 0.55, blue: 0.10, alpha: 1),
    NSColor(red: 0.88, green: 0.30, blue: 0.09, alpha: 1),
])!.draw(in: shape, angle: -65)

// Soft highlight on the upper half.
NSGraphicsContext.saveGraphicsState()
shape.addClip()
NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0)])!
    .draw(in: NSRect(x: 100, y: 512, width: 824, height: 412), angle: -90)
NSGraphicsContext.restoreGraphicsState()

// Cream app window with a soft drop shadow.
let cream = NSColor(red: 1.0, green: 0.96, blue: 0.9, alpha: 1)
let window = NSRect(x: 232, y: 262, width: 560, height: 470)
let windowShape = NSBezierPath(roundedRect: window, xRadius: 64, yRadius: 64)
NSGraphicsContext.saveGraphicsState()
let glyphShadow = NSShadow()
glyphShadow.shadowBlurRadius = 24
glyphShadow.shadowOffset = NSSize(width: 0, height: -10)
glyphShadow.shadowColor = NSColor(red: 0.5, green: 0.15, blue: 0.02, alpha: 0.35)
glyphShadow.set()
cream.setFill()
windowShape.fill()
NSGraphicsContext.restoreGraphicsState()

// Title-bar dots.
let dotColor = NSColor(red: 1.0, green: 0.62, blue: 0.2, alpha: 0.55)
for i in 0..<3 {
    dotColor.setFill()
    NSBezierPath(ovalIn: NSRect(x: window.minX + 52 + Double(i) * 50, y: window.maxY - 78, width: 30, height: 30)).fill()
}

// Orange play triangle with rounded corners.
let cx = window.midX + 12, cy = window.midY - 30, r = 118.0
let play = NSBezierPath()
play.move(to: NSPoint(x: cx - r * 0.75, y: cy + r))
play.line(to: NSPoint(x: cx + r, y: cy))
play.line(to: NSPoint(x: cx - r * 0.75, y: cy - r))
play.close()
play.lineJoinStyle = .round
play.lineWidth = 44
let playColor = NSColor(red: 0.96, green: 0.45, blue: 0.08, alpha: 1)
playColor.setFill()
playColor.setStroke()
play.fill()
play.stroke()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
