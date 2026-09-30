import Cocoa
import CoreGraphics
import os

final class TargetKillController: NSResponder {
    static let shared = TargetKillController()
    private let logger = Logger(subsystem: "com.antigravity.superkill", category: "TargetKill")

    private var overlayWindows: [NSWindow] = []
    private var isTargeting = false

    private override init() {
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func startTargetKill() {
        guard !isTargeting else { return }
        isTargeting = true
        logger.info("Entering Target Kill mode")

        NSCursor.crosshair.push()

        // Create overlay on all connected screens
        for screen in NSScreen.screens {
            let overlay = TargetOverlayWindow(contentRect: screen.frame, targetController: self)
            overlay.orderFrontRegardless()
            overlayWindows.append(overlay)
        }

        // Show instructional notification
        HUDController.shared.show(
            appName: "Target Kill Mode",
            appIcon: NSImage(systemSymbolName: "scope", accessibilityDescription: nil),
            pid: ProcessInfo.processInfo.processIdentifier
        )
    }

    func stopTargetKill() {
        guard isTargeting else { return }
        isTargeting = false
        logger.info("Exiting Target Kill mode")

        NSCursor.pop()

        for window in overlayWindows {
            window.orderOut(nil)
        }
        overlayWindows.removeAll()
    }

    func handleClicked(at screenPoint: NSPoint) {
        stopTargetKill()

        // Find window under screenPoint
        // In CGWindowList, coordinates are top-left based (Y starts from top of primary screen)
        guard let primaryScreen = NSScreen.screens.first else { return }
        let cgY = primaryScreen.frame.height - screenPoint.y
        let cgPoint = CGPoint(x: screenPoint.x, y: cgY)

        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            logger.error("Failed to retrieve CGWindowList")
            return
        }

        let myPid = ProcessInfo.processInfo.processIdentifier

        for windowInfo in windowList {
            guard let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  let pid = windowInfo[kCGWindowOwnerPID as String] as? pid_t else {
                continue
            }

            // Don't kill ourselves or background window layers
            if pid == myPid { continue }
            if bounds.contains(cgPoint) {
                logger.notice("Found target window for PID \(pid) under click")
                _ = KillManager.shared.forceQuitPID(pid)
                return
            }
        }
    }
}

private final class TargetOverlayWindow: NSWindow {
    private weak var targetController: TargetKillController?

    init(contentRect: NSRect, targetController: TargetKillController) {
        self.targetController = targetController
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        self.level = .screenSaver // High level to capture events
        self.isOpaque = false
        self.backgroundColor = NSColor.black.withAlphaComponent(0.01) // Nearly transparent
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true

        let customView = TargetOverlayView(targetController: targetController)
        customView.frame = NSRect(origin: .zero, size: contentRect.size)
        customView.autoresizingMask = [.width, .height]
        self.contentView = customView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC
            targetController?.stopTargetKill()
        } else {
            super.keyDown(with: event)
        }
    }
}

private final class TargetOverlayView: NSView {
    private weak var targetController: TargetKillController?

    init(targetController: TargetKillController) {
        self.targetController = targetController
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        let point = NSEvent.mouseLocation
        targetController?.handleClicked(at: point)
    }

    override func rightMouseDown(with event: NSEvent) {
        targetController?.stopTargetKill()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .crosshair)
    }
}
