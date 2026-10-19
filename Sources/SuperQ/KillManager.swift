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

        // 2. Terminate entire process group if valid non-system group
        var bsdInfo = proc_bsdinfo()
        let size = proc_pidinfo(target.pid, PROC_PIDTBSDINFO, 0, &bsdInfo, Int32(MemoryLayout<proc_bsdinfo>.size))
        if size == MemoryLayout<proc_bsdinfo>.size {
            let pgid = pid_t(bsdInfo.pbi_pgid)
            if pgid > 1 && pgid != currentPid && pgid != getppid() {
                var leaderPath = [CChar](repeating: 0, count: 4096)
                let ret = proc_pidpath(pgid, &leaderPath, UInt32(leaderPath.count))
                let leaderName = ret > 0 ? (String(cString: leaderPath) as NSString).lastPathComponent : ""
                if !launcherOrSystemProcesses.contains(leaderName) {
                    kill(-pgid, SIGKILL)
                }
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

    private let overlayOwners: Set<String> = [
        "Steam Helper", "steam_osx", "gameoverlayrenderer",
        "Discord Overlay", "GeForceNOW", "OriginThinSetupInternal"
    ]

    private func resolveFrontmostTarget() -> TargetProcessInfo? {
        let myPid = ProcessInfo.processInfo.processIdentifier

        let ignoredOwners: Set<String> = [
            "Window Server", "WindowServer", "Dock", "Control Center", "ControlCenter",
            "Notification Center", "NotificationCenter", "Spotlight", "SystemUIServer",
            "loginwindow", "ScreenSaverEngine", "Wallpaper", "screencapture",
            "universalAccessAuthWarn", "SuperQ"
        ]

        // 1. Accessibility Focused Application (The app currently receiving keyboard inputs)
        let systemWide = AXUIElementCreateSystemWide()
        var focusedAppValue: AnyObject?
        if AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focusedAppValue) == .success,
           let focusedApp = focusedAppValue {
            var axPid: pid_t = 0
            if AXUIElementGetPid(focusedApp as! AXUIElement, &axPid) == .success, axPid != myPid && axPid > 1 {
                let axName = getProcessPath(pid: axPid).map { ($0 as NSString).lastPathComponent } ?? ""
                if !ignoredOwners.contains(axName) && !overlayOwners.contains(axName) && axName != "Finder" {
                    if let target = makeTargetInfo(pid: axPid, fallbackName: axName.isEmpty ? "Focused Application" : axName) {
                        logger.notice("Found AX focused target: \(target.name, privacy: .public) (PID: \(target.pid))")
                        return target
                    }
                }
            }
        }

        // 2. CoreGraphics On-Screen Window List (inspects true frontmost window in Z-order)
        // Works for full screen games, Metal/OpenGL exclusive modes, SDL2, Wine, emulators
        if let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[CFString: Any]] {
            struct CandidateWindow {
                let pid: pid_t
                let owner: String
                let layer: Int
            }

            var candidates: [CandidateWindow] = []
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

                candidates.append(CandidateWindow(pid: pid, owner: owner, layer: layer))
            }

            // If the top window is an in-game overlay (e.g. Steam Helper), prioritize the real game window underneath it
            let selectedCandidate: CandidateWindow?
            if let nonOverlay = candidates.first(where: { !self.overlayOwners.contains($0.owner) && $0.owner != "Finder" }) {
                selectedCandidate = nonOverlay
            } else {
                selectedCandidate = candidates.first
            }

            if let chosen = selectedCandidate, let target = makeTargetInfo(pid: chosen.pid, fallbackName: chosen.owner) {
                logger.notice("Found on-screen window target: \(target.name, privacy: .public) (PID: \(target.pid), layer: \(chosen.layer))")
                return target
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

        var name = execPath.map { ($0 as NSString).lastPathComponent } ?? fallbackName

        // If the process is a runner like wine, inspect arguments for the real game executable
        let lowerName = name.lowercased()
        if lowerName.contains("wine") || lowerName.contains("crossover") || lowerName.contains("proton") || lowerName == "python" || lowerName == "sh" || lowerName == "bash" {
            let args = getProcessArgs(pid: pid)
            for arg in args {
                if arg.hasSuffix(".exe") || arg.hasSuffix(".app") {
                    let exeName = (arg as NSString).lastPathComponent
                    let clean = exeName.replacingOccurrences(of: ".exe", with: "")
                    if !clean.isEmpty {
                        name = clean
                        break
                    }
                }
            }
        }

        return TargetProcessInfo(
            pid: pid,
            name: name,
            icon: icon,
            bundleURL: bundleURL,
            bundleIdentifier: nil
        )
    }

    // MARK: - Related & Background Process Discovery

    private let launcherOrSystemProcesses: Set<String> = [
        "launchd", "WindowServer", "Window Server", "loginwindow", "Dock",
        "Finder", "Steam", "steam_osx", "Terminal", "iTerm2", "Ghostty",
        "Alacritty", "kitty", "zsh", "bash", "sh", "fish", "SuperQ"
    ]

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

        // 1. Climb up to find session root (stopping at client/system launchers like Steam or Finder)
        var currentAncestor = targetPid
        while let ppid = parentMap[currentAncestor], ppid > 1 {
            let pName = pidToPath[ppid].map { ($0 as NSString).lastPathComponent } ?? ""
            if launcherOrSystemProcesses.contains(pName) {
                break
            }
            resolvedPids.insert(ppid)
            currentAncestor = ppid
        }

        // 2. Collect all descendant processes of all ancestors/roots (descendants of session root)
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

        // 3. Collect all processes executing from inside the same app bundle directory
        var bundlePath = bundleURL?.path
        if bundlePath == nil, let execPath = pidToPath[targetPid] {
            bundlePath = extractBundlePath(from: execPath)
        }

        if let bp = bundlePath {
            for (p, path) in pidToPath {
                if path.hasPrefix(bp + "/") || path == bp {
                    resolvedPids.insert(p)
                }
            }
        }

        // 4. Collect processes running from the same runner or game prefix directory (Wine/Proton/Steam)
        for checkPid in [targetPid, currentAncestor] {
            if let path = pidToPath[checkPid] {
                for marker in ["/runners/", "/compatdata/", "/steamapps/common/"] {
                    if let range = path.range(of: marker) {
                        let afterMarker = path[range.upperBound...]
                        let folderName = afterMarker.components(separatedBy: "/").first ?? ""
                        if !folderName.isEmpty {
                            let prefixDir = String(path[..<range.upperBound]) + folderName
                            for (p, pPath) in pidToPath {
                                if pPath.hasPrefix(prefixDir) {
                                    resolvedPids.insert(p)
                                }
                            }
                        }
                    }
                }
            }
        }

        // 4b. Collect any process matching active game keywords (executable name, app id, or game folder)
        var gameKeywords: [String] = []
        for checkPid in [targetPid, currentAncestor] {
            var checkStrings = getProcessArgs(pid: checkPid)
            if let p = pidToPath[checkPid] { checkStrings.append(p) }
            for str in checkStrings {
                if let range = str.range(of: "steamapps/common/") {
                    let folder = str[range.upperBound...].components(separatedBy: "/").first ?? ""
                    if !folder.isEmpty && !gameKeywords.contains(folder) { gameKeywords.append(folder) }
                }
                if let range = str.range(of: "compatdata/") {
                    let appId = str[range.upperBound...].components(separatedBy: "/").first ?? ""
                    if !appId.isEmpty && !gameKeywords.contains(appId) { gameKeywords.append(appId) }
                }
                if str.hasSuffix(".exe") {
                    let exe = (str as NSString).lastPathComponent
                    if !gameKeywords.contains(exe) { gameKeywords.append(exe) }
                }
            }
        }

        if !gameKeywords.isEmpty {
            for (p, path) in pidToPath {
                let pArgs = getProcessArgs(pid: p)
                let allPStrings = [path] + pArgs
                for kw in gameKeywords {
                    if allPStrings.contains(where: { $0.contains(kw) }) {
                        resolvedPids.insert(p)
                        break
                    }
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

        // 6. Collect processes in same process group (if not system daemon)
        if let targetPgid = pidToPgid[targetPid], targetPgid > 1, targetPgid != myPid && targetPgid != myPpid {
            let leaderName = pidToPath[targetPgid].map { ($0 as NSString).lastPathComponent } ?? ""
            if !launcherOrSystemProcesses.contains(leaderName) {
                for (p, pgid) in pidToPgid {
                    if pgid == targetPgid {
                        resolvedPids.insert(p)
                    }
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

    private func getProcessArgs(pid: pid_t) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        if sysctl(&mib, 3, nil, &size, nil, 0) != 0 || size == 0 {
            return []
        }
        var buffer = [CChar](repeating: 0, count: size)
        if sysctl(&mib, 3, &buffer, &size, nil, 0) != 0 {
            return []
        }
        var argc: Int32 = 0
        memcpy(&argc, buffer, MemoryLayout<Int32>.size)
        var offset = MemoryLayout<Int32>.size
        while offset < size && buffer[offset] != 0 { offset += 1 }
        while offset < size && buffer[offset] == 0 { offset += 1 }
        var args: [String] = []
        while offset < size && args.count < Int(argc) {
            let start = offset
            while offset < size && buffer[offset] != 0 { offset += 1 }
            if offset > start {
                let str = String(cString: Array(buffer[start...offset]))
                args.append(str)
            }
            offset += 1
        }
        return args
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
