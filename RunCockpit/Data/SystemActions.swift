import AppKit
import Darwin
import UniformTypeIdentifiers

/// Stateless OS-integration helpers for the session action buttons.
/// The app is unsandboxed (see project.pbxproj), so NSWorkspace / NSPasteboard /
/// launching `.command` scripts all work without entitlements.
enum SystemActions {

    static func copy(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
    }

    /// Reveals the project directory in Finder. `false` if path is empty.
    @discardableResult
    static func revealInFinder(path: String) -> Bool {
        guard !path.isEmpty else { return false }
        return NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    /// Opens a new default-terminal window, `cd`s into the project dir and runs
    /// `claude --resume <id>`. The `cd` is required — resume only finds the
    /// session from its own project directory. `false` if cwd is empty.
    @discardableResult
    static func resume(sessionId: String, cwd: String) -> Bool {
        guard !cwd.isEmpty else { return false }
        // ponytail: single-quote escape — wrap in '...', and replace any ' with '\''
        let safeCwd = "'" + cwd.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let script = """
        #!/bin/zsh
        cd \(safeCwd) || exit 1
        exec claude --resume \(sessionId)
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("resume-\(sessionId).command")
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                                  ofItemAtPath: url.path)
        } catch {
            return false
        }
        return NSWorkspace.shared.open(url)
    }

    /// Sends SIGTERM to a live session's PID. `false` if the pid is dead or the
    /// signal fails. The transcript persists, so the session stays resumable.
    static func terminate(pid: Int) -> Bool {
        guard Registry.pidAlive(pid) else { return false }   // also guards stale/reused pid
        // ponytail: SIGTERM only — add a SIGKILL escalation (re-check after ~1s) only if
        // real sessions turn out to ignore SIGTERM.
        return kill(pid_t(pid), SIGTERM) == 0
    }

    /// Reveals a file in Finder, selecting it within its containing folder.
    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Opens `path` with the application at `appURL`.
    static func open(path: String, withAppAt appURL: URL) {
        let cfg = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([URL(fileURLWithPath: path)],
                                withApplicationAt: appURL,
                                configuration: cfg) { _, _ in }
    }

    /// Prompts the user to pick an application (defaults to /Applications).
    static func chooseApplication(lang: Language) -> URL? {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = tr("Choose", lang)
        panel.message = tr("Choose the application to open projects", lang)
        return panel.runModal() == .OK ? panel.url : nil
    }
}
