import Foundation

// MARK: - Live session registry  (~/.claude/sessions/<PID>.json)

struct SessionRegistry: Decodable {
    let pid: Int
    let sessionId: String
    let cwd: String
    let startedAt: Int          // epoch ms
    let kind: String?           // "interactive" only is kept
    let status: String?         // "busy" | "idle"
    let updatedAt: Int?         // epoch ms
    let statusUpdatedAt: Int?   // epoch ms
    let name: String?
    let agent: String?

    var startedDate: Date { Date(timeIntervalSince1970: Double(startedAt) / 1000) }
    var updatedDate: Date { Date(timeIntervalSince1970: Double(updatedAt ?? startedAt) / 1000) }
}

// MARK: - Transcript line  (one JSON object per line in <sessionId>.jsonl)

struct TranscriptEntry: Decodable {
    let type: String
    let uuid: String?
    let parentUuid: String?
    let sessionId: String?
    let timestamp: String?      // ISO-8601 with millis + Z
    let cwd: String?
    let gitBranch: String?
    let isSidechain: Bool?
    let isMeta: Bool?
    let isCompactSummary: Bool?
    let slug: String?
    let message: RawMessage?
    let toolUseResult: ToolUseResult?
    let aiTitle: String?
    let operation: String?   // "queue-operation" porte les <task-notification>
    let content: String?     // top-level string (queue-operation / system) — distinct de message.content

    var date: Date? { timestamp.flatMap(RVDate.parseISO) }
}

struct RawMessage: Decodable {
    let id: String?
    let model: String?
    let role: String?
    let type: String?
    let stop_reason: String?
    let usage: RawUsage?
    let content: MessageContent?
}

struct RawUsage: Decodable {
    let input_tokens: Int?
    let output_tokens: Int?
    let cache_read_input_tokens: Int?
    let cache_creation_input_tokens: Int?
    let cache_creation: RawCacheCreation?

    struct RawCacheCreation: Decodable {
        let ephemeral_5m_input_tokens: Int?
        let ephemeral_1h_input_tokens: Int?
    }

    var buckets: TokenBuckets {
        let e5 = cache_creation?.ephemeral_5m_input_tokens
        let e1 = cache_creation?.ephemeral_1h_input_tokens
        let write5: Int, write1: Int
        if e5 != nil || e1 != nil {
            write5 = e5 ?? 0; write1 = e1 ?? 0
        } else {
            // Older entries: only the flat total is present → treat as 5m.
            write5 = cache_creation_input_tokens ?? 0; write1 = 0
        }
        return TokenBuckets(input: input_tokens ?? 0,
                            output: output_tokens ?? 0,
                            cacheWrite5m: write5,
                            cacheWrite1h: write1,
                            cacheRead: cache_read_input_tokens ?? 0)
    }
}

/// `message.content` is either a plain string or an array of typed blocks.
enum MessageContent: Decodable {
    case text(String)
    case blocks([Block])

    struct Block: Decodable {
        let type: String?           // "text" | "tool_use" | "tool_result"
        let text: String?
        let name: String?           // tool_use: tool name
        let id: String?             // tool_use: block id
        let input: ToolInput?       // tool_use: arguments (targeted fields only)
        let tool_use_id: String?    // tool_result: points back to tool_use.id
        let is_error: Bool?         // tool_result
        let content: MessageContent? // tool_result: string|blocks → preview via .plainText
    }

    /// Only the tool_use input fields we summarise in the action stream.
    struct ToolInput: Decodable {
        let command: String?; let description: String?
        let file_path: String?; let offset: Int?; let limit: Int?
        let pattern: String?; let path: String?; let glob: String?
        let url: String?; let query: String?
        let subagent_type: String?; let prompt: String?
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { self = .text(s); return }
        if let b = try? c.decode([Block].self) { self = .blocks(b); return }
        self = .text("")
    }

    /// Concatenated text content (text blocks only).
    var plainText: String {
        switch self {
        case .text(let s): return s
        case .blocks(let bs): return bs.compactMap { $0.type == nil || $0.type == "text" ? $0.text : nil }.joined(separator: "\n")
        }
    }
}

// MARK: - Agent / Task spawn result  (toolUseResult on a parent tool entry)

struct ToolUseResult: Decodable {
    let agentId: String?
    let agentType: String?
    let resolvedModel: String?
    let status: String?         // "async_launched" | "completed"
    let prompt: String?
    let usage: RawUsage?
    let toolStats: RawToolStats?

    struct RawToolStats: Decodable {
        let readCount: Int?
        let searchCount: Int?
        let bashCount: Int?
        let editFileCount: Int?
        let linesAdded: Int?
        let linesRemoved: Int?
        let otherToolCount: Int?

        var domain: ToolStats {
            ToolStats(read: readCount ?? 0, bash: bashCount ?? 0, edit: editFileCount ?? 0,
                      search: searchCount ?? 0, linesAdded: linesAdded ?? 0,
                      linesRemoved: linesRemoved ?? 0, other: otherToolCount ?? 0)
        }
    }
}

// MARK: - Sub-agent sidecar  (subagents/agent-<id>.meta.json)

struct AgentMeta: Decodable {
    let agentType: String?
    let description: String?
}

// MARK: - Date helpers

enum RVDate {
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoNoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parseISO(_ s: String) -> Date? {
        iso.date(from: s) ?? isoNoFrac.date(from: s)
    }
}
