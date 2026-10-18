import Cocoa
import os

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

final class CardView: NSView {
    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.5).cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class MainWindowController: NSWindowController, NSWindowDelegate {
    static let shared = MainWindowController()
    private let logger = Logger(subsystem: "com.antigravity.superq", category: "MainWindowController")

    // UI Elements
    private var shortcutBadgeLabel: NSTextField!
    private var presetPopUp: NSPopUpButton!
    private var soundCheckbox: NSButton!
    private var hudCheckbox: NSButton!
    private var lightThemePopUp: NSPopUpButton!
    private var darkThemePopUp: NSPopUpButton!
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
        guard let window = window else { return }

        let container = FlippedView(frame: NSRect(x: 0, y: 0, width: 440, height: 540))
        window.contentView = container

        // 1. Header (y: 16, height: 50)
        let headerView = createHeaderView(frame: NSRect(x: 20, y: 16, width: 400, height: 50))
        container.addSubview(headerView)

        // 2. Action Card (y: 76, height: 76)
        let actionCard = createActionCard(frame: NSRect(x: 20, y: 76, width: 400, height: 76))
        container.addSubview(actionCard)

        // 3. Shortcut Card (y: 162, height: 122)
        let shortcutCard = createShortcutCard(frame: NSRect(x: 20, y: 162, width: 400, height: 122))
        container.addSubview(shortcutCard)

        // 4. Preferences Card (y: 294, height: 168)
        let preferencesCard = createPreferencesCard(frame: NSRect(x: 20, y: 294, width: 400, height: 168))
        container.addSubview(preferencesCard)

        // 5. Footer (y: 474, height: 54)
        createFooterView(in: container)

        updateUI()
    }

    // MARK: - View Builders

    private func createHeaderView(frame: NSRect) -> NSView {
        let view = FlippedView(frame: frame)

        // App Icon
        let iconView = NSImageView(frame: NSRect(x: 0, y: 2, width: 46, height: 46))
        iconView.imageScaling = .scaleProportionallyUpOrDown
        if let icon = NSApp.applicationIconImage {
            iconView.image = icon
        } else if let path = Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
                  let icon = NSImage(contentsOfFile: path) {
            iconView.image = icon
        } else {
            iconView.image = NSImage(systemSymbolName: "xmark.app.fill", accessibilityDescription: "SuperQ")
        }
        view.addSubview(iconView)

        // App Title
        let titleLabel = NSTextField(labelWithString: "SuperQ")
        titleLabel.frame = NSRect(x: 58, y: 2, width: 180, height: 24)
        titleLabel.font = NSFont.systemFont(ofSize: 19, weight: .bold)
        view.addSubview(titleLabel)

        // Subtitle
        let subtitleLabel = NSTextField(labelWithString: "Instant Force-Quit for macOS")
        subtitleLabel.frame = NSRect(x: 58, y: 26, width: 200, height: 16)
        subtitleLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        subtitleLabel.textColor = .secondaryLabelColor
        view.addSubview(subtitleLabel)

        // Status badge pill
        let statusBadge = FlippedView(frame: NSRect(x: 266, y: 12, width: 134, height: 26))
        statusBadge.wantsLayer = true
        statusBadge.layer?.cornerRadius = 13
        statusBadge.layer?.borderWidth = 1
        statusBadge.layer?.borderColor = NSColor.systemGreen.withAlphaComponent(0.35).cgColor
        statusBadge.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.12).cgColor

        let statusText = NSTextField(labelWithString: "● Active in Menu")
        statusText.frame = NSRect(x: 8, y: 5, width: 118, height: 16)
        statusText.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        statusText.textColor = NSColor.systemGreen
        statusBadge.addSubview(statusText)

        view.addSubview(statusBadge)
        return view
    }

    private func createActionCard(frame: NSRect) -> CardView {
        let card = CardView(frame: frame)

        let forceQuitButton = NSButton(title: "Force Quit Active App", target: self, action: #selector(handleForceQuitAction))
        forceQuitButton.frame = NSRect(x: 12, y: 12, width: 216, height: 32)
        forceQuitButton.bezelStyle = .rounded
        forceQuitButton.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        card.addSubview(forceQuitButton)

        let testButton = NSButton(title: "Test Pop-up & Audio", target: self, action: #selector(handleTestFeedback))
        testButton.frame = NSRect(x: 236, y: 12, width: 152, height: 32)
        testButton.bezelStyle = .rounded
        testButton.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        card.addSubview(testButton)

        let caption = NSTextField(labelWithString: "Terminates the foreground application immediately with kernel SIGKILL.")
        caption.frame = NSRect(x: 14, y: 50, width: 372, height: 16)
        caption.font = NSFont.systemFont(ofSize: 11)
        caption.textColor = .secondaryLabelColor
        card.addSubview(caption)

        return card
    }

    private func createShortcutCard(frame: NSRect) -> CardView {
        let card = CardView(frame: frame)

        // Section Title
        let titleLabel = NSTextField(labelWithString: "Force-Quit Global Shortcut")
        titleLabel.frame = NSRect(x: 14, y: 10, width: 372, height: 18)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        card.addSubview(titleLabel)

        // Badge Container
        let badgeBox = FlippedView(frame: NSRect(x: 14, y: 34, width: 66, height: 26))
        badgeBox.wantsLayer = true
        badgeBox.layer?.cornerRadius = 5
        badgeBox.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor

        shortcutBadgeLabel = NSTextField(labelWithString: "⇧⌘Q")
        shortcutBadgeLabel.frame = NSRect(x: 2, y: 4, width: 62, height: 18)
        shortcutBadgeLabel.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)
        shortcutBadgeLabel.textColor = .controlAccentColor
        shortcutBadgeLabel.alignment = .center
        badgeBox.addSubview(shortcutBadgeLabel)
        card.addSubview(badgeBox)

        // Preset PopUp
        presetPopUp = NSPopUpButton(frame: NSRect(x: 86, y: 34, width: 300, height: 26), pullsDown: false)
        presetPopUp.target = self
        presetPopUp.action = #selector(handlePresetChanged(_:))
        for preset in ShortcutPreset.allCases {
            presetPopUp.addItem(withTitle: preset.displayName)
            presetPopUp.lastItem?.representedObject = preset
        }
        presetPopUp.addItem(withTitle: "Custom...")
        presetPopUp.lastItem?.representedObject = "custom"
        card.addSubview(presetPopUp)

        // Custom button
        let customBtn = NSButton(title: "Record Custom Shortcut...", target: self, action: #selector(openRecorder))
        customBtn.frame = NSRect(x: 12, y: 66, width: 196, height: 28)
        customBtn.bezelStyle = .rounded
        customBtn.font = NSFont.systemFont(ofSize: 12)
        card.addSubview(customBtn)

        // Reset button
        let resetBtn = NSButton(title: "Reset to Default (⇧⌘Q)", target: self, action: #selector(resetShortcut))
        resetBtn.frame = NSRect(x: 214, y: 66, width: 174, height: 28)
        resetBtn.bezelStyle = .rounded
        resetBtn.font = NSFont.systemFont(ofSize: 12)
        card.addSubview(resetBtn)

        // Caption
        let desc = NSTextField(labelWithString: "Press this combination anywhere in macOS to instantly force quit.")
        desc.frame = NSRect(x: 14, y: 98, width: 372, height: 16)
        desc.font = NSFont.systemFont(ofSize: 11)
        desc.textColor = .secondaryLabelColor
        card.addSubview(desc)

        return card
    }

    private func createPreferencesCard(frame: NSRect) -> CardView {
        let card = CardView(frame: frame)

        let titleLabel = NSTextField(labelWithString: "Feedback & System Preferences")
        titleLabel.frame = NSRect(x: 14, y: 10, width: 372, height: 18)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        card.addSubview(titleLabel)

        // Row 1: Play Sound Checkbox
        soundCheckbox = NSButton(checkboxWithTitle: "Play sound on termination (Windows chime / modern audio)", target: self, action: #selector(handleSoundToggled(_:)))
        soundCheckbox.frame = NSRect(x: 14, y: 34, width: 372, height: 20)
        soundCheckbox.font = NSFont.systemFont(ofSize: 12)
        card.addSubview(soundCheckbox)

        // Row 2: Show HUD Checkbox
        hudCheckbox = NSButton(checkboxWithTitle: "Show visual termination pop-up / HUD", target: self, action: #selector(handleHUDToggled(_:)))
        hudCheckbox.frame = NSRect(x: 14, y: 58, width: 372, height: 20)
        hudCheckbox.font = NSFont.systemFont(ofSize: 12)
        card.addSubview(hudCheckbox)

        // Row 3: Light Theme Selector
        let lightThemeLabel = NSTextField(labelWithString: "Light theme:")
        lightThemeLabel.frame = NSRect(x: 14, y: 84, width: 96, height: 20)
        lightThemeLabel.font = NSFont.systemFont(ofSize: 12)
        card.addSubview(lightThemeLabel)

        lightThemePopUp = NSPopUpButton(frame: NSRect(x: 112, y: 82, width: 274, height: 24), pullsDown: false)
        lightThemePopUp.target = self
        lightThemePopUp.action = #selector(handleLightThemeChanged(_:))
        for theme in HUDTheme.allCases {
            lightThemePopUp.addItem(withTitle: theme.displayName)
            lightThemePopUp.lastItem?.representedObject = theme
        }
        card.addSubview(lightThemePopUp)

        // Row 4: Dark Theme Selector
        let darkThemeLabel = NSTextField(labelWithString: "Dark theme:")
        darkThemeLabel.frame = NSRect(x: 14, y: 112, width: 96, height: 20)
        darkThemeLabel.font = NSFont.systemFont(ofSize: 12)
        card.addSubview(darkThemeLabel)

        darkThemePopUp = NSPopUpButton(frame: NSRect(x: 112, y: 110, width: 274, height: 24), pullsDown: false)
        darkThemePopUp.target = self
        darkThemePopUp.action = #selector(handleDarkThemeChanged(_:))
        for theme in HUDTheme.allCases {
            darkThemePopUp.addItem(withTitle: theme.displayName)
            darkThemePopUp.lastItem?.representedObject = theme
        }
        card.addSubview(darkThemePopUp)

        // Row 5: Launch at Login Checkbox
        launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch SuperQ automatically at login", target: self, action: #selector(handleLaunchAtLoginToggled(_:)))
        launchAtLoginCheckbox.frame = NSRect(x: 14, y: 140, width: 372, height: 20)
        launchAtLoginCheckbox.font = NSFont.systemFont(ofSize: 12)
        card.addSubview(launchAtLoginCheckbox)

        return card
    }

    private func createFooterView(in container: NSView) {
        let quitButton = NSButton(title: "Quit SuperQ", target: self, action: #selector(handleQuitApp))
        quitButton.frame = NSRect(x: 20, y: 474, width: 115, height: 32)
        quitButton.bezelStyle = .rounded
        container.addSubview(quitButton)

        let closeButton = NSButton(title: "Close Window", target: self, action: #selector(handleCloseWindow))
        closeButton.frame = NSRect(x: 305, y: 474, width: 115, height: 32)
        closeButton.bezelStyle = .rounded
        closeButton.keyEquivalent = "\u{1b}" // Escape key
        container.addSubview(closeButton)

        let helperLabel = NSTextField(labelWithString: "SuperQ remains active in the menu bar when this window is closed.")
        helperLabel.frame = NSRect(x: 20, y: 512, width: 400, height: 16)
        helperLabel.font = NSFont.systemFont(ofSize: 10)
        helperLabel.textColor = .secondaryLabelColor
        helperLabel.alignment = .center
        container.addSubview(helperLabel)
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
        lightThemePopUp?.selectItem(withTitle: settings.lightTheme.displayName)
        darkThemePopUp?.selectItem(withTitle: settings.darkTheme.displayName)

        // Login
        launchAtLoginCheckbox?.state = settings.isLaunchAtLoginEnabled ? .on : .off
    }

    // MARK: - Actions

    @objc private func handleForceQuitAction() {
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

    @objc private func handleLightThemeChanged(_ sender: NSPopUpButton) {
        if let theme = sender.selectedItem?.representedObject as? HUDTheme {
            SettingsManager.shared.lightTheme = theme
            notifyMenuChanged()
        }
    }

    @objc private func handleDarkThemeChanged(_ sender: NSPopUpButton) {
        if let theme = sender.selectedItem?.representedObject as? HUDTheme {
            SettingsManager.shared.darkTheme = theme
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
