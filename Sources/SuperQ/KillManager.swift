import Cocoa
import CoreGraphics
import Darwin
import os

struct TargetProcessInfo {
    let pid: pid_t
    let name: String
    let icon: NSImage?
    let bundleURL: URL?
    let bundleIdentifier: String?
}

final class KillManager {
    static let shared = KillManager()
    private let logger = Logger(subsystem: "com.antigravity.superq", category: "KillManager")

    private init() {}

    @discardableResult
    func forceQuitFrontmostApp() -> Bool {
        guard let target = resolveFrontmostTarget() else {
            logger.notice("No active program or frontmost application found")
            return false
        }

        return forceQuitTarget(target)
    }

    @discardableResult
    func forceQuitApp(_ app: NSRunningApplication) -> Bool {
        let currentPid = ProcessInfo.processInfo.processIdentifier
        let targetPid = app.processIdentifier

        if targetPid == currentPid {
            logger.notice("Ignored attempt to kill SuperQ itself")
            return false
        }

        if app.isTerminated {
            logger.notice("Target application is already terminated: PID \(targetPid)")
            return false
        }

        let target = TargetProcessInfo(
            pid: targetPid,
            name: app.localizedName ?? "Application",
            icon: app.icon,
            bundleURL: app.bundleURL,
            bundleIdentifier: app.bundleIdentifier
        )

        return forceQuitTarget(target)
    }

    @discardableResult
    func forceQuitPID(_ pid: pid_t) -> Bool {
        let currentPid = ProcessInfo.processInfo.processIdentifier
        if pid == currentPid || pid <= 1 {
            return false
        }

        guard let target = makeTargetInfo(pid: pid, fallbackName: "Process (PID: \(pid))") else {
            return false
        }

        return forceQuitTarget(target)
    }

    // MARK: - Core Multi-Process Force Quit

    private func forceQuitTarget(_ target: TargetProcessInfo) -> Bool {
        let currentPid = ProcessInfo.processInfo.processIdentifier
        if target.pid == currentPid || target.pid <= 1 {
            return false
        }

        // Collect target PID and all associated background/child/bundle processes
        let pidsToKill = findRelatedProcesses(
            for: target.pid,
            bundleURL: target.bundleURL,
            bundleIdentifier: target.bundleIdentifier
        )

        logger.notice("Force quitting: \(target.name) (PID: \(target.pid)) and \(pidsToKill.count) total processes: \(Array(pidsToKill))")

        // 1. Direct POSIX SIGKILL kernel termination to all resolved processes
        for pid in pidsToKill {
            kill(pid, SIGKILL)
            if let runningApp = NSRunningApplication(processIdentifier: pid) {
                runningApp.forceTerminate()
            }
        }

        // 2. Terminate entire process group if target was group leader
        var bsdInfo = proc_bsdinfo()
        let size = proc_pidinfo(target.pid, PROC_PIDTBSDINFO, 0, &bsdInfo, Int32(MemoryLayout<proc_bsdinfo>.size))
        if size == MemoryLayout<proc_bsdinfo>.size {
            let pgid = pid_t(bsdInfo.pbi_pgid)
            if pgid == target.pid && pgid > 1 {
                kill(-pgid, SIGKILL)
            }
        }

        // 3. Audio feedback
        if SettingsManager.shared.isSoundEnabled {
            playKillSound()
        }

        // 4. Visual HUD feedback
        if SettingsManager.shared.isHUDEnabled {
            DispatchQueue.main.async {
                HUDController.shared.show(
                    appName: target.name,
                    appIcon: target.icon,
                    pid: target.pid,
                    killedCount: pidsToKill.count
                )
            }
        }

        return true
    }

    // MARK: - Frontmost / Full-Screen Target Resolution

    private func resolveFrontmostTarget() -> TargetProcessInfo? {
        let myPid = ProcessInfo.processInfo.processIdentifier

        let ignoredOwners: Set<String> = [
            "Window Server", "WindowServer", "Dock", "Control Center", "ControlCenter",
            "Notification Center", "NotificationCenter", "Spotlight", "SystemUIServer",
            "loginwindow", "ScreenSaverEngine", "Wallpaper", "screencapture",
            "universalAccessAuthWarn", "SuperQ"
        ]

        // 1. CoreGraphics On-Screen Window List (inspects true frontmost window in Z-order)
        // Works for full screen games, Metal/OpenGL exclusive modes, SDL2, Wine, emulators
        if let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[CFString: Any]] {
            for w in infoList {
                guard let pid = w[kCGWindowOwnerPID] as? pid_t,
                      let owner = w[kCGWindowOwnerName] as? String,
                      let layer = w[kCGWindowLayer] as? Int,
                      let boundsDict = w[kCGWindowBounds] as? [CFString: Any],
                      let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
                    continue
                }
                let alpha = w[kCGWindowAlpha] as? Double ?? 1.0

                if pid == myPid || ignoredOwners.contains(owner) { continue }
                if layer < 0 { continue }
                if alpha < 0.05 { continue }
                if bounds.width < 80 || bounds.height < 80 { continue }

                // Found top visible application/game window
                if let target = makeTargetInfo(pid: pid, fallbackName: owner) {
                    logger.notice("Found on-screen window target: \(target.name) (PID: \(target.pid), layer: \(layer))")
                    return target
                }
            }
        }

        // 2. Accessibility Focused Application
        let systemWide = AXUIElementCreateSystemWide()
        var focusedAppValue: AnyObject?
        if AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focusedAppValue) == .success,
           let focusedApp = focusedAppValue {
            var axPid: pid_t = 0
            if AXUIElementGetPid(focusedApp as! AXUIElement, &axPid) == .success, axPid != myPid && axPid > 1 {
                if let target = makeTargetInfo(pid: axPid, fallbackName: "Focused Application") {
                    logger.notice("Found AX focused target: \(target.name) (PID: \(target.pid))")
                    return target
                }
            }
        }

        // 3. NSWorkspace frontmost application
        if let frontApp = NSWorkspace.shared.frontmostApplication, frontApp.processIdentifier != myPid {
            return makeTargetInfo(pid: frontApp.processIdentifier, fallbackName: frontApp.localizedName ?? "Application")
        }

        // 4. NSWorkspace menuBarOwningApplication
        if let menuApp = NSWorkspace.shared.menuBarOwningApplication, menuApp.processIdentifier != myPid {
            return makeTargetInfo(pid: menuApp.processIdentifier, fallbackName: menuApp.localizedName ?? "Application")
        }

        return nil
    }

    private func makeTargetInfo(pid: pid_t, fallbackName: String) -> TargetProcessInfo? {
        let myPid = ProcessInfo.processInfo.processIdentifier
        if pid <= 1 || pid == myPid { return nil }

        if let app = NSRunningApplication(processIdentifier: pid) {
            return TargetProcessInfo(
                pid: pid,
                name: app.localizedName ?? fallbackName,
                icon: app.icon,
                bundleURL: app.bundleURL,
                bundleIdentifier: app.bundleIdentifier
            )
        }

        let execPath = getProcessPath(pid: pid)
        var bundleURL: URL? = nil
        var icon: NSImage? = nil

        if let path = execPath {
            if let bundlePath = extractBundlePath(from: path) {
                bundleURL = URL(fileURLWithPath: bundlePath)
                if let bundle = Bundle(url: bundleURL!) {
                    let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                        ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                    if let n = name, !n.isEmpty {
                        return TargetProcessInfo(
                            pid: pid,
                            name: n,
                            icon: NSWorkspace.shared.icon(forFile: bundlePath),
                            bundleURL: bundleURL,
                            bundleIdentifier: bundle.bundleIdentifier
                        )
                    }
                }
                icon = NSWorkspace.shared.icon(forFile: bundlePath)
            } else {
                icon = NSWorkspace.shared.icon(forFile: path)
            }
        }

        let name = execPath.map { ($0 as NSString).lastPathComponent } ?? fallbackName
        return TargetProcessInfo(
            pid: pid,
            name: name,
            icon: icon,
            bundleURL: bundleURL,
            bundleIdentifier: nil
        )
    }

    // MARK: - Related & Background Process Discovery

    private func findRelatedProcesses(for targetPid: pid_t, bundleURL: URL?, bundleIdentifier: String?) -> Set<pid_t> {
        let myPid = ProcessInfo.processInfo.processIdentifier
        let myPpid = getppid()

        let allPids = getAllPids()
        var childrenMap: [pid_t: [pid_t]] = [:]
        var parentMap: [pid_t: pid_t] = [:]
        var pidToPath: [pid_t: String] = [:]
        var pidToPgid: [pid_t: pid_t] = [:]

        for p in allPids {
            if let info = getBsdInfo(pid: p) {
                let ppid = pid_t(info.pbi_ppid)
                let pgid = pid_t(info.pbi_pgid)
                childrenMap[ppid, default: []].append(p)
                parentMap[p] = ppid
                pidToPgid[p] = pgid
            }
            if let path = getProcessPath(pid: p) {
                pidToPath[p] = path
            }
        }

        var resolvedPids: Set<pid_t> = [targetPid]

        // 1. Determine app bundle path
        var bundlePath = bundleURL?.path
        if bundlePath == nil, let execPath = pidToPath[targetPid] {
            bundlePath = extractBundlePath(from: execPath)
        }

        // 2. Check if target process has a parent inside the same app bundle / directory
        if let ppid = parentMap[targetPid], ppid > 1 {
            if let bp = bundlePath, let parentPath = pidToPath[ppid], parentPath.hasPrefix(bp) {
                resolvedPids.insert(ppid)
            }
        }

        // 3. Collect all descendant processes (children, grandchildren, etc.)
        var queue = Array(resolvedPids)
        while !queue.isEmpty {
            let current = queue.removeFirst()
            if let children = childrenMap[current] {
                for child in children {
                    if !resolvedPids.contains(child) {
                        resolvedPids.insert(child)
                        queue.append(child)
                    }
                }
            }
        }

        // 4. Collect all processes executing from inside the same app bundle directory
        if let bp = bundlePath {
            for (p, path) in pidToPath {
                if path.hasPrefix(bp + "/") || path == bp {
                    resolvedPids.insert(p)
                }
            }
        }

        // 5. Collect all processes matching bundleIdentifier
        if let bid = bundleIdentifier, !bid.isEmpty {
            let matchingApps = NSRunningApplication.runningApplications(withBundleIdentifier: bid)
            for app in matchingApps {
                resolvedPids.insert(app.processIdentifier)
            }
        }

        // 6. Collect processes in same process group if target was group leader
        if let targetPgid = pidToPgid[targetPid], targetPgid == targetPid, targetPgid > 1 {
            for (p, pgid) in pidToPgid {
                if pgid == targetPgid {
                    resolvedPids.insert(p)
                }
            }
        }

        // 7. Safety filter against system and self
        let ignoredNames: Set<String> = [
            "kernel_task", "launchd", "WindowServer", "Window Server",
            "loginwindow", "Dock", "SystemUIServer", "SuperQ"
        ]

        var finalPids: Set<pid_t> = []
        for p in resolvedPids {
            if p <= 1 || p == myPid || p == myPpid { continue }
            if let path = pidToPath[p] {
                let name = (path as NSString).lastPathComponent
                if ignoredNames.contains(name) { continue }
            }
            finalPids.insert(p)
        }

        return finalPids
    }

    // MARK: - Process Helpers

    private func getProcessPath(pid: pid_t) -> String? {
        var pathBuffer = [CChar](repeating: 0, count: 4096)
        let ret = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
        if ret > 0 {
            return String(cString: pathBuffer)
        }
        return nil
    }

    private func getBsdInfo(pid: pid_t) -> proc_bsdinfo? {
        var bsdInfo = proc_bsdinfo()
        let size = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsdInfo, Int32(MemoryLayout<proc_bsdinfo>.size))
        if size == MemoryLayout<proc_bsdinfo>.size {
            return bsdInfo
        }
        return nil
    }

    private func getAllPids() -> [pid_t] {
        let maxPids = 8192
        var pids = [pid_t](repeating: 0, count: maxPids)
        let bytesUsed = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(MemoryLayout<pid_t>.stride * maxPids))
        let count = Int(bytesUsed) / MemoryLayout<pid_t>.stride
        return Array(pids.prefix(count)).filter { $0 > 1 }
    }

    private func extractBundlePath(from executablePath: String) -> String? {
        if let range = executablePath.range(of: ".app", options: .backwards) {
            let bundleEndIndex = range.upperBound
            return String(executablePath[..<bundleEndIndex])
        }
        return nil
    }

    // MARK: - Audio Feedback

    private func playKillSound() {
        if SettingsManager.shared.currentTheme.isWindows {
            playWindowsChime()
        } else {
            playModernSound()
        }
    }

    private var activeSound: NSSound?

    private func playWindowsChime() {
        let candidatePaths = [
            Bundle.main.path(forResource: "windows-2000-chimes", ofType: "mp3"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/windows-2000-chimes.mp3").path,
            "Resources/windows-2000-chimes.mp3",
            "/Users/mmtechstore/Downloads/windows-2000-chimes.mp3"
        ].compactMap { $0 }

        for path in candidatePaths where FileManager.default.fileExists(atPath: path) {
            if let sound = NSSound(contentsOfFile: path, byReference: true) {
                sound.volume = 0.35
                activeSound = sound
                sound.play()
                return
            } else {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
                task.arguments = ["-v", "0.35", path]
                try? task.run()
                return
            }
        }

        playModernSound()
    }

    private func playModernSound() {
        if let sound = NSSound(named: "Funk") {
            sound.play()
        } else if let sound = NSSound(named: "Tink") {
            sound.play()
        } else {
            NSSound.beep()
        }
    }
}
