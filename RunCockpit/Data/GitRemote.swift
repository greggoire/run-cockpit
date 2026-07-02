import Foundation

/// Resolves a project directory's git remote URL so worktrees/clones of the
/// same repo collapse into one logical project. Uses the `git` CLI (not a
/// `.git/config` parse) because a worktree's `.git` is a *file* pointing into
/// the main repo — only `git -C` resolves that indirection transparently.
enum GitRemote {

    /// `git -C <cwd> config --get remote.origin.url`. nil on non-repo / no origin / failure.
    static func remote(forCwd cwd: String) -> String? {
        guard !cwd.isEmpty, FileManager.default.fileExists(atPath: cwd) else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", cwd, "config", "--get", "remote.origin.url"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()           // swallow "not a git repository" noise
        do { try p.run() } catch { return nil }
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let s = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return s.isEmpty ? nil : s
    }

    /// Canonical key from any remote URL form → `host/owner/repo` (lowercased,
    /// no scheme, no `user@`, scp `:`→`/`, no trailing `.git`/slash). "" if blank.
    ///   git@github.com:me/run-view.git → github.com/me/run-view
    ///   https://github.com/me/run-view(.git) → github.com/me/run-view
    ///   ssh://git@host/me/run-view → host/me/run-view
    static func normalize(_ url: String) -> String {
        var s = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return "" }
        if let r = s.range(of: "://") { s = String(s[r.upperBound...]) }   // strip scheme
        if let at = s.firstIndex(of: "@") {                                // strip userinfo in authority
            let slash = s.firstIndex(of: "/")
            if slash == nil || at < slash! { s = String(s[s.index(after: at)...]) }
        }
        if let colon = s.firstIndex(of: ":") { s.replaceSubrange(colon...colon, with: "/") } // scp host:path
        while s.hasSuffix("/") { s.removeLast() }
        if s.hasSuffix(".git") { s.removeLast(4) }
        while s.hasSuffix("/") { s.removeLast() }
        return s.lowercased()
    }
}

/// Single source of truth for "which project does a session belong to" and how
/// it's labelled — reused by AppState accessors and StatsData aggregation.
enum ProjectIdentity {
    /// Grouping key: the cached normalized remote when enabled & present, else
    /// the raw cwd (current per-folder behavior).
    static func key(cwd: String, remotes: [String: String], enabled: Bool) -> String {
        guard enabled, let r = remotes[cwd], !r.isEmpty else { return cwd }
        return r
    }

    /// Display label: short repo name for a remote key, `~`-collapsed path otherwise.
    static func label(forKey key: String) -> String {
        if key.hasPrefix("/") { return collapseHome(key) }
        return key.split(separator: "/").last.map(String.init) ?? key
    }

    /// `$HOME` → `~` for display (shared by SessionSummary.projectDisplay & stats).
    /// home is constant for the process lifetime; resolve it once (called per row).
    private static let home = FileManager.default.homeDirectoryForCurrentUser.path
    static func collapseHome(_ path: String) -> String {
        path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

#if DEBUG
/// ponytail: no test target exists; this assert-based check runs every debug
/// launch (called from RunCockpitApp) and fails loudly if normalize regresses.
func gitRemoteNormalizeSelfCheck() {
    assert(GitRemote.normalize("git@github.com:me/run-view.git") == "github.com/me/run-view")
    assert(GitRemote.normalize("https://github.com/me/run-view.git") == "github.com/me/run-view")
    assert(GitRemote.normalize("https://github.com/me/run-view") == "github.com/me/run-view")
    assert(GitRemote.normalize("ssh://git@host.example/me/Run-View/") == "host.example/me/run-view")
    assert(GitRemote.normalize("   ") == "")
}

/// O1/O4: session ids must be UUIDs so untrusted filenames never reach a shell/path.
func sessionIdSelfCheck() {
    assert(Registry.isValidSessionId("4514F2D9-1B2A-4C3D-8E5F-0A1B2C3D4E5F"))
    assert(!Registry.isValidSessionId("../../etc/passwd"))
    assert(!Registry.isValidSessionId("x; rm -rf ~"))
    assert(!Registry.isValidSessionId(""))
}
#endif
