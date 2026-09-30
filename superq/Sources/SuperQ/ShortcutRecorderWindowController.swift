import Cocoa
import Carbon

final class ShortcutRecorderWindowController: NSWindowController {
    static let shared = ShortcutRecorderWindowController()

    private var displayLabel: NSTextField!
    private var saveButton: NSButton!
    private var capturedKeyCode: UInt32?
    private var capturedCarbonModifiers: UInt32?
    private var capturedDisplayString: String?
    private var eventMonitor: Any?

    var onShortcutSaved: (() -> Void)?

    private init() {
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 210),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Change Force-Quit Shortcut"
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        guard let window = window, let contentView = window.contentView else { return }

        // Instruction label
        let instructionLabel = NSTextField(labelWithString: "Press any key combination with at least one modifier (⌘, ⌥, ⌃, or ⇧):")
        instructionLabel.frame = NSRect(x: 20, y: 140, width: 320, height: 40)
        instructionLabel.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        instructionLabel.textColor = .secondaryLabelColor
        instructionLabel.lineBreakMode = .byWordWrapping
        contentView.addSubview(instructionLabel)

        // Key display container
        let boxView = NSView(frame: NSRect(x: 20, y: 80, width: 320, height: 48))
        boxView.wantsLayer = true
        boxView.layer?.cornerRadius = 8
        boxView.layer?.borderWidth = 1.5
        boxView.layer?.borderColor = NSColor.separatorColor.cgColor
        boxView.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        displayLabel = NSTextField(labelWithString: SettingsManager.shared.shortcutDisplay)
        displayLabel.frame = NSRect(x: 0, y: 10, width: 320, height: 28)
        displayLabel.font = NSFont.systemFont(ofSize: 20, weight: .bold)
        displayLabel.alignment = .center
        displayLabel.textColor = .labelColor
        boxView.addSubview(displayLabel)
        contentView.addSubview(boxView)

        // Cancel button
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(handleCancel))
        cancelButton.frame = NSRect(x: 18, y: 18, width: 75, height: 32)
        contentView.addSubview(cancelButton)

        // Reset button
        let resetButton = NSButton(title: "Reset (⇧⌘Q)", target: self, action: #selector(handleReset))
        resetButton.frame = NSRect(x: 98, y: 18, width: 110, height: 32)
        contentView.addSubview(resetButton)

        // Save button
        saveButton = NSButton(title: "Save", target: self, action: #selector(handleSave))
        saveButton.frame = NSRect(x: 250, y: 18, width: 90, height: 32)
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r" // Enter key
        contentView.addSubview(saveButton)
    }

    func show() {
        guard let window = window else { return }

        // Load current
        capturedKeyCode = SettingsManager.shared.shortcutKeyCode
        capturedCarbonModifiers = SettingsManager.shared.shortcutCarbonModifiers
        capturedDisplayString = SettingsManager.shared.shortcutDisplay
        displayLabel.stringValue = SettingsManager.shared.shortcutDisplay

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        startMonitoringKeys()
    }

    private func startMonitoringKeys() {
        stopMonitoringKeys()

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }

            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])

            // Require at least one modifier key
            guard !flags.isEmpty else {
                return nil
            }

            // Don't capture bare Tab or Escape
            if event.keyCode == 53 { // ESC
                self.handleCancel()
                return nil
            }

            let keyCode = UInt32(event.keyCode)
            var carbonMods: UInt32 = 0
            if flags.contains(.command) { carbonMods |= UInt32(cmdKey) }
            if flags.contains(.shift) { carbonMods |= UInt32(shiftKey) }
            if flags.contains(.option) { carbonMods |= UInt32(optionKey) }
            if flags.contains(.control) { carbonMods |= UInt32(controlKey) }

            let display = self.formatDisplayString(keyCode: event.keyCode, flags: flags, characters: event.charactersIgnoringModifiers)

            self.capturedKeyCode = keyCode
            self.capturedCarbonModifiers = carbonMods
            self.capturedDisplayString = display
            self.displayLabel.stringValue = display

            return nil
        }
    }

    private func stopMonitoringKeys() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private func formatDisplayString(keyCode: UInt16, flags: NSEvent.ModifierFlags, characters: String?) -> String {
        var str = ""
        if flags.contains(.control) { str += "⌃" }
        if flags.contains(.option) { str += "⌥" }
        if flags.contains(.shift) { str += "⇧" }
        if flags.contains(.command) { str += "⌘" }

        switch keyCode {
        case 122: str += "F1"
        case 120: str += "F2"
        case 99: str += "F3"
        case 118: str += "F4"
        case 96: str += "F5"
        case 97: str += "F6"
        case 98: str += "F7"
        case 100: str += "F8"
        case 101: str += "F9"
        case 109: str += "F10"
        case 103: str += "F11"
        case 111: str += "F12"
        case 49: str += "Space"
        case 36: str += "Return"
        case 51: str += "Delete"
        default:
            if let chars = characters?.uppercased(), !chars.isEmpty {
                str += chars
            } else {
                str += "Key(\(keyCode))"
            }
        }
        return str
    }

    @objc private func handleSave() {
        stopMonitoringKeys()
        if let code = capturedKeyCode,
           let mods = capturedCarbonModifiers,
           let display = capturedDisplayString {
            SettingsManager.shared.setCustomShortcut(keyCode: code, carbonModifiers: mods, display: display)
            HotKeyManager.shared.updateRegistration()
            onShortcutSaved?()
        }
        window?.close()
    }

    @objc private func handleReset() {
        stopMonitoringKeys()
        SettingsManager.shared.resetToDefaultShortcut()
        HotKeyManager.shared.updateRegistration()
        onShortcutSaved?()
        window?.close()
    }

    @objc private func handleCancel() {
        stopMonitoringKeys()
        window?.close()
    }
}
