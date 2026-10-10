import AppKit
import ApplicationServices

/// The Accessibility permission, needed to press keyboard shortcuts.
enum Permissions {
    /// Live answer: reflects a change in System Settings right away.
    static var keyboardGranted: Bool { AXIsProcessTrusted() || CGPreflightPostEventAccess() }

    /// Shows the system prompt and adds the app to the list in System Settings.
    static func request() { CGRequestPostEventAccess() }

    /// A process that started before the permission was granted can keep a stale "no" for sending
    /// key presses. A relaunch clears it.
    static var staleInThisProcess: Bool { AXIsProcessTrusted() && !CGPreflightPostEventAccess() }

    /// Relaunches at most once a minute, so a stuck answer can never cause a restart loop.
    static func relaunchIfStale(arguments: [String] = []) -> Bool {
        guard staleInThisProcess else { return false }
        let defaults = UserDefaults.standard
        let last = defaults.double(forKey: "relaunchedForAccessAt")
        let now = Date().timeIntervalSince1970
        guard now - last > 60 else { return false }
        defaults.set(now, forKey: "relaunchedForAccessAt")
        log.info("relaunching to pick up the Accessibility permission")

        let quoted = arguments.map { "'\($0.replacingOccurrences(of: "'", with: ""))'" }.joined(separator: " ")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.7; /usr/bin/open -n '\(Bundle.main.bundlePath)' --args \(quoted)"]
        try? task.run()
        NSApp.terminate(nil)
        return true
    }
}
