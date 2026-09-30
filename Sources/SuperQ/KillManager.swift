import Cocoa
import os

final class KillManager {
    static let shared = KillManager()
    private let logger = Logger(subsystem: "com.antigravity.superq", category: "KillManager")

    private init() {}

    @discardableResult
    func forceQuitFrontmostApp() -> Bool {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            logger.notice("No frontmost application found")
            return false
        }

        return forceQuitApp(frontApp)
    }

    @discardableResult
    func forceQuitApp(_ app: NSRunningApplication) -> Bool {
        let currentPid = ProcessInfo.processInfo.processIdentifier
        let targetPid = app.processIdentifier

        // Safety check 1: Never kill SuperKill itself
        if targetPid == currentPid {
            logger.notice("Ignored attempt to kill SuperKill itself")
            return false
        }

        // Safety check 2: Already terminated
        if app.isTerminated {
            logger.notice("Target application is already terminated: PID \(targetPid)")
            return false
        }

        let appName = app.localizedName ?? "Application"
        let appIcon = app.icon
        let bundleId = app.bundleIdentifier ?? "unknown"

        logger.notice("Force quitting: \(appName) (Bundle: \(bundleId), PID: \(targetPid))")

        // 1. Direct POSIX SIGKILL (instant, uncompromising kernel termination)
        kill(targetPid, SIGKILL)

        // 2. LaunchServices force termination
        app.forceTerminate()

        // 3. Audio feedback
        if SettingsManager.shared.isSoundEnabled {
            playKillSound()
        }

        // 4. Visual HUD feedback
        if SettingsManager.shared.isHUDEnabled {
            DispatchQueue.main.async {
                HUDController.shared.show(appName: appName, appIcon: appIcon, pid: targetPid)
            }
        }

        return true
    }

    func forceQuitPID(_ pid: pid_t) -> Bool {
        let currentPid = ProcessInfo.processInfo.processIdentifier
        if pid == currentPid {
            return false
        }

        // Check if there is an NSRunningApplication for it
        if let app = NSRunningApplication(processIdentifier: pid) {
            return forceQuitApp(app)
        }

        // Otherwise kill raw PID
        logger.notice("Force quitting raw PID \(pid)")
        kill(pid, SIGKILL)

        if SettingsManager.shared.isSoundEnabled {
            playKillSound()
        }

        if SettingsManager.shared.isHUDEnabled {
            DispatchQueue.main.async {
                HUDController.shared.show(appName: "Process (PID: \(pid))", appIcon: nil, pid: pid)
            }
        }

        return true
    }

    private func playKillSound() {
        // Use Funk or Pop or Tink for a pleasant, subtle confirmation sound
        if let sound = NSSound(named: "Funk") {
            sound.play()
        } else if let sound = NSSound(named: "Tink") {
            sound.play()
        } else {
            NSSound.beep()
        }
    }
}
