import Foundation
import ServiceManagement
import Carbon
import os

enum ShortcutPreset: String, CaseIterable, Identifiable {
    case shiftCmdQ = "shift_cmd_q"
    case optCmdQ = "opt_cmd_q"
    case ctrlCmdQ = "ctrl_cmd_q"
    case ctrlOptCmdQ = "ctrl_opt_cmd_q"
    case ctrlShiftCmdQ = "ctrl_shift_cmd_q"
    case optShiftCmdQ = "opt_shift_cmd_q"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .shiftCmdQ:
            return "⇧⌘Q (Shift + Cmd + Q) [Default]"
        case .optCmdQ:
            return "⌥⌘Q (Option + Cmd + Q)"
        case .ctrlCmdQ:
            return "⌃⌘Q (Control + Cmd + Q)"
        case .ctrlOptCmdQ:
            return "⌃⌥⌘Q (Ctrl + Opt + Cmd + Q)"
        case .ctrlShiftCmdQ:
            return "⌃⇧⌘Q (Ctrl + Shift + Cmd + Q)"
        case .optShiftCmdQ:
            return "⌥⇧⌘Q (Opt + Shift + Cmd + Q)"
        }
    }

    var shortDisplay: String {
        switch self {
        case .shiftCmdQ: return "⇧⌘Q"
        case .optCmdQ: return "⌥⌘Q"
        case .ctrlCmdQ: return "⌃⌘Q"
        case .ctrlOptCmdQ: return "⌃⌥⌘Q"
        case .ctrlShiftCmdQ: return "⌃⇧⌘Q"
        case .optShiftCmdQ: return "⌥⇧⌘Q"
        }
    }

    var carbonModifiers: UInt32 {
        let cmd = UInt32(cmdKey)
        let shift = UInt32(shiftKey)
        let opt = UInt32(optionKey)
        let ctrl = UInt32(controlKey)

        switch self {
        case .shiftCmdQ: return cmd | shift
        case .optCmdQ: return cmd | opt
        case .ctrlCmdQ: return cmd | ctrl
        case .ctrlOptCmdQ: return cmd | ctrl | opt
        case .ctrlShiftCmdQ: return cmd | ctrl | shift
        case .optShiftCmdQ: return cmd | opt | shift
        }
    }

    var keyCode: UInt32 {
        return 12 // kVK_ANSI_Q
    }
}

final class SettingsManager {
    static let shared = SettingsManager()
    private let defaults = UserDefaults.standard
    private let logger = Logger(subsystem: "com.antigravity.superq", category: "Settings")

    private let keySoundEnabled = "superq_sound_enabled"
    private let keyHUDEnabled = "superq_hud_enabled"
    private let keyShortcutKeyCode = "superq_shortcut_keycode"
    private let keyShortcutCarbonModifiers = "superq_shortcut_modifiers"
    private let keyShortcutDisplay = "superq_shortcut_display"
    private let keyShortcutPresetId = "superq_shortcut_preset_id"

    private init() {
        defaults.register(defaults: [
            keySoundEnabled: true,
            keyHUDEnabled: true,
            keyShortcutKeyCode: 12,
            keyShortcutCarbonModifiers: UInt32(cmdKey | shiftKey),
            keyShortcutDisplay: "⇧⌘Q",
            keyShortcutPresetId: ShortcutPreset.shiftCmdQ.rawValue
        ])
    }

    var isSoundEnabled: Bool {
        get { defaults.bool(forKey: keySoundEnabled) }
        set { defaults.set(newValue, forKey: keySoundEnabled) }
    }

    var isHUDEnabled: Bool {
        get { defaults.bool(forKey: keyHUDEnabled) }
        set { defaults.set(newValue, forKey: keyHUDEnabled) }
    }

    var shortcutKeyCode: UInt32 {
        get { UInt32(defaults.integer(forKey: keyShortcutKeyCode)) }
        set { defaults.set(Int(newValue), forKey: keyShortcutKeyCode) }
    }

    var shortcutCarbonModifiers: UInt32 {
        get { UInt32(defaults.integer(forKey: keyShortcutCarbonModifiers)) }
        set { defaults.set(Int(newValue), forKey: keyShortcutCarbonModifiers) }
    }

    var shortcutDisplay: String {
        get { defaults.string(forKey: keyShortcutDisplay) ?? "⇧⌘Q" }
        set { defaults.set(newValue, forKey: keyShortcutDisplay) }
    }

    var currentPresetId: String? {
        get { defaults.string(forKey: keyShortcutPresetId) }
        set { defaults.set(newValue, forKey: keyShortcutPresetId) }
    }

    func applyPreset(_ preset: ShortcutPreset) {
        shortcutKeyCode = preset.keyCode
        shortcutCarbonModifiers = preset.carbonModifiers
        shortcutDisplay = preset.shortDisplay
        currentPresetId = preset.rawValue
        logger.info("Applied shortcut preset: \(preset.shortDisplay)")
    }

    func setCustomShortcut(keyCode: UInt32, carbonModifiers: UInt32, display: String) {
        shortcutKeyCode = keyCode
        shortcutCarbonModifiers = carbonModifiers
        shortcutDisplay = display
        currentPresetId = "custom"
        logger.info("Set custom shortcut: \(display) (code: \(keyCode), mods: \(carbonModifiers))")
    }

    func resetToDefaultShortcut() {
        applyPreset(.shiftCmdQ)
    }

    var isLaunchAtLoginEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    func setLaunchAtLogin(enabled: Bool) -> Bool {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                    logger.info("Registered launch at login")
                } else {
                    try SMAppService.mainApp.unregister()
                    logger.info("Unregistered launch at login")
                }
                return true
            } catch {
                logger.error("Failed to update launch at login: \(error.localizedDescription)")
                return false
            }
        }
        return false
    }
}
