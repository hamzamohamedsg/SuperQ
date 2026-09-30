import Cocoa
import AVFoundation

final class VideoRenderer {
    let width = 1920
    let height = 1080
    let fps: Int32 = 30
    let durationSeconds = 10
    var totalFrames: Int { Int(fps) * durationSeconds }

    func render(outputPath: String) {
        let outputURL = URL(fileURLWithPath: outputPath)
        try? FileManager.default.removeItem(at: outputURL)

        guard let writer = try? AVAssetWriter(outputURL: outputURL, fileType: .mp4) else {
            print("Failed to create AVAssetWriter")
            return
        }

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 8_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]

        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false

        let sourceBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: sourceBufferAttributes
        )

        writer.add(writerInput)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        var pixelBufferPool: CVPixelBufferPool? = adaptor.pixelBufferPool

        for frameIndex in 0..<totalFrames {
            while !writerInput.isReadyForMoreMediaData {
                usleep(1000)
            }

            var pixelBuffer: CVPixelBuffer?
            let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, adaptor.pixelBufferPool ?? pixelBufferPool!, &pixelBuffer)
            guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
                continue
            }

            CVPixelBufferLockBaseAddress(buffer, [])
            let pixelData = CVPixelBufferGetBaseAddress(buffer)
            let rgbColorSpace = CGColorSpaceCreateDeviceRGB()

            let context = CGContext(
                data: pixelData,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: rgbColorSpace,
                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
            )

            if let ctx = context {
                let time = Double(frameIndex) / Double(fps)
                drawFrame(in: ctx, time: time)
            }

            CVPixelBufferUnlockBaseAddress(buffer, [])

            let frameTime = CMTime(value: Int64(frameIndex), timescale: fps)
            adaptor.append(buffer, withPresentationTime: frameTime)

            if frameIndex % 30 == 0 {
                print("Rendering frame \(frameIndex)/\(totalFrames)... (\(Int(timeProgression(frameIndex) * 100))%)")
            }
        }

        writerInput.markAsFinished()
        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting {
            semaphore.signal()
        }
        semaphore.wait()

        print("Video rendering complete! Saved to \(outputPath)")
    }

    private func timeProgression(_ frame: Int) -> Double {
        return Double(frame) / Double(totalFrames)
    }

    // MARK: - Frame Drawing
    private func drawFrame(in ctx: CGContext, time: Double) {
        NSGraphicsContext.saveGraphicsState()
        let nsContext = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.current = nsContext

        // Background wallpaper (Dark modern macOS slate / deep navy)
        drawWallpaper(in: ctx)

        // Menu bar at top
        drawMenuBar(in: ctx, time: time)

        // Scene sequencing
        if time < 2.5 {
            // Scene 1: Title Card (0.0s - 2.5s)
            drawSceneTitle(in: ctx, time: time)
        } else if time < 5.0 {
            // Scene 2: Frozen / Beachball app (2.5s - 5.0s)
            drawSceneFrozenApp(in: ctx, time: time - 2.5)
        } else if time < 7.2 {
            // Scene 3: Keystroke ⇧⌘Q and Instant Kill (5.0s - 7.2s)
            drawSceneKillAction(in: ctx, time: time - 5.0)
        } else {
            // Scene 4: Minimal Menu Bar Showcase & Outro (7.2s - 10.0s)
            drawSceneMenuShowcase(in: ctx, time: time - 7.2)
        }

        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawWallpaper(in ctx: CGContext) {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let colors = [
            NSColor(red: 0.11, green: 0.13, blue: 0.17, alpha: 1.0).cgColor,
            NSColor(red: 0.05, green: 0.06, blue: 0.08, alpha: 1.0).cgColor
        ] as CFArray
        if let grad = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0]) {
            ctx.drawLinearGradient(grad, start: CGPoint(x: 960, y: 1080), end: CGPoint(x: 960, y: 0), options: [])
        }

        // Subtle ambient spotlight
        ctx.saveGState()
        let spotColors = [
            NSColor(red: 0.20, green: 0.25, blue: 0.35, alpha: 0.35).cgColor,
            NSColor.clear.cgColor
        ] as CFArray
        if let spotGrad = CGGradient(colorsSpace: colorSpace, colors: spotColors, locations: [0.0, 1.0]) {
            ctx.drawRadialGradient(spotGrad, startCenter: CGPoint(x: 960, y: 540), startRadius: 0, endCenter: CGPoint(x: 960, y: 540), endRadius: 700, options: [])
        }
        ctx.restoreGState()
    }

    private func drawMenuBar(in ctx: CGContext, time: Double) {
        let barRect = CGRect(x: 0, y: 1040, width: 1920, height: 40)
        ctx.setFillColor(NSColor(white: 0.08, alpha: 0.85).cgColor)
        ctx.fill(barRect)

        // Apple Logo & Menu items
        drawText("  Finder  File  Edit  View  Go  Window  Help", at: CGPoint(x: 24, y: 1050), font: .systemFont(ofSize: 15, weight: .regular), color: NSColor(white: 0.85, alpha: 1.0))

        // Right side: WiFi, Battery, Date, and SuperQ "Q" item
        let timeString = "Thu 1:45 PM"
        drawText(timeString, at: CGPoint(x: 1800, y: 1050), font: .systemFont(ofSize: 14, weight: .regular), color: NSColor(white: 0.8, alpha: 1.0))

        // SuperQ 'Q' in menu bar
        let qRect = CGRect(x: 1735, y: 1044, width: 32, height: 32)
        if time > 7.2 {
            ctx.setFillColor(NSColor.white.withAlphaComponent(0.2).cgColor)
            ctx.fill(qRect)
        }
        drawText("Q", at: CGPoint(x: 1745, y: 1050), font: .systemFont(ofSize: 16, weight: .bold), color: .white)
    }

    // MARK: - Scene 1: Title Card
    private func drawSceneTitle(in ctx: CGContext, time: Double) {
        let alpha = min(time * 2.0, 1.0) * (time > 2.0 ? max(0, (2.5 - time) * 2.0) : 1.0)
        ctx.saveGState()
        ctx.setAlpha(CGFloat(alpha))

        // SuperQ App Icon
        let iconSize: CGFloat = 160
        let iconRect = CGRect(x: (CGFloat(width) - iconSize) / 2, y: 570, width: iconSize, height: iconSize)
        drawIcon(in: ctx, rect: iconRect)

        // Title
        drawCenteredText("SuperQ", y: 470, font: .systemFont(ofSize: 64, weight: .bold), color: .white)

        // Subtitle
        drawCenteredText("SuperF4 for macOS", y: 400, font: .systemFont(ofSize: 28, weight: .semibold), color: NSColor(red: 0.95, green: 0.35, blue: 0.40, alpha: 1.0))

        drawCenteredText("Instant Force-Quit with  ⇧ ⌘ Q", y: 340, font: .systemFont(ofSize: 22, weight: .regular), color: NSColor(white: 0.7, alpha: 1.0))

        ctx.restoreGState()
    }

    // MARK: - Scene 2: Frozen App
    private func drawSceneFrozenApp(in ctx: CGContext, time: Double) {
        let windowRect = CGRect(x: 460, y: 260, width: 1000, height: 580)
        drawWindow(in: ctx, rect: windowRect, title: "UnresponsiveApp (Not Responding)", isFrozen: true, time: time)

        // Warning banner
        drawCenteredText("⌘Q ignored. App is frozen.", y: 170, font: .systemFont(ofSize: 24, weight: .semibold), color: NSColor(red: 1.0, green: 0.4, blue: 0.4, alpha: 0.9))
    }

    // MARK: - Scene 3: Kill Action
    private func drawSceneKillAction(in ctx: CGContext, time: Double) {
        if time < 0.9 {
            // App still visible, keys appearing
            let windowRect = CGRect(x: 460, y: 260, width: 1000, height: 580)
            drawWindow(in: ctx, rect: windowRect, title: "UnresponsiveApp (Not Responding)", isFrozen: true, time: time)
        }

        // Draw Floating Shortcut Keys
        let keyY: CGFloat = (time < 0.9) ? 140 : 620
        drawShortcutKeys(in: ctx, y: keyY, isPressed: time >= 0.7)

        if time >= 0.9 {
            // App has been KILLED! Draw HUD
            let hudAlpha = min((time - 0.9) * 4.0, 1.0)
            ctx.saveGState()
            ctx.setAlpha(CGFloat(hudAlpha))

            let hudRect = CGRect(x: (CGFloat(width) - 440) / 2, y: 360, width: 440, height: 110)
            drawHUD(in: ctx, rect: hudRect)

            ctx.restoreGState()
        }
    }

    // MARK: - Scene 4: Menu Showcase
    private func drawSceneMenuShowcase(in ctx: CGContext, time: Double) {
        // Draw open menu from the 'Q' status item
        let menuRect = CGRect(x: 1610, y: 770, width: 280, height: 265)
        drawMenuDropdown(in: ctx, rect: menuRect)

        // End Title & Punchline
        let textAlpha = min(time * 2.0, 1.0)
        ctx.saveGState()
        ctx.setAlpha(CGFloat(textAlpha))

        drawText("SuperQ", at: CGPoint(x: 200, y: 620), font: .systemFont(ofSize: 68, weight: .heavy), color: .white)
        drawText("Zero Bloat. 0.0% CPU. Pure Speed.", at: CGPoint(x: 200, y: 550), font: .systemFont(ofSize: 32, weight: .medium), color: NSColor(red: 0.95, green: 0.40, blue: 0.45, alpha: 1.0))

        drawText("✓ Instant SIGKILL Kernel Termination", at: CGPoint(x: 200, y: 460), font: .systemFont(ofSize: 22, weight: .regular), color: NSColor(white: 0.85, alpha: 1.0))
        drawText("✓ Fully Customizable Keyboard Shortcuts", at: CGPoint(x: 200, y: 410), font: .systemFont(ofSize: 22, weight: .regular), color: NSColor(white: 0.85, alpha: 1.0))
        drawText("✓ Toggleable Sound & Visual Pop-up", at: CGPoint(x: 200, y: 360), font: .systemFont(ofSize: 22, weight: .regular), color: NSColor(white: 0.85, alpha: 1.0))
        drawText("✓ Open Source • Free Forever", at: CGPoint(x: 200, y: 310), font: .systemFont(ofSize: 22, weight: .semibold), color: NSColor(white: 0.70, alpha: 1.0))

        ctx.restoreGState()
    }

    // MARK: - Helper UI Drawings
    private func drawIcon(in ctx: CGContext, rect: CGRect) {
        ctx.saveGState()
        let path = CGPath(roundedRect: rect, cornerWidth: rect.width * 0.22, cornerHeight: rect.height * 0.22, transform: nil)
        ctx.addPath(path)
        ctx.clip()

        // Icon gradient
        let colors = [
            NSColor(red: 0.18, green: 0.19, blue: 0.22, alpha: 1.0).cgColor,
            NSColor(red: 0.09, green: 0.10, blue: 0.12, alpha: 1.0).cgColor
        ] as CFArray
        if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 1.0]) {
            ctx.drawLinearGradient(grad, start: CGPoint(x: rect.midX, y: rect.maxY), end: CGPoint(x: rect.midX, y: rect.minY), options: [])
        }

        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.15).cgColor)
        ctx.setLineWidth(rect.width * 0.02)
        ctx.addPath(path)
        ctx.strokePath()

        // Icon 'Q' text
        let font = NSFont.systemFont(ofSize: rect.width * 0.58, weight: .bold)
        let text = "Q" as NSString
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let size = text.size(withAttributes: attrs)
        text.draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2 - rect.height * 0.04), withAttributes: attrs)

        ctx.restoreGState()
    }

    private func drawWindow(in ctx: CGContext, rect: CGRect, title: String, isFrozen: Bool, time: Double) {
        ctx.saveGState()
        // Window shadow
        ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 30, color: NSColor.black.withAlphaComponent(0.6).cgColor)

        // Window background
        let path = CGPath(roundedRect: rect, cornerWidth: 12, cornerHeight: 12, transform: nil)
        ctx.setFillColor(NSColor(red: 0.13, green: 0.14, blue: 0.16, alpha: 0.98).cgColor)
        ctx.addPath(path)
        ctx.fillPath()
        ctx.restoreGState()

        // Title bar
        let titleBarRect = CGRect(x: rect.minX, y: rect.maxY - 38, width: rect.width, height: 38)
        ctx.setFillColor(NSColor(red: 0.16, green: 0.17, blue: 0.20, alpha: 1.0).cgColor)
        ctx.fill(titleBarRect)

        // Window buttons (red, yellow, green)
        let btnY = rect.maxY - 24
        drawCircle(in: ctx, center: CGPoint(x: rect.minX + 20, y: btnY), radius: 6, color: NSColor(red: 1.0, green: 0.38, blue: 0.36, alpha: 1.0))
        drawCircle(in: ctx, center: CGPoint(x: rect.minX + 40, y: btnY), radius: 6, color: NSColor(red: 1.0, green: 0.75, blue: 0.24, alpha: 1.0))
        drawCircle(in: ctx, center: CGPoint(x: rect.minX + 60, y: btnY), radius: 6, color: NSColor(red: 0.16, green: 0.80, blue: 0.38, alpha: 1.0))

        // Title
        drawCenteredText(title, y: rect.maxY - 28, font: .systemFont(ofSize: 13, weight: .medium), color: NSColor(white: 0.8, alpha: 1.0))

        // Content: Beachball or frozen spinner
        if isFrozen {
            let cx = rect.midX
            let cy = rect.midY + 20
            drawBeachball(in: ctx, center: CGPoint(x: cx, y: cy), radius: 36, rotation: CGFloat(time * 6.0))

            drawCenteredText("Waiting for application to respond...", y: cy - 70, font: .systemFont(ofSize: 18, weight: .regular), color: NSColor(white: 0.6, alpha: 1.0))
        }
    }

    private func drawBeachball(in ctx: CGContext, center: CGPoint, radius: CGFloat, rotation: CGFloat) {
        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: rotation)

        let colors: [NSColor] = [
            NSColor(red: 0.95, green: 0.25, blue: 0.25, alpha: 1.0),
            NSColor(red: 0.98, green: 0.60, blue: 0.20, alpha: 1.0),
            NSColor(red: 0.98, green: 0.90, blue: 0.20, alpha: 1.0),
            NSColor(red: 0.25, green: 0.85, blue: 0.30, alpha: 1.0),
            NSColor(red: 0.20, green: 0.55, blue: 0.95, alpha: 1.0),
            NSColor(red: 0.70, green: 0.30, blue: 0.90, alpha: 1.0)
        ]

        let angleStep = (CGFloat.pi * 2) / CGFloat(colors.count)
        for (i, c) in colors.enumerated() {
            ctx.beginPath()
            ctx.move(to: .zero)
            ctx.addArc(center: .zero, radius: radius, startAngle: CGFloat(i) * angleStep, endAngle: CGFloat(i + 1) * angleStep, clockwise: false)
            ctx.setFillColor(c.cgColor)
            ctx.fillPath()
        }

        ctx.restoreGState()
    }

    private func drawShortcutKeys(in ctx: CGContext, y: CGFloat, isPressed: Bool) {
        let keys = ["⇧", "⌘", "Q"]
        let keyWidth: CGFloat = 85
        let keyHeight: CGFloat = 85
        let gap: CGFloat = 16
        let totalWidth = CGFloat(keys.count) * keyWidth + CGFloat(keys.count - 1) * gap
        let startX = (CGFloat(width) - totalWidth) / 2

        for (i, key) in keys.enumerated() {
            let kx = startX + CGFloat(i) * (keyWidth + gap)
            let kRect = CGRect(x: kx, y: y, width: keyWidth, height: keyHeight)

            ctx.saveGState()
            if isPressed {
                ctx.setShadow(offset: .zero, blur: 24, color: NSColor(red: 0.95, green: 0.30, blue: 0.35, alpha: 0.9).cgColor)
            } else {
                ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 12, color: NSColor.black.withAlphaComponent(0.4).cgColor)
            }

            let path = CGPath(roundedRect: kRect, cornerWidth: 14, cornerHeight: 14, transform: nil)
            ctx.addPath(path)

            if isPressed {
                ctx.setFillColor(NSColor(red: 0.95, green: 0.25, blue: 0.30, alpha: 1.0).cgColor)
            } else {
                ctx.setFillColor(NSColor(red: 0.20, green: 0.22, blue: 0.26, alpha: 0.95).cgColor)
            }
            ctx.fillPath()

            ctx.setStrokeColor(NSColor.white.withAlphaComponent(isPressed ? 0.6 : 0.2).cgColor)
            ctx.setLineWidth(2)
            ctx.addPath(path)
            ctx.strokePath()

            ctx.restoreGState()

            // Key text
            let font = NSFont.systemFont(ofSize: 42, weight: .bold)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
            let size = (key as NSString).size(withAttributes: attrs)
            (key as NSString).draw(at: CGPoint(x: kRect.midX - size.width / 2, y: kRect.midY - size.height / 2), withAttributes: attrs)
        }
    }

    private func drawHUD(in ctx: CGContext, rect: CGRect) {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 24, color: NSColor.black.withAlphaComponent(0.6).cgColor)

        let path = CGPath(roundedRect: rect, cornerWidth: 18, cornerHeight: 18, transform: nil)
        ctx.addPath(path)
        ctx.setFillColor(NSColor(red: 0.12, green: 0.13, blue: 0.15, alpha: 0.95).cgColor)
        ctx.fillPath()

        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.2).cgColor)
        ctx.setLineWidth(1.5)
        ctx.addPath(path)
        ctx.strokePath()
        ctx.restoreGState()

        // Icon inside HUD
        let iconRect = CGRect(x: rect.minX + 24, y: rect.minY + 23, width: 64, height: 64)
        drawIcon(in: ctx, rect: iconRect)

        // Text
        drawText("UnresponsiveApp", at: CGPoint(x: rect.minX + 104, y: rect.minY + 62), font: .systemFont(ofSize: 22, weight: .bold), color: .white)

        // Red badge
        let badgeRect = CGRect(x: rect.minX + 310, y: rect.minY + 64, width: 104, height: 24)
        let bPath = CGPath(roundedRect: badgeRect, cornerWidth: 6, cornerHeight: 6, transform: nil)
        ctx.setFillColor(NSColor(red: 0.95, green: 0.22, blue: 0.26, alpha: 1.0).cgColor)
        ctx.addPath(bPath)
        ctx.fillPath()
        drawText("FORCE QUIT", at: CGPoint(x: badgeRect.minX + 11, y: badgeRect.minY + 5), font: .systemFont(ofSize: 12, weight: .heavy), color: .white)

        drawText("Terminated instantly • PID 48291", at: CGPoint(x: rect.minX + 104, y: rect.minY + 34), font: .systemFont(ofSize: 15, weight: .medium), color: NSColor(white: 0.7, alpha: 1.0))
    }

    private func drawMenuDropdown(in ctx: CGContext, rect: CGRect) {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 18, color: NSColor.black.withAlphaComponent(0.5).cgColor)

        let path = CGPath(roundedRect: rect, cornerWidth: 8, cornerHeight: 8, transform: nil)
        ctx.addPath(path)
        ctx.setFillColor(NSColor(red: 0.16, green: 0.17, blue: 0.20, alpha: 0.96).cgColor)
        ctx.fillPath()

        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.15).cgColor)
        ctx.setLineWidth(1)
        ctx.addPath(path)
        ctx.strokePath()
        ctx.restoreGState()

        // Menu items
        let items = [
            ("Force Quit Active App", "⇧⌘Q"),
            ("Shortcut (⇧⌘Q)", "▸"),
            ("Play Sound", "✓"),
            ("Show Pop-up", "✓"),
            ("Launch at Login", "✓"),
            ("Quit SuperQ", "")
        ]

        for (i, item) in items.enumerated() {
            let y = rect.maxY - CGFloat(38 * (i + 1))
            drawText(item.0, at: CGPoint(x: rect.minX + 16, y: y + 6), font: .systemFont(ofSize: 14, weight: .regular), color: .white)
            drawText(item.1, at: CGPoint(x: rect.maxX - 45, y: y + 6), font: .systemFont(ofSize: 14, weight: .semibold), color: NSColor(white: 0.7, alpha: 1.0))
        }
    }

    private func drawCircle(in ctx: CGContext, center: CGPoint, radius: CGFloat, color: NSColor) {
        ctx.setFillColor(color.cgColor)
        ctx.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }

    private func drawText(_ text: String, at point: CGPoint, font: NSFont, color: NSColor) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        (text as NSString).draw(at: point, withAttributes: attrs)
    }

    private func drawCenteredText(_ text: String, y: CGFloat, font: NSFont, color: NSColor) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (text as NSString).size(withAttributes: attrs)
        let x = (CGFloat(width) - size.width) / 2
        (text as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: attrs)
    }
}

let renderer = VideoRenderer()
let scriptDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let outputPath = scriptDir.appendingPathComponent("superq_demo.mp4").path
renderer.render(outputPath: outputPath)
