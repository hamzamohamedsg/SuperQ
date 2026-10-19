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
    private var globalEventMonitor: Any?
    private var accessibilityTimer: Timer?
    private var lastTriggerTime: TimeInterval = 0

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
            GetEventDispatcherTarget(),
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
            logger.info("Carbon event handler installed successfully on EventDispatcherTarget")
        }
    }

    func updateRegistration() {
        unregisterHotKey()
        unregisterEventTap()
        unregisterGlobalMonitor()

        let keyCode = SettingsManager.shared.shortcutKeyCode
        let carbonMods = SettingsManager.shared.shortcutCarbonModifiers
        let display = SettingsManager.shared.shortcutDisplay

        registerCarbonHotKey(keyCode: keyCode, carbonModifiers: carbonMods, display: display)

        if AXIsProcessTrusted() {
            accessibilityTimer?.invalidate()
            accessibilityTimer = nil
            registerEventTap(keyCode: keyCode, carbonModifiers: carbonMods)
            registerGlobalMonitor(keyCode: keyCode, carbonModifiers: carbonMods)
        } else {
            startAccessibilityMonitoring()
        }
    }

    private func registerCarbonHotKey(keyCode: UInt32, carbonModifiers: UInt32, display: String) {
        let hotKeyID = EventHotKeyID(signature: OSType(0x53505251), id: 1) // 'SPRQ'
        let status = RegisterEventHotKey(
            keyCode,
            carbonModifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )

        if status != noErr {
            logger.error("Failed to register Carbon HotKey (\(display)): \(status)")
        } else {
            logger.info("Registered Carbon HotKey (\(display)) on EventDispatcherTarget")
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
        triggerAction()
    }

    func triggerAction() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastTriggerTime > 0.35 else { return }
        lastTriggerTime = now
        logger.notice("SuperQ shortcut action triggered")
        DispatchQueue.main.async { [weak self] in
            self?.onHotKeyTriggered?()
        }
    }

    // MARK: - CGEventTap for swallowing key events & working inside full-screen games

    private func registerEventTap(keyCode targetKeyCode: UInt32, carbonModifiers targetMods: UInt32) {
        let mask = (1 << CGEventType.keyDown.rawValue)

        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passRetained(event) }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(refcon).takeUnretainedValue()

            // If system disabled the tap due to high load (e.g. 3D game rendering), immediately re-enable it
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = manager.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                return Unmanaged.passRetained(event)
            }

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
                    manager.triggerAction()
                    // Return nil to swallow event completely
                    return nil
                }
            }
            return Unmanaged.passRetained(event)
        }

        // Try HID level first (hardware driver level, intercepts before fullscreen games/apps)
        var tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        // Fallback to session level if HID level tap cannot be created
        if tap == nil {
            tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: CGEventMask(mask),
                callback: callback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
        }

        guard let validTap = tap else {
            logger.notice("Could not create CGEventTap")
            return
        }

        self.eventTap = validTap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, validTap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: validTap, enable: true)
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

    // MARK: - Global NSEvent Monitor Fallback

    private func registerGlobalMonitor(keyCode targetKeyCode: UInt32, carbonModifiers targetMods: UInt32) {
        unregisterGlobalMonitor()
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return }
            let currentMods = SettingsManager.shared.shortcutCarbonModifiers
            let currentCode = SettingsManager.shared.shortcutKeyCode

            let reqCmd = (currentMods & UInt32(cmdKey)) != 0
            let reqShift = (currentMods & UInt32(shiftKey)) != 0
            let reqOpt = (currentMods & UInt32(optionKey)) != 0
            let reqCtrl = (currentMods & UInt32(controlKey)) != 0

            let flags = event.modifierFlags
            var matches = (UInt32(event.keyCode) == currentCode)
            if flags.contains(.command) != reqCmd { matches = false }
            if flags.contains(.shift) != reqShift { matches = false }
            if flags.contains(.option) != reqOpt { matches = false }
            if flags.contains(.control) != reqCtrl { matches = false }

            if matches {
                self.logger.notice("NSEvent global monitor caught shortcut")
                self.triggerAction()
            }
        }
    }

    private func unregisterGlobalMonitor() {
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }
    }

    private func startAccessibilityMonitoring() {
        guard accessibilityTimer == nil else { return }
        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
            if AXIsProcessTrusted() {
                timer.invalidate()
                self?.accessibilityTimer = nil
                self?.logger.info("Accessibility granted! Updating registrations.")
                self?.updateRegistration()
            }
        }
    }

    func unregister() {
        accessibilityTimer?.invalidate()
        accessibilityTimer = nil
        unregisterHotKey()
        unregisterEventTap()
        unregisterGlobalMonitor()
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
    }
}
