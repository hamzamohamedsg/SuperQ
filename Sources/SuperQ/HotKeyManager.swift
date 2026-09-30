import Cocoa
import Carbon
import os

final class HotKeyManager {
    static let shared = HotKeyManager()
    private let logger = Logger(subsystem: "com.antigravity.superq", category: "HotKeyManager")

    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var onHotKeyTriggered: (() -> Void)?

    private init() {
        installCarbonHandler()
    }

    deinit {
        unregister()
    }

    private func installCarbonHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (nextHandler, theEvent, userData) -> OSStatus in
                guard let userData = userData else { return noErr }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                manager.handleCarbonHotKeyEvent()
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        if status != noErr {
            logger.error("Failed to install Carbon event handler: \(status)")
        } else {
            logger.info("Carbon event handler installed successfully")
        }
    }

    func updateRegistration() {
        unregisterHotKey()
        unregisterEventTap()

        let keyCode = SettingsManager.shared.shortcutKeyCode
        let carbonMods = SettingsManager.shared.shortcutCarbonModifiers
        let display = SettingsManager.shared.shortcutDisplay

        registerCarbonHotKey(keyCode: keyCode, carbonModifiers: carbonMods, display: display)

        if AXIsProcessTrusted() {
            registerEventTap(keyCode: keyCode, carbonModifiers: carbonMods)
        }
    }

    private func registerCarbonHotKey(keyCode: UInt32, carbonModifiers: UInt32, display: String) {
        let hotKeyID = EventHotKeyID(signature: OSType(0x53505251), id: 1) // 'SPRQ'
        let status = RegisterEventHotKey(
            keyCode,
            carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status != noErr {
            logger.error("Failed to register Carbon HotKey (\(display)): \(status)")
        } else {
            logger.info("Registered Carbon HotKey (\(display))")
        }
    }

    private func unregisterHotKey() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    private func handleCarbonHotKeyEvent() {
        logger.notice("Carbon HotKey triggered!")
        DispatchQueue.main.async { [weak self] in
            self?.onHotKeyTriggered?()
        }
    }

    // MARK: - CGEventTap for swallowing key events when Accessibility is granted

    private func registerEventTap(keyCode targetKeyCode: UInt32, carbonModifiers targetMods: UInt32) {
        let mask = (1 << CGEventType.keyDown.rawValue)

        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passRetained(event) }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(refcon).takeUnretainedValue()

            if type == .keyDown {
                let eventKeyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
                let flags = event.flags

                let currentMods = SettingsManager.shared.shortcutCarbonModifiers
                let currentCode = SettingsManager.shared.shortcutKeyCode

                let reqCmd = (currentMods & UInt32(cmdKey)) != 0
                let reqShift = (currentMods & UInt32(shiftKey)) != 0
                let reqOpt = (currentMods & UInt32(optionKey)) != 0
                let reqCtrl = (currentMods & UInt32(controlKey)) != 0

                var matches = (eventKeyCode == currentCode)
                if flags.contains(.maskCommand) != reqCmd { matches = false }
                if flags.contains(.maskShift) != reqShift { matches = false }
                if flags.contains(.maskAlternate) != reqOpt { matches = false }
                if flags.contains(.maskControl) != reqCtrl { matches = false }

                if matches {
                    manager.logger.notice("CGEventTap intercepted and consumed shortcut!")
                    DispatchQueue.main.async {
                        manager.onHotKeyTriggered?()
                    }
                    // Return nil to swallow event completely
                    return nil
                }
            }
            return Unmanaged.passRetained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            logger.notice("Could not create CGEventTap (Accessibility permission not granted yet)")
            return
        }

        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        logger.info("CGEventTap activated successfully")
    }

    private func unregisterEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
                runLoopSource = nil
            }
            eventTap = nil
        }
    }

    func unregister() {
        unregisterHotKey()
        unregisterEventTap()
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
    }
}
