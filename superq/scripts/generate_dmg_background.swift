import Cocoa

func renderDMGBackground() {
    let width: CGFloat = 540
    let height: CGFloat = 360
    let scale: CGFloat = 2.0 // Retina @2x

    let img = NSImage(size: NSSize(width: width, height: height))
    img.lockFocus()

    let context = NSGraphicsContext.current?.cgContext
    let rect = CGRect(x: 0, y: 0, width: width, height: height)

    // Background gradient: Deep slate graphite
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bgColors = [
        NSColor(red: 0.14, green: 0.15, blue: 0.17, alpha: 1.0).cgColor,
        NSColor(red: 0.08, green: 0.09, blue: 0.10, alpha: 1.0).cgColor
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 1.0]) {
        context?.drawLinearGradient(gradient, start: CGPoint(x: 0, y: height), end: CGPoint(x: 0, y: 0), options: [])
    }

    // Header Instruction text
    let title = "Drag to Applications to Install" as NSString
    let titleFont = NSFont.systemFont(ofSize: 15, weight: .semibold)
    let titleAttrs: [NSAttributedString.Key: Any] = [
        .font: titleFont,
        .foregroundColor: NSColor(white: 0.90, alpha: 1.0)
    ]
    let titleSize = title.size(withAttributes: titleAttrs)
    title.draw(at: CGPoint(x: (width - titleSize.width) / 2, y: height - 58), withAttributes: titleAttrs)

    let sub = "Press ⇧⌘Q anytime to force quit" as NSString
    let subFont = NSFont.systemFont(ofSize: 12, weight: .regular)
    let subAttrs: [NSAttributedString.Key: Any] = [
        .font: subFont,
        .foregroundColor: NSColor(white: 0.55, alpha: 1.0)
    ]
    let subSize = sub.size(withAttributes: subAttrs)
    sub.draw(at: CGPoint(x: (width - subSize.width) / 2, y: height - 80), withAttributes: subAttrs)

    // Center Arrow (between left icon at 150 and right icon at 390)
    let arrowY: CGFloat = 190
    let arrowStartX: CGFloat = 240
    let arrowEndX: CGFloat = 300

    context?.saveGState()
    context?.setStrokeColor(NSColor(white: 0.45, alpha: 0.8).cgColor)
    context?.setLineWidth(2.5)
    context?.setLineCap(.round)
    context?.setLineJoin(.round)

    // Arrow line
    context?.move(to: CGPoint(x: arrowStartX, y: arrowY))
    context?.addLine(to: CGPoint(x: arrowEndX, y: arrowY))

    // Arrow head
    context?.move(to: CGPoint(x: arrowEndX - 8, y: arrowY + 8))
    context?.addLine(to: CGPoint(x: arrowEndX, y: arrowY))
    context?.addLine(to: CGPoint(x: arrowEndX - 8, y: arrowY - 8))
    context?.strokePath()
    context?.restoreGState()

    img.unlockFocus()

    // Export 2x PNG
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(width * scale),
        pixelsHigh: Int(height * scale),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )
    rep?.size = NSSize(width: width, height: height)

    NSGraphicsContext.saveGraphicsState()
    if let rep = rep {
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        img.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
    }
    NSGraphicsContext.restoreGraphicsState()

    if let pngData = rep?.representation(using: .png, properties: [:]) {
        let outputPath = "/Users/mmtechstore/.gemini/antigravity-ide/scratch/superkill/Resources/dmg_background.png"
        try? pngData.write(to: URL(fileURLWithPath: outputPath))
        print("DMG background saved to \(outputPath)")
    }
}

renderDMGBackground()
