import Cocoa

func renderSimpleIcon(size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()

    let context = NSGraphicsContext.current?.cgContext
    let rect = CGRect(x: 0, y: 0, width: size, height: size)

    // Modern macOS squircle
    let inset = size * 0.08
    let iconRect = rect.insetBy(dx: inset, dy: inset)
    let cornerRadius = iconRect.width * 0.224
    let path = CGPath(roundedRect: iconRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

    context?.saveGState()
    context?.addPath(path)
    context?.clip()

    // Clean matte dark charcoal / graphite background
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bgColors = [
        NSColor(red: 0.16, green: 0.17, blue: 0.19, alpha: 1.0).cgColor,
        NSColor(red: 0.09, green: 0.10, blue: 0.11, alpha: 1.0).cgColor
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 1.0]) {
        context?.drawLinearGradient(gradient, start: CGPoint(x: 0, y: iconRect.maxY), end: CGPoint(x: 0, y: iconRect.minY), options: [])
    }

    // Subtle edge border
    context?.setStrokeColor(NSColor.white.withAlphaComponent(0.1).cgColor)
    context?.setLineWidth(size * 0.015)
    context?.addPath(path)
    context?.strokePath()

    // Draw minimalist, elegant bold "Q" in clean white / light gray
    let qFontSize = size * 0.54
    let font = NSFont.systemFont(ofSize: qFontSize, weight: .bold)
    let text = "Q" as NSString
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(white: 0.95, alpha: 1.0)
    ]
    let textSize = text.size(withAttributes: attrs)
    let textPoint = CGPoint(
        x: (size - textSize.width) / 2,
        y: (size - textSize.height) / 2 - (size * 0.02)
    )
    text.draw(at: textPoint, withAttributes: attrs)

    context?.restoreGState()
    img.unlockFocus()
    return img
}

let fm = FileManager.default
let iconsetDir = "/Users/mmtechstore/.gemini/antigravity-ide/scratch/superkill/Resources/AppIcon.iconset"
try? fm.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

let sizes: [(Int, Int)] = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2)
]

for (pt, scale) in sizes {
    let px = pt * scale
    let img = renderSimpleIcon(size: CGFloat(px))
    guard let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        continue
    }

    let filename = (scale == 1) ? "icon_\(pt)x\(pt).png" : "icon_\(pt)x\(pt)@2x.png"
    let path = "\(iconsetDir)/\(filename)"
    try? png.write(to: URL(fileURLWithPath: path))
}

print("Simple iconset created at \(iconsetDir)")
