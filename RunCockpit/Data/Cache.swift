import Foundation

/// Cached history aggregate for one session, invalidated when the transcript mtime changes.
struct CachedSummary: Codable {
    var sessionId: String
    var mtime: Date
    var title: String
    var titleIsCommand: Bool?   // optional: old caches predate it → decode as nil → false
    var cwd: String
    var branch: String
    var model: String
    var startedAt: Date
    var endedAt: Date?
    var durationMs: Double?
    var tokens: TokenBuckets
    var agentCount: Int
    var tours: Int
}

/// Single JSON index of history aggregates under App Support.
/// ponytail: one file for v1; switch to per-session files / SQLite only if it gets slow.
final class HistoryCache {
    private var map: [String: CachedSummary]

    init() {
        if let data = try? Data(contentsOf: Paths.historyCacheFile),
           let m = try? JSONDecoder().decode([String: CachedSummary].self, from: data) {
            map = m
        } else {
            map = [:]
        }
    }

    /// Valid cached entry only if the mtime still matches.
    func get(_ sessionId: String, mtime: Date) -> CachedSummary? {
        guard let c = map[sessionId], abs(c.mtime.timeIntervalSince(mtime)) < 0.5 else { return nil }
        return c
    }

    func put(_ s: CachedSummary) { map[s.sessionId] = s }

    func save() {
        if let data = try? JSONEncoder().encode(map) {
            try? data.write(to: Paths.historyCacheFile, options: .atomic)
        }
    }
}

/// cwd → normalized git remote, persisted as one JSON file. `""` means "probed,
/// no remote" so non-repo folders are never re-probed. Permanent (a remote URL
/// effectively never changes); cleared only by the Settings "Re-detect" action.
/// ponytail: one file, no mtime invalidation — distinct cwds are few.
final class GitRemoteCache {
    private(set) var map: [String: String]

    init() {
        if let data = try? Data(contentsOf: Paths.gitRemoteCacheFile),
           let m = try? JSONDecoder().decode([String: String].self, from: data) {
            map = m
        } else {
            map = [:]
        }
    }

    func has(_ cwd: String) -> Bool { map[cwd] != nil }
    func put(_ cwd: String, _ remote: String) { map[cwd] = remote }
    func clear() { map = [:] }

    func save() {
        if let data = try? JSONEncoder().encode(map) {
            try? data.write(to: Paths.gitRemoteCacheFile, options: .atomic)
        }
    }
}
