import Cocoa
import os

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let logger = Logger(subsystem: "com.antigravity.superq", category: "AppDelegate")

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as menu bar only agent (no Dock icon)
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()

        HotKeyManager.shared.onHotKeyTriggered = {
            KillManager.shared.forceQuitFrontmostApp()
        }
        HotKeyManager.shared.updateRegistration()

        ShortcutRecorderWindowController.shared.onShortcutSaved = { [weak self] in
            self?.buildMenu()
        }

        logger.info("SuperQ ready.")
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.title = "Q"
            button.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        }

        buildMenu()
    }

    private func buildMenu() {
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

        menu.addItem(NSMenuItem.separator())

        // 2. Shortcut Submenu
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

        // 3. Play Sound toggle
        let soundItem = NSMenuItem(
            title: "Play Sound",
            action: #selector(toggleSound),
            keyEquivalent: ""
        )
        soundItem.target = self
        soundItem.state = SettingsManager.shared.isSoundEnabled ? .on : .off
        menu.addItem(soundItem)

        // 4. Show Pop-up / HUD toggle
        let hudItem = NSMenuItem(
            title: "Show Pop-up",
            action: #selector(toggleHUD),
            keyEquivalent: ""
        )
        hudItem.target = self
        hudItem.state = SettingsManager.shared.isHUDEnabled ? .on : .off
        menu.addItem(hudItem)

        // 5. Launch at Login
        let loginItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        loginItem.target = self
        loginItem.state = SettingsManager.shared.isLaunchAtLoginEnabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(NSMenuItem.separator())

        // 6. Quit SuperQ
        let quitItem = NSMenuItem(
            title: "Quit SuperQ",
            action: #selector(quitApp),
            keyEquivalent: ""
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func handleForceQuit() {
        KillManager.shared.forceQuitFrontmostApp()
    }

    @objc private func handleSelectPreset(_ sender: NSMenuItem) {
        guard let preset = sender.representedObject as? ShortcutPreset else { return }
        SettingsManager.shared.applyPreset(preset)
        HotKeyManager.shared.updateRegistration()
        buildMenu()
    }

    @objc private func openShortcutRecorder() {
        ShortcutRecorderWindowController.shared.show()
    }

    @objc private func handleResetShortcut() {
        SettingsManager.shared.resetToDefaultShortcut()
        HotKeyManager.shared.updateRegistration()
        buildMenu()
    }

    @objc private func toggleSound() {
        SettingsManager.shared.isSoundEnabled.toggle()
        buildMenu()
    }

    @objc private func toggleHUD() {
        SettingsManager.shared.isHUDEnabled.toggle()
        buildMenu()
    }

    @objc private func toggleLaunchAtLogin() {
        let current = SettingsManager.shared.isLaunchAtLoginEnabled
        _ = SettingsManager.shared.setLaunchAtLogin(enabled: !current)
        buildMenu()
    }

    @objc private func quitApp() {
        HotKeyManager.shared.unregister()
        NSApp.terminate(nil)
    }
}
