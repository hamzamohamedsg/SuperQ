import Cocoa

final class Win95PopupView: NSView {
    var onDismiss: (() -> Void)?

    private var appName: String = "Application"
    private var pid: pid_t = 0
    private var appIcon: NSImage?
    var isDark: Bool = false

    private var standardGray: NSColor {
        // Dock sampled exact gray from screenshot: #494949 (73, 73, 73)
        isDark
            ? NSColor(calibratedRed: 73/255, green: 73/255, blue: 73/255, alpha: 1.0)
            : NSColor(calibratedRed: 192/255, green: 192/255, blue: 192/255, alpha: 1.0)
    }

    private var closeButtonFrame: NSRect = .zero
    private var okButtonFrame: NSRect = .zero
    private var isClosePressed = false
    private var isOKPressed = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(appName: String, appIcon: NSImage?, pid: pid_t, isDark: Bool = false) {
        self.appName = appName
        self.appIcon = appIcon
        self.pid = pid
        self.isDark = isDark
        self.isClosePressed = false
        self.isOKPressed = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let bounds = self.bounds

        // 1. Window 3D Bevel Background
        drawWindowBevel(in: bounds)

        // 2. Title Bar Frame and Close Button geometry
        let titleBarRect = NSRect(x: 3, y: bounds.height - 23, width: bounds.width - 6, height: 20)
        closeButtonFrame = NSRect(x: bounds.width - 21, y: bounds.height - 21, width: 16, height: 16)
        okButtonFrame = NSRect(x: (bounds.width - 75) / 2, y: 12, width: 75, height: 23)

        // 3. Draw Title Bar
        drawTitleBar(in: titleBarRect)

        // 4. Draw Close Button
        drawCloseButton(in: closeButtonFrame, isPressed: isClosePressed)

        // 5. Draw Critical Error Stop Icon
        let iconRect = NSRect(x: 18, y: bounds.height - 76, width: 34, height: 34)
        drawStopIcon(in: iconRect)

        // 6. Draw Content Text
        drawContentText(in: bounds)

        // 7. Draw OK Button
        drawOKButton(in: okButtonFrame, isPressed: isOKPressed)
    }

    private func drawWindowBevel(in bounds: NSRect) {
        let bg = standardGray
        bg.setFill()
        bounds.fill()

        let white = NSColor.white
        let lightGray = NSColor(calibratedRed: 223/255, green: 223/255, blue: 223/255, alpha: 1.0)
        let darkGray = NSColor(calibratedRed: 128/255, green: 128/255, blue: 128/255, alpha: 1.0)
        let black = NSColor.black

        // Outer 1px frame
        white.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
        NSRect(x: 0, y: 0, width: 1, height: bounds.height).fill()

        black.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
        NSRect(x: bounds.width - 1, y: 0, width: 1, height: bounds.height).fill()

        // Inner 1px frame
        lightGray.setFill()
        NSRect(x: 1, y: bounds.height - 2, width: bounds.width - 2, height: 1).fill()
        NSRect(x: 1, y: 1, width: 1, height: bounds.height - 2).fill()

        darkGray.setFill()
        NSRect(x: 1, y: 1, width: bounds.width - 2, height: 1).fill()
        NSRect(x: bounds.width - 2, y: 1, width: 1, height: bounds.height - 2).fill()
    }

    private func drawTitleBar(in rect: NSRect) {
        let navyStart = NSColor(calibratedRed: 0/255, green: 0/255, blue: 128/255, alpha: 1.0)
        let navyEnd = NSColor(calibratedRed: 16/255, green: 132/255, blue: 208/255, alpha: 1.0)
        if let gradient = NSGradient(starting: navyStart, ending: navyEnd) {
            gradient.draw(in: rect, angle: 0)
        } else {
            navyStart.setFill()
            rect.fill()
        }

        var textX = rect.minX + 4
        if let icon = appIcon {
            let iconRect = NSRect(x: rect.minX + 3, y: rect.minY + 3, width: 14, height: 14)
            icon.draw(in: iconRect)
            textX += 17
        }

        let titleStr = "Terminated - \(appName)"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 11),
            .foregroundColor: NSColor.white
        ]
        let maxTextWidth = max(closeButtonFrame.minX - textX - 4, 40)
        let textRect = NSRect(x: textX, y: rect.minY + 2, width: maxTextWidth, height: 15)
        titleStr.draw(with: textRect, options: [.truncatesLastVisibleLine, .usesLineFragmentOrigin], attributes: attrs)
    }

    private func drawCloseButton(in rect: NSRect, isPressed: Bool) {
        let face = standardGray
        face.setFill()
        rect.fill()

        let white = NSColor.white
        let darkGray = NSColor(calibratedRed: 128/255, green: 128/255, blue: 128/255, alpha: 1.0)
        let black = NSColor.black

        if isPressed {
            darkGray.setFill()
            NSRect(x: rect.minX, y: rect.maxY - 1, width: rect.width, height: 1).fill()
            NSRect(x: rect.minX, y: rect.minY, width: 1, height: rect.height).fill()
            white.setFill()
            NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: 1).fill()
            NSRect(x: rect.maxX - 1, y: rect.minY, width: 1, height: rect.height).fill()
        } else {
            white.setFill()
            NSRect(x: rect.minX, y: rect.maxY - 1, width: rect.width, height: 1).fill()
            NSRect(x: rect.minX, y: rect.minY, width: 1, height: rect.height).fill()
            black.setFill()
            NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: 1).fill()
            NSRect(x: rect.maxX - 1, y: rect.minY, width: 1, height: rect.height).fill()
            darkGray.setFill()
            NSRect(x: rect.minX + 1, y: rect.minY + 1, width: rect.width - 2, height: 1).fill()
            NSRect(x: rect.maxX - 2, y: rect.minY + 1, width: 1, height: rect.height - 2).fill()
        }

        let shift: CGFloat = isPressed ? 1.0 : 0.0
        let xCenter = rect.midX + shift
        let yCenter = rect.midY - shift
        let size: CGFloat = 3.5

        let path = NSBezierPath()
        path.move(to: NSPoint(x: xCenter - size, y: yCenter - size))
        path.line(to: NSPoint(x: xCenter + size, y: yCenter + size))
        path.move(to: NSPoint(x: xCenter - size, y: yCenter + size))
        path.line(to: NSPoint(x: xCenter + size, y: yCenter - size))
        black.setStroke()
        path.lineWidth = 1.6
        path.stroke()
    }

    private func drawStopIcon(in rect: NSRect) {
        let circleRect = rect.insetBy(dx: 1, dy: 1)

        let darkRed = NSColor(calibratedRed: 120/255, green: 0, blue: 0, alpha: 1.0)
        let mainRed = NSColor(calibratedRed: 200/255, green: 0, blue: 0, alpha: 1.0)

        let path = NSBezierPath(ovalIn: circleRect)
        mainRed.setFill()
        path.fill()

        darkRed.setStroke()
        path.lineWidth = 1.0
        path.stroke()

        let xInset: CGFloat = 8.0
        let xRect = circleRect.insetBy(dx: xInset, dy: xInset)

        let xPath = NSBezierPath()
        xPath.move(to: NSPoint(x: xRect.minX, y: xRect.minY))
        xPath.line(to: NSPoint(x: xRect.maxX, y: xRect.maxY))
        xPath.move(to: NSPoint(x: xRect.minX, y: xRect.maxY))
        xPath.line(to: NSPoint(x: xRect.maxX, y: xRect.minY))

        NSGraphicsContext.saveGraphicsState()
        darkRed.setStroke()
        xPath.lineWidth = 4.5
        xPath.lineCapStyle = .square
        var transform = AffineTransform()
        transform.translate(x: 1, y: -1)
        let shadowPath = (xPath.copy() as! NSBezierPath)
        shadowPath.transform(using: transform)
        shadowPath.stroke()

        NSColor.white.setStroke()
        xPath.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawContentText(in bounds: NSRect) {
        let textX: CGFloat = 66.0
        let textYStart = bounds.height - 38.0
        let availableWidth = bounds.width - textX - 16.0

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 12),
            .foregroundColor: NSColor.black
        ]
        let titleText = "\(appName) was terminated."
        let titleRect = NSRect(x: textX, y: textYStart - 18, width: availableWidth, height: 18)
        titleText.draw(with: titleRect, options: [.truncatesLastVisibleLine, .usesLineFragmentOrigin], attributes: titleAttrs)

        let subAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.black
        ]
        let subText = "Process ID: \(pid)  •  Status: SIGKILL"
        let subRect = NSRect(x: textX, y: textYStart - 36, width: availableWidth, height: 16)
        subText.draw(with: subRect, options: [.truncatesLastVisibleLine, .usesLineFragmentOrigin], attributes: subAttrs)

        let hintAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor(calibratedWhite: 0.35, alpha: 1.0)
        ]
        let hintText = "Application closed immediately."
        let hintRect = NSRect(x: textX, y: textYStart - 52, width: availableWidth, height: 14)
        hintText.draw(with: hintRect, options: [.truncatesLastVisibleLine, .usesLineFragmentOrigin], attributes: hintAttrs)
    }

    private func drawOKButton(in rect: NSRect, isPressed: Bool) {
        let face = standardGray
        face.setFill()
        rect.fill()

        let white = NSColor.white
        let darkGray = NSColor(calibratedRed: 128/255, green: 128/255, blue: 128/255, alpha: 1.0)
        let black = NSColor.black

        black.setFill()
        NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: 1).fill()
        NSRect(x: rect.minX, y: rect.maxY - 1, width: rect.width, height: 1).fill()
        NSRect(x: rect.minX, y: rect.minY, width: 1, height: rect.height).fill()
        NSRect(x: rect.maxX - 1, y: rect.minY, width: 1, height: rect.height).fill()

        let inner = rect.insetBy(dx: 1, dy: 1)

        if isPressed {
            darkGray.setFill()
            NSRect(x: inner.minX, y: inner.maxY - 1, width: inner.width, height: 1).fill()
            NSRect(x: inner.minX, y: inner.minY, width: 1, height: inner.height).fill()
            white.setFill()
            NSRect(x: inner.minX, y: inner.minY, width: inner.width, height: 1).fill()
            NSRect(x: inner.maxX - 1, y: inner.minY, width: 1, height: inner.height).fill()
        } else {
            white.setFill()
            NSRect(x: inner.minX, y: inner.maxY - 1, width: inner.width, height: 1).fill()
            NSRect(x: inner.minX, y: inner.minY, width: 1, height: inner.height).fill()
            darkGray.setFill()
            NSRect(x: inner.minX, y: inner.minY, width: inner.width, height: 1).fill()
            NSRect(x: inner.maxX - 1, y: inner.minY, width: 1, height: inner.height).fill()
        }

        let focusRect = rect.insetBy(dx: 4, dy: 4)
        let focusPath = NSBezierPath(rect: focusRect)
        focusPath.lineWidth = 1.0
        let pattern: [CGFloat] = [1.0, 1.0]
        focusPath.setLineDash(pattern, count: 2, phase: 0)
        black.setStroke()
        focusPath.stroke()

        let shift: CGFloat = isPressed ? 1.0 : 0.0
        let title = "OK"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.black
        ]
        let textSize = title.size(withAttributes: attrs)
        let textPoint = NSPoint(
            x: rect.midX - textSize.width / 2 + shift,
            y: rect.midY - textSize.height / 2 - shift
        )
        title.draw(at: textPoint, withAttributes: attrs)
    }

    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        if closeButtonFrame.contains(loc) {
            isClosePressed = true
            needsDisplay = true
        } else if okButtonFrame.contains(loc) {
            isOKPressed = true
            needsDisplay = true
        } else {
            onDismiss?()
        }
    }

    override func mouseUp(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        if isClosePressed {
            isClosePressed = false
            needsDisplay = true
            if closeButtonFrame.contains(loc) {
                onDismiss?()
            }
        } else if isOKPressed {
            isOKPressed = false
            needsDisplay = true
            if okButtonFrame.contains(loc) {
                onDismiss?()
            }
        }
    }
}
