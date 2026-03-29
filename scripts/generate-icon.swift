#!/usr/bin/swift
// generate-icon.swift
// Renders the Tidy Gmail app icon (envelope.badge.shield.half.filled SF Symbol on a
// blue gradient rounded-rect background) and writes AppIcon.icns to the given directory.
//
// Usage:  swift scripts/generate-icon.swift [output-dir]
// Requires macOS 14+.

import AppKit

// Initialise AppKit (required for SF Symbol rendering) without showing a UI.
NSApplication.shared.setActivationPolicy(.prohibited)

let outputDir   = CommandLine.arguments.dropFirst().first ?? "."
let iconsetPath = (outputDir as NSString).appendingPathComponent("AppIcon.iconset")
let icnsPath    = (outputDir as NSString).appendingPathComponent("AppIcon.icns")
let fm          = FileManager.default

try! fm.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true, attributes: nil)

// MARK: - Render one PNG

func makePNG(pixelSize: Int) -> Data {
    let s = CGFloat(pixelSize)

    // Off-screen bitmap rep (bottom-left origin, RGBA).
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: s, height: s)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    defer { NSGraphicsContext.restoreGraphicsState() }

    let ctx = NSGraphicsContext.current!.cgContext

    // Rounded-rect clip.
    let radius = s * 0.22
    ctx.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: s, height: s),
                       cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.clip()

    // Blue gradient (top-left → bottom-right).
    let space = CGColorSpaceCreateDeviceRGB()
    let stops = [CGColor(red: 0.25, green: 0.55, blue: 1.00, alpha: 1),
                 CGColor(red: 0.08, green: 0.28, blue: 0.85, alpha: 1)] as CFArray
    if let grad = CGGradient(colorsSpace: space, colors: stops, locations: [0, 1]) {
        ctx.drawLinearGradient(grad,
                               start: CGPoint(x: 0, y: s),
                               end:   CGPoint(x: s, y: 0),
                               options: [])
    }

    // White SF Symbol, centred.
    // Strategy: draw the template symbol into a scratch image, then sourceIn-fill white
    // to tint it — sourceIn keeps the symbol's alpha and replaces the colour with white.
    let ptSize = s * 0.52
    let cfg = NSImage.SymbolConfiguration(pointSize: ptSize, weight: .medium)
    if let raw = NSImage(systemSymbolName: "envelope.badge.shield.half.filled",
                          accessibilityDescription: nil)?
                    .withSymbolConfiguration(cfg) {
        let tinted = NSImage(size: raw.size)
        tinted.lockFocus()
        raw.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1.0)
        NSColor.white.setFill()
        NSRect(origin: .zero, size: raw.size).fill(using: .sourceIn)
        tinted.unlockFocus()

        let x = (s - tinted.size.width)  / 2
        let y = (s - tinted.size.height) / 2
        tinted.draw(in: NSRect(x: x, y: y, width: tinted.size.width, height: tinted.size.height),
                    from: .zero, operation: .sourceOver, fraction: 1.0)
    }

    return rep.representation(using: .png, properties: [:])!
}

// MARK: - All required iconset sizes

let sizes: [(name: String, pt: Int, scale: Int)] = [
    ("icon_16x16",       16, 1), ("icon_16x16@2x",    16, 2),
    ("icon_32x32",       32, 1), ("icon_32x32@2x",    32, 2),
    ("icon_128x128",    128, 1), ("icon_128x128@2x", 128, 2),
    ("icon_256x256",    256, 1), ("icon_256x256@2x", 256, 2),
    ("icon_512x512",    512, 1), ("icon_512x512@2x", 512, 2),
]

for (name, pt, scale) in sizes {
    let px  = pt * scale
    let png = makePNG(pixelSize: px)
    try! png.write(to: URL(fileURLWithPath: "\(iconsetPath)/\(name).png"))
    print("  ✓ \(name).png  (\(px)px)")
}

// MARK: - Convert iconset → icns

let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments     = ["-c", "icns", iconsetPath, "-o", icnsPath]
try! proc.run()
proc.waitUntilExit()

guard proc.terminationStatus == 0 else {
    fputs("✗ iconutil failed (exit \(proc.terminationStatus))\n", stderr)
    exit(1)
}

try! fm.removeItem(atPath: iconsetPath)
print("✓ AppIcon.icns → \(icnsPath)")
