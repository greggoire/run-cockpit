import Foundation

/// Filesystem locations. `~/.claude` is read-only; everything the app writes
/// lives under `~/Library/Application Support/RunCockpit/`.
enum Paths {
    static let home = FileManager.default.homeDirectoryForCurrentUser

    // Read-only sources
    static var claudeDir: URL { home.appendingPathComponent(".claude", isDirectory: true) }
    static var sessionsDir: URL { claudeDir.appendingPathComponent("sessions", isDirectory: true) }
    static var projectsDir: URL { claudeDir.appendingPathComponent("projects", isDirectory: true) }

    // App-owned, writable
    static var appSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? home.appendingPathComponent("Library/Application Support", isDirectory: true)
        let dir = base.appendingPathComponent("RunCockpit", isDirectory: true)
        let fm = FileManager.default
        if !fm.fileExists(atPath: dir.path) {                      // ponytail: one-time migration from old "RunCockpit" brand, drop in a version or two
            let legacy = base.appendingPathComponent("RunCockpit", isDirectory: true)
            if fm.fileExists(atPath: legacy.path) { try? fm.moveItem(at: legacy, to: dir) }
        }
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    static var cacheDir: URL {
        let dir = appSupport.appendingPathComponent("cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    static var pricingFile: URL { appSupport.appendingPathComponent("pricing.json") }
    static var settingsFile: URL { appSupport.appendingPathComponent("settings.json") }
    static var historyCacheFile: URL { appSupport.appendingPathComponent("history-cache.json") }
    static var gitRemoteCacheFile: URL { appSupport.appendingPathComponent("git-remotes.json") }

    /// All `<projectDir>` entries under projects/.
    static func projectDirs() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: projectsDir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]))?
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true } ?? []
    }

    /// Top-level `<sessionId>.jsonl` transcript files for a project dir.
    static func transcripts(in projectDir: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: projectDir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]))?
            .filter { $0.pathExtension == "jsonl" } ?? []
    }

    /// Locate the transcript file + its project dir for a given sessionId.
    static func locateTranscript(sessionId: String) -> (file: URL, projectDir: URL)? {
        for dir in projectDirs() {
            let f = dir.appendingPathComponent("\(sessionId).jsonl")
            if FileManager.default.fileExists(atPath: f.path) { return (f, dir) }
        }
        return nil
    }

    /// `<projectDir>/<sessionId>/subagents/` — flat dir of agent-*.jsonl + .meta.json.
    static func subagentsDir(projectDir: URL, sessionId: String) -> URL {
        projectDir.appendingPathComponent(sessionId, isDirectory: true)
            .appendingPathComponent("subagents", isDirectory: true)
    }

    /// `<projectDir>/<sessionId>/workflows/` — wf_xxx.json metadata + scripts/.
    static func workflowsDir(projectDir: URL, sessionId: String) -> URL {
        projectDir.appendingPathComponent(sessionId, isDirectory: true)
            .appendingPathComponent("workflows", isDirectory: true)
    }

    /// `<projectDir>/<sessionId>/subagents/workflows/` — wf_xxx/ subdirs with agent transcripts.
    static func subagentWorkflowsDir(projectDir: URL, sessionId: String) -> URL {
        subagentsDir(projectDir: projectDir, sessionId: sessionId)
            .appendingPathComponent("workflows", isDirectory: true)
    }

    static func mtime(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}
