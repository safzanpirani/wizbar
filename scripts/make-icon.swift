// Renders Resources/AppIcon.icns: a warm glowing bulb on a dusk squircle.
// Run: swift scripts/make-icon.swift
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let size = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // macOS icon grid: 824/1024 body with ~185.4 corner radius.
    let inset = size * 100 / 1024
    let body = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let squircle = NSBezierPath(roundedRect: body, xRadius: size * 185.4 / 1024, yRadius: size * 185.4 / 1024)

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = size * 0.03
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.012)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor(srgbRed: 0.12, green: 0.09, blue: 0.16, alpha: 1).setFill()
    squircle.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    squircle.addClip()
    NSGradient(colors: [
        NSColor(srgbRed: 0.24, green: 0.15, blue: 0.30, alpha: 1),
        NSColor(srgbRed: 0.08, green: 0.06, blue: 0.13, alpha: 1),
    ])!.draw(in: body, angle: -90)
    let glowCenter = NSPoint(x: size / 2, y: size * 0.56)
    NSGradient(colors: [
        NSColor(srgbRed: 1.0, green: 0.78, blue: 0.45, alpha: 0.95),
        NSColor(srgbRed: 1.0, green: 0.55, blue: 0.25, alpha: 0.35),
        NSColor(srgbRed: 1.0, green: 0.45, blue: 0.2, alpha: 0),
    ], atLocations: [0, 0.45, 1], colorSpace: .sRGB)!
        .draw(fromCenter: glowCenter, radius: 0, toCenter: glowCenter, radius: size * 0.42, options: [])
    NSGraphicsContext.restoreGraphicsState()

    let config = NSImage.SymbolConfiguration(pointSize: size * 0.40, weight: .medium)
        .applying(.init(paletteColors: [NSColor(srgbRed: 1, green: 0.98, blue: 0.93, alpha: 1)]))
    if let bulb = NSImage(systemSymbolName: "lightbulb.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let s = bulb.size
        bulb.draw(in: NSRect(x: (size - s.width) / 2, y: (size - s.height) / 2 + size * 0.01, width: s.width, height: s.height))
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}

let output = root.appendingPathComponent("Resources/AppIcon.icns")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try task.run()
task.waitUntilExit()
try render(1024).write(to: FileManager.default.temporaryDirectory.appendingPathComponent("wizbar-icon-preview.png"))
print("wrote \(output.path)")
