import Cocoa
import os

final class MainWindowController: NSWindowController, NSWindowDelegate {
    static let shared = MainWindowController()
    private let logger = Logger(subsystem: "com.antigravity.superq", category: "MainWindowController")

    // UI Elements
    private var shortcutBadgeLabel: NSTextField!
    private var presetPopUp: NSPopUpButton!
    private var soundCheckbox: NSButton!
    private var hudCheckbox: NSButton!
    private var themePopUp: NSPopUpButton!
    private var launchAtLoginCheckbox: NSButton!

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 540),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SuperQ"
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        window.delegate = self
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        guard let window = window, let contentView = window.contentView else { return }

        // Root vertical stack
        let rootStack = NSStackView()
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 14
        rootStack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.topAnchor.constraint(equalTo: contentView.topAnchor),
            rootStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            rootStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        // 1. Header (Icon + Title + Subtitle + Status)
        let headerView = createHeaderView()
        rootStack.addArrangedSubview(headerView)
        headerView.widthAnchor.constraint(equalTo: rootStack.widthAnchor, constant: -48).isActive = true

        // 2. Action Card (Force Quit button)
        let actionCard = createActionCard()
        rootStack.addArrangedSubview(actionCard)
        actionCard.widthAnchor.constraint(equalTo: rootStack.widthAnchor, constant: -48).isActive = true

        // 3. Shortcut Card
        let shortcutCard = createShortcutCard()
        rootStack.addArrangedSubview(shortcutCard)
        shortcutCard.widthAnchor.constraint(equalTo: rootStack.widthAnchor, constant: -48).isActive = true

        // 4. Preferences Card (Sound, HUD, Theme, Login)
        let preferencesCard = createPreferencesCard()
        rootStack.addArrangedSubview(preferencesCard)
        preferencesCard.widthAnchor.constraint(equalTo: rootStack.widthAnchor, constant: -48).isActive = true

        // 5. Footer (Quit & Close)
        let footerView = createFooterView()
        rootStack.addArrangedSubview(footerView)
        footerView.widthAnchor.constraint(equalTo: rootStack.widthAnchor, constant: -48).isActive = true

        updateUI()
    }

    // MARK: - Subview Builders

    private func createHeaderView() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        // App Icon
        let iconView = NSImageView()
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        if let icon = NSApp.applicationIconImage {
            iconView.image = icon
        } else if let path = Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
                  let icon = NSImage(contentsOfFile: path) {
            iconView.image = icon
        } else {
            iconView.image = NSImage(systemSymbolName: "xmark.app.fill", accessibilityDescription: "SuperQ")
        }
        container.addSubview(iconView)

        // Text vertical stack
        let titleLabel = NSTextField(labelWithString: "SuperQ")
        titleLabel.font = NSFont.systemFont(ofSize: 20, weight: .bold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let subtitleLabel = NSTextField(labelWithString: "Instant Force-Quit for macOS")
        subtitleLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        let statusLabel = NSTextField(labelWithString: "● Active in Menu Bar")
        statusLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        statusLabel.textColor = NSColor.systemGreen
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(titleLabel)
        container.addSubview(subtitleLabel)
        container.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            iconView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 48),
            iconView.heightAnchor.constraint(equalToConstant: 48),

            titleLabel.topAnchor.constraint(equalTo: container.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 14),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),

            statusLabel.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 4),
            statusLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            statusLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        return container
    }

    private func createActionCard() -> NSBox {
        let box = NSBox()
        box.boxType = .custom
        box.borderColor = NSColor.separatorColor
        box.borderWidth = 1
        box.cornerRadius = 8
        box.fillColor = NSColor.controlBackgroundColor.withAlphaComponent(0.6)
        box.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        box.contentView = stack

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        let forceQuitButton = NSButton(title: "Force Quit Active App", target: self, action: #selector(handleForceQuitAction))
        forceQuitButton.bezelStyle = .rounded
        forceQuitButton.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        forceQuitButton.translatesAutoresizingMaskIntoConstraints = false
        buttonRow.addArrangedSubview(forceQuitButton)

        let testButton = NSButton(title: "Test Pop-up & Audio", target: self, action: #selector(handleTestFeedback))
        testButton.bezelStyle = .rounded
        testButton.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        testButton.translatesAutoresizingMaskIntoConstraints = false
        buttonRow.addArrangedSubview(testButton)

        stack.addArrangedSubview(buttonRow)

        let caption = NSTextField(labelWithString: "Terminates the foreground application immediately with kernel SIGKILL.")
        caption.font = NSFont.systemFont(ofSize: 11)
        caption.textColor = .secondaryLabelColor
        stack.addArrangedSubview(caption)

        return box
    }

    private func createShortcutCard() -> NSBox {
        let box = NSBox()
        box.boxType = .custom
        box.borderColor = NSColor.separatorColor
        box.borderWidth = 1
        box.cornerRadius = 8
        box.fillColor = NSColor.controlBackgroundColor.withAlphaComponent(0.6)
        box.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        box.contentView = stack

        // Title row
        let titleLabel = NSTextField(labelWithString: "Force-Quit Global Shortcut")
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        stack.addArrangedSubview(titleLabel)

        // Controls row (Badge + Preset PopUp + Custom + Reset)
        let controlsRow = NSStackView()
        controlsRow.orientation = .horizontal
        controlsRow.spacing = 8
        controlsRow.alignment = .centerY
        controlsRow.translatesAutoresizingMaskIntoConstraints = false

        // Shortcut badge container
        let badgeBox = NSView()
        badgeBox.wantsLayer = true
        badgeBox.layer?.cornerRadius = 5
        badgeBox.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor
        badgeBox.translatesAutoresizingMaskIntoConstraints = false

        shortcutBadgeLabel = NSTextField(labelWithString: "⇧⌘Q")
        shortcutBadgeLabel.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .bold)
        shortcutBadgeLabel.textColor = .controlAccentColor
        shortcutBadgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeBox.addSubview(shortcutBadgeLabel)

        NSLayoutConstraint.activate([
            shortcutBadgeLabel.topAnchor.constraint(equalTo: badgeBox.topAnchor, constant: 3),
            shortcutBadgeLabel.bottomAnchor.constraint(equalTo: badgeBox.bottomAnchor, constant: -3),
            shortcutBadgeLabel.leadingAnchor.constraint(equalTo: badgeBox.leadingAnchor, constant: 8),
            shortcutBadgeLabel.trailingAnchor.constraint(equalTo: badgeBox.trailingAnchor, constant: -8)
        ])
        controlsRow.addArrangedSubview(badgeBox)

        // Preset PopUp
        presetPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
        presetPopUp.target = self
        presetPopUp.action = #selector(handlePresetChanged(_:))
        presetPopUp.translatesAutoresizingMaskIntoConstraints = false
        for preset in ShortcutPreset.allCases {
            presetPopUp.addItem(withTitle: preset.displayName)
            presetPopUp.lastItem?.representedObject = preset
        }
        presetPopUp.addItem(withTitle: "Custom...")
        presetPopUp.lastItem?.representedObject = "custom"
        controlsRow.addArrangedSubview(presetPopUp)

        // Custom button
        let customBtn = NSButton(title: "Record...", target: self, action: #selector(openRecorder))
        customBtn.bezelStyle = .rounded
        controlsRow.addArrangedSubview(customBtn)

        // Reset button
        let resetBtn = NSButton(title: "Reset", target: self, action: #selector(resetShortcut))
        resetBtn.bezelStyle = .rounded
        controlsRow.addArrangedSubview(resetBtn)

        stack.addArrangedSubview(controlsRow)

        let desc = NSTextField(labelWithString: "Press this combination anywhere in macOS to instantly force quit.")
        desc.font = NSFont.systemFont(ofSize: 11)
        desc.textColor = .secondaryLabelColor
        stack.addArrangedSubview(desc)

        return box
    }

    private func createPreferencesCard() -> NSBox {
        let box = NSBox()
        box.boxType = .custom
        box.borderColor = NSColor.separatorColor
        box.borderWidth = 1
        box.cornerRadius = 8
        box.fillColor = NSColor.controlBackgroundColor.withAlphaComponent(0.6)
        box.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        box.contentView = stack

        let titleLabel = NSTextField(labelWithString: "Feedback & System Preferences")
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        stack.addArrangedSubview(titleLabel)

        // Row 1: Play Sound Checkbox
        soundCheckbox = NSButton(checkboxWithTitle: "Play sound on termination (Windows chime / modern audio)", target: self, action: #selector(handleSoundToggled(_:)))
        soundCheckbox.font = NSFont.systemFont(ofSize: 12)
        stack.addArrangedSubview(soundCheckbox)

        // Row 2: Show HUD Checkbox
        hudCheckbox = NSButton(checkboxWithTitle: "Show visual termination pop-up / HUD", target: self, action: #selector(handleHUDToggled(_:)))
        hudCheckbox.font = NSFont.systemFont(ofSize: 12)
        stack.addArrangedSubview(hudCheckbox)

        // Row 3: Pop-up Theme Selector
        let themeRow = NSStackView()
        themeRow.orientation = .horizontal
        themeRow.spacing = 8
        themeRow.alignment = .centerY
        themeRow.translatesAutoresizingMaskIntoConstraints = false

        let themeLabel = NSTextField(labelWithString: "Pop-up Theme:")
        themeLabel.font = NSFont.systemFont(ofSize: 12)
        themeRow.addArrangedSubview(themeLabel)

        themePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
        themePopUp.target = self
        themePopUp.action = #selector(handleThemeChanged(_:))
        for theme in HUDTheme.allCases {
            themePopUp.addItem(withTitle: theme.displayName)
            themePopUp.lastItem?.representedObject = theme
        }
        themeRow.addArrangedSubview(themePopUp)
        stack.addArrangedSubview(themeRow)

        // Row 4: Launch at Login Checkbox
        launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch SuperQ automatically at login", target: self, action: #selector(handleLaunchAtLoginToggled(_:)))
        launchAtLoginCheckbox.font = NSFont.systemFont(ofSize: 12)
        stack.addArrangedSubview(launchAtLoginCheckbox)

        return box
    }

    private func createFooterView() -> NSView {
        let footer = NSView()
        footer.translatesAutoresizingMaskIntoConstraints = false

        let quitButton = NSButton(title: "Quit SuperQ", target: self, action: #selector(handleQuitApp))
        quitButton.bezelStyle = .rounded
        quitButton.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(quitButton)

        let closeButton = NSButton(title: "Close Window", target: self, action: #selector(handleCloseWindow))
        closeButton.bezelStyle = .rounded
        closeButton.keyEquivalent = "\u{1b}" // Escape key
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(closeButton)

        let helperLabel = NSTextField(labelWithString: "SuperQ remains active in the menu bar when this window is closed.")
        helperLabel.font = NSFont.systemFont(ofSize: 10)
        helperLabel.textColor = .secondaryLabelColor
        helperLabel.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(helperLabel)

        NSLayoutConstraint.activate([
            quitButton.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            quitButton.topAnchor.constraint(equalTo: footer.topAnchor),

            closeButton.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
            closeButton.topAnchor.constraint(equalTo: footer.topAnchor),

            helperLabel.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            helperLabel.topAnchor.constraint(equalTo: quitButton.bottomAnchor, constant: 6),
            helperLabel.bottomAnchor.constraint(equalTo: footer.bottomAnchor)
        ])

        return footer
    }

    // MARK: - Public API

    func show() {
        guard let window = window else { return }
        updateUI()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        logger.info("MainWindowController displayed")
    }

    func updateUI() {
        let settings = SettingsManager.shared

        // Shortcut
        shortcutBadgeLabel?.stringValue = settings.shortcutDisplay

        // Preset
        let currentPresetId = settings.currentPresetId
        if let currentPresetId = currentPresetId,
           let preset = ShortcutPreset(rawValue: currentPresetId) {
            presetPopUp?.selectItem(withTitle: preset.displayName)
        } else {
            presetPopUp?.selectItem(withTitle: "Custom...")
        }

        // Toggles
        soundCheckbox?.state = settings.isSoundEnabled ? .on : .off
        hudCheckbox?.state = settings.isHUDEnabled ? .on : .off

        // Theme
        let currentTheme = settings.currentTheme
        themePopUp?.selectItem(withTitle: currentTheme.displayName)

        // Login
        launchAtLoginCheckbox?.state = settings.isLaunchAtLoginEnabled ? .on : .off
    }

    // MARK: - Actions

    @objc private func handleForceQuitAction() {
        // Hide window so the previous application becomes frontmost, then terminate it
        window?.orderOut(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            KillManager.shared.forceQuitFrontmostApp()
        }
    }

    @objc private func handleTestFeedback() {
        HUDController.shared.show(
            appName: "SuperQ Test",
            appIcon: NSApp.applicationIconImage,
            pid: ProcessInfo.processInfo.processIdentifier
        )
    }

    @objc private func handlePresetChanged(_ sender: NSPopUpButton) {
        if let preset = sender.selectedItem?.representedObject as? ShortcutPreset {
            SettingsManager.shared.applyPreset(preset)
            HotKeyManager.shared.updateRegistration()
            updateUI()
            notifyMenuChanged()
        } else if (sender.selectedItem?.representedObject as? String) == "custom" {
            openRecorder()
        }
    }

    @objc private func openRecorder() {
        ShortcutRecorderWindowController.shared.show()
        ShortcutRecorderWindowController.shared.onShortcutSaved = { [weak self] in
            self?.updateUI()
            self?.notifyMenuChanged()
        }
    }

    @objc private func resetShortcut() {
        SettingsManager.shared.resetToDefaultShortcut()
        HotKeyManager.shared.updateRegistration()
        updateUI()
        notifyMenuChanged()
    }

    @objc private func handleSoundToggled(_ sender: NSButton) {
        SettingsManager.shared.isSoundEnabled = (sender.state == .on)
        notifyMenuChanged()
    }

    @objc private func handleHUDToggled(_ sender: NSButton) {
        SettingsManager.shared.isHUDEnabled = (sender.state == .on)
        notifyMenuChanged()
    }

    @objc private func handleThemeChanged(_ sender: NSPopUpButton) {
        if let theme = sender.selectedItem?.representedObject as? HUDTheme {
            SettingsManager.shared.currentTheme = theme
            notifyMenuChanged()
        }
    }

    @objc private func handleLaunchAtLoginToggled(_ sender: NSButton) {
        let enable = (sender.state == .on)
        let success = SettingsManager.shared.setLaunchAtLogin(enabled: enable)
        if !success {
            sender.state = SettingsManager.shared.isLaunchAtLoginEnabled ? .on : .off
        }
        notifyMenuChanged()
    }

    @objc private func handleQuitApp() {
        HotKeyManager.shared.unregister()
        NSApp.terminate(nil)
    }

    @objc private func handleCloseWindow() {
        window?.close()
    }

    private func notifyMenuChanged() {
        NotificationCenter.default.post(name: NSNotification.Name("SuperQSettingsChanged"), object: nil)
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false // Don't release, just hide
    }
}
