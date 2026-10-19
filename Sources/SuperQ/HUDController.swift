import Cocoa

final class HUDController: NSWindowController {
    static let shared = HUDController()

    // Modern HUD
    private var effectView: NSVisualEffectView!
    private var iconImageView: NSImageView!
    private var titleLabel: NSTextField!
    private var badgeLabel: NSTextField!
    private var subtitleLabel: NSTextField!

    // Windows 95 Retro HUD
    private var win95View: Win95PopupView!

    private var dismissWorkItem: DispatchWorkItem?

    private init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 334, height: 128),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        super.init(window: panel)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        guard let panel = window else { return }

        // Setup Windows 95 View
        win95View = Win95PopupView(frame: NSRect(x: 0, y: 0, width: 334, height: 128))
        win95View.autoresizingMask = [.width, .height]
        win95View.onDismiss = { [weak self] in
            self?.dismissImmediately()
        }

        // Setup Modern effect view
        effectView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 340, height: 80))
        effectView.autoresizingMask = [.width, .height]
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 18
        effectView.layer?.masksToBounds = true
        effectView.layer?.borderWidth = 1.0
        effectView.layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor

        // Modern Icon
        iconImageView = NSImageView(frame: NSRect(x: 18, y: 16, width: 48, height: 48))
        iconImageView.imageScaling = .scaleProportionallyUpOrDown
        iconImageView.wantsLayer = true
        iconImageView.layer?.cornerRadius = 10
        iconImageView.layer?.masksToBounds = true
        effectView.addSubview(iconImageView)

        // Modern Text container
        let textContainer = NSView(frame: NSRect(x: 78, y: 16, width: 244, height: 48))

        // Title (App Name)
        titleLabel = NSTextField(labelWithString: "Application")
        titleLabel.frame = NSRect(x: 0, y: 24, width: 170, height: 22)
        titleLabel.font = NSFont.systemFont(ofSize: 15, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.lineBreakMode = .byTruncatingTail
        textContainer.addSubview(titleLabel)

        // Badge ("FORCE QUIT")
        badgeLabel = NSTextField(labelWithString: "FORCE QUIT")
        badgeLabel.frame = NSRect(x: 172, y: 26, width: 72, height: 18)
        badgeLabel.font = NSFont.systemFont(ofSize: 9, weight: .heavy)
        badgeLabel.textColor = .white
        badgeLabel.alignment = .center
        badgeLabel.wantsLayer = true
        badgeLabel.layer?.backgroundColor = NSColor(red: 0.95, green: 0.22, blue: 0.25, alpha: 0.95).cgColor
        badgeLabel.layer?.cornerRadius = 5
        badgeLabel.layer?.masksToBounds = true
        textContainer.addSubview(badgeLabel)

        // Subtitle (PID info)
        subtitleLabel = NSTextField(labelWithString: "Terminated instantly")
        subtitleLabel.frame = NSRect(x: 0, y: 4, width: 244, height: 18)
        subtitleLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        subtitleLabel.textColor = NSColor.white.withAlphaComponent(0.7)
        subtitleLabel.lineBreakMode = .byTruncatingTail
        textContainer.addSubview(subtitleLabel)

        effectView.addSubview(textContainer)

        // Default content view
        panel.contentView = win95View
    }

    func show(appName: String, appIcon: NSImage?, pid: pid_t, killedCount: Int = 1) {
        guard let panel = window else { return }

        // Cancel pending dismiss
        dismissWorkItem?.cancel()

        let screen = NSScreen.main ?? NSScreen.screens.first
        let screenFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        switch SettingsManager.shared.currentTheme {
        case .windows95, .windows95Dark:
            let isDark = (SettingsManager.shared.currentTheme == .windows95Dark)
            panel.ignoresMouseEvents = false
            panel.contentView = win95View
            win95View.configure(appName: appName, appIcon: appIcon, pid: pid, isDark: isDark, killedCount: killedCount)

            let width: CGFloat = 334
            let height: CGFloat = 128
            let x = screenFrame.origin.x + (screenFrame.width - width) / 2
            let y = screenFrame.origin.y + 90
            panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)

            panel.alphaValue = 0.0
            panel.orderFrontRegardless()

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1.0
            }

            // Auto-dismiss after 0.9 seconds with quick fade out (matching modern HUD)
            let workItem = DispatchWorkItem { [weak self, weak panel] in
                guard let panel = panel else { return }
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.25
                    context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    panel.animator().alphaValue = 0.0
                }, completionHandler: {
                    if panel.alphaValue == 0.0 {
                        panel.orderOut(nil)
                    }
                })
                self?.dismissWorkItem = nil
            }
            dismissWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: workItem)

        case .modern:
            panel.ignoresMouseEvents = true
            panel.contentView = effectView

            titleLabel.stringValue = appName
            subtitleLabel.stringValue = killedCount > 1
                ? "Terminated with \(killedCount) processes"
                : "Terminated instantly • PID \(pid)"
            if let icon = appIcon {
                iconImageView.image = icon
            } else {
                iconImageView.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: nil)
            }

            let maxTitleWidth: CGFloat = 160
            let measuredWidth = min(titleLabel.attributedStringValue.size().width + 8, maxTitleWidth)
            titleLabel.frame = NSRect(x: 0, y: 24, width: measuredWidth, height: 22)

            let badgeText = killedCount > 1 ? "\(killedCount) KILLED" : "FORCE QUIT"
            badgeLabel.stringValue = badgeText
            let badgeWidth = max(70, badgeLabel.attributedStringValue.size().width + 12)
            badgeLabel.frame = NSRect(x: measuredWidth + 6, y: 27, width: badgeWidth, height: 16)

            let width: CGFloat = 340
            let height: CGFloat = 80
            let x = screenFrame.origin.x + (screenFrame.width - width) / 2
            let y = screenFrame.origin.y + 90
            panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)

            panel.alphaValue = 0.0
            panel.orderFrontRegardless()

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1.0
            }

            let workItem = DispatchWorkItem { [weak self, weak panel] in
                guard let panel = panel else { return }
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.25
                    context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    panel.animator().alphaValue = 0.0
                }, completionHandler: {
                    if panel.alphaValue == 0.0 {
                        panel.orderOut(nil)
                    }
                })
                self?.dismissWorkItem = nil
            }
            dismissWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: workItem)
        }
    }

    func dismissImmediately() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        guard let panel = window else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0.0
        }, completionHandler: {
            if panel.alphaValue == 0.0 {
                panel.orderOut(nil)
            }
        })
    }
}
