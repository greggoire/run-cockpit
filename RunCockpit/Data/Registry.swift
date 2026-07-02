import Foundation
import Darwin

/// Reads `~/.claude/sessions/<PID>.json` and filters to *living* interactive sessions.
enum Registry {
    /// Is the process still alive? `kill(pid, 0)` returns 0 (exists) or fails with
    /// EPERM (exists, not ours). ESRCH means dead → stale file.
    static func pidAlive(_ pid: Int) -> Bool {
        if pid <= 0 { return false }
        let r = kill(pid_t(pid), 0)
        if r == 0 { return true }
        return errno == EPERM
    }

    /// Session IDs are UUIDs. Anything else is untrusted filesystem content (a crafted
    /// transcript filename or registry field) that must never reach a shell (resume) or a
    /// path builder — reject it at ingestion so the rest of the app sees only valid ids.
    static func isValidSessionId(_ s: String) -> Bool { UUID(uuidString: s) != nil }

    /// Live interactive sessions (kind == "interactive", PID alive).
    static func liveSessions() -> [SessionRegistry] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: Paths.sessionsDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        let dec = JSONDecoder()
        var out: [SessionRegistry] = []
        for f in files where f.pathExtension == "json" {
            guard let data = try? Data(contentsOf: f),
                  let reg = try? dec.decode(SessionRegistry.self, from: data) else { continue }
            guard (reg.kind ?? "interactive") == "interactive" else { continue }
            guard isValidSessionId(reg.sessionId) else { continue }  // O1/O4: untrusted id → reject before paths/shell
            guard pidAlive(reg.pid) else { continue }       // stale artifact otherwise
            out.append(reg)
        }
        return out
    }
}
