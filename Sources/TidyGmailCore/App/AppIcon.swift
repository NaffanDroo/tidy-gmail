import AppKit

/// Programmatically renders the Tidy Gmail app icon:
/// a blue-gradient rounded rect with the white envelope·badge·shield SF Symbol centred on it.
/// This matches the icon shown on the sign-in screen and sets the Dock / window icon at launch.
@MainActor
public func makeAppIcon(side: CGFloat = 512) -> NSImage {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(side),
        pixelsHigh: Int(side),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        return NSImage(systemSymbolName: "envelope.badge.shield.half.filled",
                       accessibilityDescription: nil) ?? NSImage()
    }
    rep.size = NSSize(width: side, height: side)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    defer { NSGraphicsContext.restoreGraphicsState() }

    if let ctx = NSGraphicsContext.current?.cgContext {
        drawBackground(in: ctx, side: side)
        drawSymbol(side: side)
    }

    let icon = NSImage(size: NSSize(width: side, height: side))
    icon.addRepresentation(rep)
    return icon
}

// MARK: - Private helpers

/// Clips to a rounded rect and fills it with a blue gradient.
@MainActor
private func drawBackground(in ctx: CGContext, side: CGFloat) {
    let radius = side * 0.22
    ctx.addPath(CGPath(
        roundedRect: CGRect(x: 0, y: 0, width: side, height: side),
        cornerWidth: radius,
        cornerHeight: radius,
        transform: nil
    ))
    ctx.clip()

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let gradientColors = [
        CGColor(red: 0.25, green: 0.55, blue: 1.00, alpha: 1),
        CGColor(red: 0.08, green: 0.28, blue: 0.85, alpha: 1)
    ] as CFArray
    let locations: [CGFloat] = [0, 1]
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: gradientColors, locations: locations) {
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: side),
            end: CGPoint(x: side, y: 0),
            options: []
        )
    }
}

/// Draws a white SF Symbol centred within the `side × side` canvas.
@MainActor
private func drawSymbol(side: CGFloat) {
    let symbolPointSize = side * 0.52
    let symbolConfig = NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .medium)
    guard let symbol = NSImage(
        systemSymbolName: "envelope.badge.shield.half.filled",
        accessibilityDescription: nil
    )?.withSymbolConfiguration(symbolConfig) else { return }

    // Tint the template image to white using sourceIn compositing
    let tinted = NSImage(size: symbol.size)
    tinted.lockFocus()
    symbol.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
    NSColor.white.setFill()
    NSRect(origin: .zero, size: symbol.size).fill(using: .sourceIn)
    tinted.unlockFocus()

    let xOffset = (side - tinted.size.width) / 2
    let yOffset = (side - tinted.size.height) / 2
    tinted.draw(
        in: NSRect(x: xOffset, y: yOffset, width: tinted.size.width, height: tinted.size.height),
        from: .zero,
        operation: .sourceOver,
        fraction: 1
    )
}
