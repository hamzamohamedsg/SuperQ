import Cocoa
import os

final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) var shared: AppDelegate?

    private var statusItem: NSStatusItem!
    private let logger = Logger(subsystem: "com.antigravity.superq", category: "AppDelegate")

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self

        // If an instance of SuperQ is already running, tell it to show the window and exit this duplicate process
        let myPid = ProcessInfo.processInfo.processIdentifier
        let bundleId = Bundle.main.bundleIdentifier ?? "com.antigravity.superq"
        let runningWithBundle = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
        let others: [NSRunningApplication]
        if !runningWithBundle.isEmpty {
            others = runningWithBundle.filter { $0.processIdentifier != myPid }
        } else {
            others = NSWorkspace.shared.runningApplications.filter {
                $0.processIdentifier != myPid && ($0.localizedName == "SuperQ" || $0.bundleIdentifier == "com.antigravity.superq")
            }
        }

        if let existing = others.first {
            logger.info("Existing SuperQ instance detected (PID \(existing.processIdentifier)). Notifying to open window.")
            DistributedNotificationCenter.default().postNotificationName(
                NSNotification.Name("com.antigravity.superq.reopenWindow"),
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
            existing.activate(options: [.activateIgnoringOtherApps])
            exit(0)
        }

        // Run as menu bar only accessory app (no permanent Dock icon)
        NSApp.setActivationPolicy(.accessory)

        // Listen for distributed reopen requests from secondary launches
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleDistributedReopen),
            name: NSNotification.Name("com.antigravity.superq.reopenWindow"),
            object: nil
        )

        // Listen for settings changed from the window
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSettingsChanged),
            name: NSNotification.Name("SuperQSettingsChanged"),
            object: nil
        )

        setupStatusItem()

        HotKeyManager.shared.onHotKeyTriggered = {
            KillManager.shared.forceQuitFrontmostApp()
        }
        HotKeyManager.shared.updateRegistration()

        ShortcutRecorderWindowController.shared.onShortcutSaved = { [weak self] in
            self?.buildMenu()
            MainWindowController.shared.updateUI()
        }

        logger.info("SuperQ ready. Running in menu bar.")
    }

    // MARK: - Reopen Handling (Open app while already running)

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        logger.info("applicationShouldHandleReopen triggered - opening SuperQ window")
        openMainWindow()
        return true
    }

    @objc private func handleDistributedReopen() {
        DispatchQueue.main.async { [weak self] in
            self?.openMainWindow()
        }
    }

    @objc func openMainWindow() {
        MainWindowController.shared.show()
    }

    @objc private func handleSettingsChanged() {
        buildMenu()
        MainWindowController.shared.updateUI()
    }

    // MARK: - Status Bar Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.title = "Q"
            button.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        }

        buildMenu()
    }

    func buildMenu() {
        let currentShortcut = SettingsManager.shared.shortcutDisplay
        if let button = statusItem?.button {
            button.toolTip = "SuperQ (\(currentShortcut) to Force Quit)"
        }

        let menu = NSMenu()

        // 1. Force Quit Active App (Action)
        let forceQuitItem = NSMenuItem(
            title: "Force Quit Active App",
            action: #selector(handleForceQuit),
            keyEquivalent: ""
        )
        forceQuitItem.target = self
        menu.addItem(forceQuitItem)

        // 2. Open SuperQ Window (for users who prefer a window over the menu bar)
        let openWindowItem = NSMenuItem(
            title: "Open SuperQ Window...",
            action: #selector(openMainWindow),
            keyEquivalent: "o"
        )
        openWindowItem.target = self
        menu.addItem(openWindowItem)

        menu.addItem(NSMenuItem.separator())

        // 3. Shortcut Submenu
        let shortcutMenu = NSMenu()
        let currentPresetId = SettingsManager.shared.currentPresetId

        for preset in ShortcutPreset.allCases {
            let item = NSMenuItem(
                title: preset.displayName,
                action: #selector(handleSelectPreset(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = preset
            item.state = (preset.rawValue == currentPresetId) ? .on : .off
            shortcutMenu.addItem(item)
        }

        shortcutMenu.addItem(NSMenuItem.separator())

        let customItem = NSMenuItem(
            title: currentPresetId == "custom" ? "Custom (\(currentShortcut))" : "Custom Shortcut...",
            action: #selector(openShortcutRecorder),
            keyEquivalent: ""
        )
        customItem.target = self
        if currentPresetId == "custom" {
            customItem.state = .on
        }
        shortcutMenu.addItem(customItem)

        let resetItem = NSMenuItem(
            title: "Reset to Default (⇧⌘Q)",
            action: #selector(handleResetShortcut),
            keyEquivalent: ""
        )
        resetItem.target = self
        shortcutMenu.addItem(resetItem)

        let shortcutParentItem = NSMenuItem(title: "Shortcut (\(currentShortcut))", action: nil, keyEquivalent: "")
        shortcutParentItem.submenu = shortcutMenu
        menu.addItem(shortcutParentItem)

        menu.addItem(NSMenuItem.separator())

        // 4. Play Sound toggle
        let soundItem = NSMenuItem(
            title: "Play Sound",
            action: #selector(toggleSound),
            keyEquivalent: ""
        )
        soundItem.target = self
        soundItem.state = SettingsManager.shared.isSoundEnabled ? .on : .off
        menu.addItem(soundItem)

        // 5. Show Pop-up / HUD toggle
        let hudItem = NSMenuItem(
            title: "Show Pop-up",
            action: #selector(toggleHUD),
            keyEquivalent: ""
        )
        hudItem.target = self
        hudItem.state = SettingsManager.shared.isHUDEnabled ? .on : .off
        menu.addItem(hudItem)

        // 5b. Theme Submenu
        let themeMenu = NSMenu()
        let currentTheme = SettingsManager.shared.currentTheme
        let lightTheme = SettingsManager.shared.lightTheme
        let darkTheme = SettingsManager.shared.darkTheme
        let isDark = SettingsManager.shared.isSystemInDarkMode

        let activeItem = NSMenuItem(title: "Active: \(currentTheme.displayName) (\(isDark ? "Dark Mode" : "Light Mode"))", action: nil, keyEquivalent: "")
        activeItem.isEnabled = false
        themeMenu.addItem(activeItem)
        themeMenu.addItem(NSMenuItem.separator())

        let lightHeader = NSMenuItem(title: "Light Theme:", action: nil, keyEquivalent: "")
        lightHeader.isEnabled = false
        themeMenu.addItem(lightHeader)

        for theme in HUDTheme.allCases {
            let item = NSMenuItem(
                title: "   " + theme.displayName,
                action: #selector(handleSelectLightTheme(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = theme
            item.state = (theme == lightTheme) ? .on : .off
            themeMenu.addItem(item)
        }

        themeMenu.addItem(NSMenuItem.separator())

        let darkHeader = NSMenuItem(title: "Dark Theme:", action: nil, keyEquivalent: "")
        darkHeader.isEnabled = false
        themeMenu.addItem(darkHeader)

        for theme in HUDTheme.allCases {
            let item = NSMenuItem(
                title: "   " + theme.displayName,
                action: #selector(handleSelectDarkTheme(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = theme
            item.state = (theme == darkTheme) ? .on : .off
            themeMenu.addItem(item)
        }

        let themeParentItem = NSMenuItem(title: "Pop-up Theme (\(currentTheme.displayName))", action: nil, keyEquivalent: "")
        themeParentItem.submenu = themeMenu
        menu.addItem(themeParentItem)

        // 6. Launch at Login
        let loginItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        loginItem.target = self
        loginItem.state = SettingsManager.shared.isLaunchAtLoginEnabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(NSMenuItem.separator())

        // 7. Quit SuperQ
        let quitItem = NSMenuItem(
            title: "Quit SuperQ",
            action: #selector(quitApp),
            keyEquivalent: ""
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Actions

    @objc private func handleForceQuit() {
        KillManager.shared.forceQuitFrontmostApp()
    }

    @objc private func handleSelectPreset(_ sender: NSMenuItem) {
        guard let preset = sender.representedObject as? ShortcutPreset else { return }
        SettingsManager.shared.applyPreset(preset)
        HotKeyManager.shared.updateRegistration()
        buildMenu()
        MainWindowController.shared.updateUI()
    }

    @objc private func openShortcutRecorder() {
        ShortcutRecorderWindowController.shared.show()
    }

    @objc private func handleResetShortcut() {
        SettingsManager.shared.resetToDefaultShortcut()
        HotKeyManager.shared.updateRegistration()
        buildMenu()
        MainWindowController.shared.updateUI()
    }

    @objc private func toggleSound() {
        SettingsManager.shared.isSoundEnabled.toggle()
        buildMenu()
        MainWindowController.shared.updateUI()
    }

    @objc private func toggleHUD() {
        SettingsManager.shared.isHUDEnabled.toggle()
        buildMenu()
        MainWindowController.shared.updateUI()
    }

    @objc private func handleSelectLightTheme(_ sender: NSMenuItem) {
        guard let theme = sender.representedObject as? HUDTheme else { return }
        SettingsManager.shared.lightTheme = theme
        buildMenu()
        MainWindowController.shared.updateUI()
    }

    @objc private func handleSelectDarkTheme(_ sender: NSMenuItem) {
        guard let theme = sender.representedObject as? HUDTheme else { return }
        SettingsManager.shared.darkTheme = theme
        buildMenu()
        MainWindowController.shared.updateUI()
    }

    @objc private func toggleLaunchAtLogin() {
        let current = SettingsManager.shared.isLaunchAtLoginEnabled
        _ = SettingsManager.shared.setLaunchAtLogin(enabled: !current)
        buildMenu()
        MainWindowController.shared.updateUI()
    }

    @objc private func quitApp() {
        HotKeyManager.shared.unregister()
        NSApp.terminate(nil)
    }
}
