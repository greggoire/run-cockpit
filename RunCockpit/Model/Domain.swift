import Foundation

/// Reliable session state (PRD: "états fiables uniquement").
enum SessionStatus: String, Codable, Sendable {
    case busy   // 🟢 en cours
    case idle   // ⚪ attend ton action
    case done   // ⚫ terminée
}

/// The five token buckets kept separate because each is priced differently.
struct TokenBuckets: Codable, Sendable, Equatable {
    var input: Int = 0
    var output: Int = 0
    var cacheWrite5m: Int = 0   // cache_creation.ephemeral_5m_input_tokens
    var cacheWrite1h: Int = 0   // cache_creation.ephemeral_1h_input_tokens
    var cacheRead: Int = 0      // cache_read_input_tokens

    var total: Int { input + output + cacheWrite5m + cacheWrite1h + cacheRead }

    static func + (a: TokenBuckets, b: TokenBuckets) -> TokenBuckets {
        TokenBuckets(input: a.input + b.input,
                     output: a.output + b.output,
                     cacheWrite5m: a.cacheWrite5m + b.cacheWrite5m,
                     cacheWrite1h: a.cacheWrite1h + b.cacheWrite1h,
                     cacheRead: a.cacheRead + b.cacheRead)
    }

    static func += (a: inout TokenBuckets, b: TokenBuckets) { a = a + b }
}

/// Fixed-shape tool counters from `toolUseResult.toolStats`.
struct ToolStats: Codable, Sendable, Equatable {
    var read = 0
    var bash = 0
    var edit = 0
    var search = 0
    var linesAdded = 0
    var linesRemoved = 0
    var other = 0

    /// Ordered (label, value) pairs for the inspector, skipping zeros.
    var displayPairs: [(String, Int)] {
        var out: [(String, Int)] = []
        if read > 0 { out.append(("read", read)) }
        if bash > 0 { out.append(("bash", bash)) }
        if edit > 0 { out.append(("edit", edit)) }
        if search > 0 { out.append(("search", search)) }
        if linesAdded > 0 { out.append(("+lignes", linesAdded)) }
        if linesRemoved > 0 { out.append(("-lignes", linesRemoved)) }
        if other > 0 { out.append(("autres", other)) }
        return out
    }
}

/// A node in the agent tree (root session or a sub-agent).
struct AgentNode: Identifiable, Sendable, Equatable {
    let id: String              // "root" or agentId
    var parentId: String?
    var label: String
    var agentType: String
    var model: String
    var status: SessionStatus
    var tokens: TokenBuckets
    var start: Date?
    var end: Date?
    var tools: ToolStats
    var prompt: String
    var actions: [ActionEvent] = []

    var durationMs: Double? {
        guard let s = start else { return nil }
        let e = end ?? Date()
        return e.timeIntervalSince(s) * 1000
    }
}

enum TimelineKind: String, Sendable { case start, spawn, done, active }

struct TimelineEvent: Identifiable, Sendable {
    let id = UUID()
    let time: Date
    let kind: TimelineKind
    let label: String
    var durationMs: Double?
}

/// One step in an agent's action stream (assistant reasoning text or a tool call).
enum ActionKind: Sendable { case text, tool }

struct ActionEvent: Identifiable, Sendable, Equatable {
    let id = UUID()
    let kind: ActionKind
    var time: Date?
    var body = ""               // text
    var tool = ""               // tool_use.name
    var summary = ""            // formatted input summary
    var isError = false
    var running = false
    var meta: String? = nil     // result preview (error text / "réponse remontée")
    var tokens = 0
    var durationMs: Double? = nil
}

/// Lightweight summary used in the active dashboard and history lists.
struct SessionSummary: Identifiable, Sendable, Equatable {
    let id: String              // sessionId
    var pid: Int?
    var live: Bool
    var status: SessionStatus
    var title: String
    var titleIsCommand: Bool = false   // title is a raw slash-command name → localize prefix at display time
    var cwd: String             // absolute, fiable
    var branch: String
    var model: String
    var startedAt: Date
    var lastActivity: Date
    var endedAt: Date?
    var tours: Int
    var subActive: Int
    var tokens: TokenBuckets
    var agentCount: Int = 0

    /// `~`-collapsed project path for display.
    var projectDisplay: String { ProjectIdentity.collapseHome(cwd) }
}

/// Full detail of one session: tree + timeline + totals.
struct SessionDetail: Sendable {
    var summary: SessionSummary
    var agents: [AgentNode]
    var timeline: [TimelineEvent]

    var totalTokens: TokenBuckets {
        agents.reduce(TokenBuckets()) { $0 + $1.tokens }
    }
    var agentCount: Int { agents.count }
}
