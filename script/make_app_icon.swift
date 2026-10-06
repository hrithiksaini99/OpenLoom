import AppKit
import Foundation

// Original code-drawn icon, matching the ribbon mark in StudioStyle.swift.
// Generated locally as part of packaging; no downloaded or AI-created assets.
let iconDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: iconDirectory, withIntermediateDirectories: true)

func drawIcon(pixels: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                       colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: bitmap) else { throw CocoaError(.fileWriteUnknown) }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    defer { NSGraphicsContext.restoreGraphicsState() }
    context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    context.cgContext.setAllowsAntialiasing(true)
    let tile = NSBezierPath(roundedRect: NSRect(x: 96, y: 108, width: 832, height: 832), xRadius: 184, yRadius: 184)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
    shadow.shadowBlurRadius = 26
    shadow.shadowOffset = .init(width: 0, height: -14)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor.systemPurple.setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    let coral = NSColor(srgbRed: 0.93, green: 0.37, blue: 0.32, alpha: 1)
    let violet = NSColor(srgbRed: 0.48, green: 0.34, blue: 0.88, alpha: 1)
    NSGradient(starting: coral, ending: violet)!.draw(in: tile, angle: -45)
    NSColor.white.withAlphaComponent(0.14).setStroke()
    tile.lineWidth = 2
    tile.stroke()
    let ribbon = NSBezierPath()
    func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint { .init(x: 246 + x * 532, y: 790 - y * 532) }
    ribbon.move(to: point(0.1, 0.52))
    ribbon.curve(to: point(0.53, 0.39), controlPoint1: point(0.08, 0.1), controlPoint2: point(0.38, 0.06))
    ribbon.curve(to: point(0.9, 0.48), controlPoint1: point(0.78, 0.88), controlPoint2: point(0.94, 0.88))
    ribbon.curve(to: point(0.47, 0.61), controlPoint1: point(0.92, 0.1), controlPoint2: point(0.63, 0.08))
    ribbon.curve(to: point(0.1, 0.52), controlPoint1: point(0.22, 0.92), controlPoint2: point(0.06, 0.88))
    ribbon.lineWidth = 65
    ribbon.lineCapStyle = .round
    ribbon.lineJoinStyle = .round
    NSColor.white.setStroke()
    ribbon.stroke()
    guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
    return data
}

for size in [16, 32, 128, 256, 512] {
    try drawIcon(pixels: size).write(to: iconDirectory.appendingPathComponent("icon_\(size)x\(size).png"))
    try drawIcon(pixels: size * 2).write(to: iconDirectory.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
