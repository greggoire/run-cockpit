import Foundation

enum Transcript {
    /// Tolerant line-by-line decode; malformed lines are skipped.
    static func parse(_ url: URL) -> [TranscriptEntry] {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let dec = JSONDecoder()
        var out: [TranscriptEntry] = []
        out.reserveCapacity(1024)
        raw.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return }
            if let e = try? dec.decode(TranscriptEntry.self, from: data) { out.append(e) }
        }
        return out
    }

    /// Sum token usage, de-duplicated by `message.id`, excluding synthetic messages.
    static func dedupTokens(_ entries: [TranscriptEntry]) -> TokenBuckets {
        var total = TokenBuckets()
        var seen = Set<String>()
        for e in entries where e.type == "assistant" {
            guard let m = e.message, let usage = m.usage else { continue }
            if (m.model ?? "") == "<synthetic>" { continue }
            if let id = m.id {
                if !seen.insert(id).inserted { continue }   // duplicate API line
            }
            total += usage.buckets
        }
        return total
    }

    /// True when the agent's own transcript shows a finished run:
    /// the last assistant turn ended (`end_turn`) rather than stopping mid tool-use.
    /// While running, the latest assistant line is a `tool_use` stop (or the last line is
    /// a `user` tool_result) — never `end_turn`, which is terminal for a Task sub-agent.
    // ponytail: end_turn covers normal completion; widen to other terminal stop_reasons (max_tokens, etc.) only if a real case shows up.
    static func isFinished(_ entries: [TranscriptEntry]) -> Bool {
        for e in entries.reversed() where e.type == "assistant" {
            return e.message?.stop_reason == "end_turn"
        }
        return false   // no assistant output yet → just spawned, treat as running
    }

    /// agentIds for which a parent transcript carries a terminal `<task-notification>`.
    /// This is the authoritative "done" signal for async/background Task sub-agents,
    /// whose parent `toolUseResult.status` stays "async_launched" and whose own
    /// transcript may end without an `end_turn` assistant line.
    static func notifiedDoneAgentIds(_ entries: [TranscriptEntry]) -> Set<String> {
        let terminal: Set<String> = ["completed", "failed", "killed", "cancelled", "error", "timeout"]
        var done = Set<String>()
        for e in entries {
            guard let text = e.content, text.contains("<task-notification>"),
                  let id = between(text, "<task-id>", "</task-id>"),
                  let st = between(text, "<status>", "</status>"),
                  terminal.contains(st) else { continue }
            done.insert(id)
        }
        return done
    }

    /// Substring strictly between `open` and `close`, trimmed; nil if absent/disordered.
    private static func between(_ s: String, _ open: String, _ close: String) -> String? {
        guard let r1 = s.range(of: open), let r2 = s.range(of: close),
              r1.upperBound <= r2.lowerBound else { return nil }
        let v = s[r1.upperBound..<r2.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? nil : v
    }

    /// Most recent non-synthetic assistant model.
    static func lastModel(_ entries: [TranscriptEntry]) -> String {
        for e in entries.reversed() where e.type == "assistant" {
            if let m = e.message?.model, m != "<synthetic>" { return m }
        }
        return ""
    }

    /// Everything `listActive`/`detail`/history need from a transcript, collected in a
    /// SINGLE forward pass — replaces ~6 separate O(n) traversals of the same array.
    struct Summary {
        var tokens = TokenBuckets()
        var model = ""
        var title = ""
        var titleIsCommand = false   // title is a raw slash-command name → localize prefix at display
        var branch = ""
        var cwd = ""
        var tours = 0
        var firstPrompt = ""
        var firstDate: Date?
        var lastDate: Date?
        var isEmpty = true
    }

    static func summarize(_ entries: [TranscriptEntry], fallback: String) -> Summary {
        var s = Summary()
        var seenTokenIds = Set<String>()
        var lastAiTitle: String?
        var firstSlug: String?
        var firstPrompt: String?
        var commandName: String?

        for e in entries {
            s.isEmpty = false

            if let d = e.date {
                if s.firstDate == nil || d < s.firstDate! { s.firstDate = d }
                if s.lastDate == nil || d > s.lastDate! { s.lastDate = d }
            }
            if s.branch.isEmpty, let b = e.gitBranch, !b.isEmpty { s.branch = b }
            if s.cwd.isEmpty, let c = e.cwd, !c.isEmpty { s.cwd = c }
            if e.type == "ai-title", let t = e.aiTitle, !t.isEmpty { lastAiTitle = t }   // keep last
            if firstSlug == nil, let sl = e.slug, !sl.isEmpty { firstSlug = sl }

            switch e.type {
            case "assistant":
                if let m = e.message, let usage = m.usage, (m.model ?? "") != "<synthetic>" {
                    let isDup = m.id.map { !seenTokenIds.insert($0).inserted } ?? false   // duplicate API line
                    if !isDup { s.tokens += usage.buckets }
                }
                if let mm = e.message?.model, mm != "<synthetic>" { s.model = mm }   // forward pass → ends as latest
            case "user":
                if e.isSidechain != true && e.isMeta != true { s.tours += 1 }
                if firstPrompt == nil, let t = isRealPrompt(e) { firstPrompt = t }
                if commandName == nil, e.isSidechain != true,
                   let text = e.message?.content?.plainText,
                   let r1 = text.range(of: "<command-name>"),
                   let r2 = text.range(of: "</command-name>"),
                   r1.upperBound <= r2.lowerBound {
                    let name = text[r1.upperBound..<r2.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty { commandName = name }
                }
            default:
                break
            }
        }

        s.firstPrompt = firstPrompt ?? ""
        // Title priority: ai-title → humanized slug → first real prompt → raw command name → fallback.
        if let t = lastAiTitle { s.title = t }
        else if let sl = firstSlug { s.title = humanize(sl) }
        else if let p = firstPrompt, !p.isEmpty { s.title = String(p.prefix(80)) }
        else if let c = commandName { s.title = c; s.titleIsCommand = true }
        else { s.title = fallback }
        return s
    }

    private static func humanize(_ slug: String) -> String {
        let words = slug.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    /// First genuine user prompt (ignores sidechain/meta/compact and command/system wrappers).
    /// Injected wrappers that are not genuine user prompts.
    private static let wrappers = ["<command-", "<system-reminder", "<local-command",
                                   "<task-notification", "<task-reminder", "<user-prompt-submit-hook"]

    private static func isRealPrompt(_ e: TranscriptEntry) -> String? {
        if e.isSidechain == true || e.isMeta == true || e.isCompactSummary == true { return nil }
        guard let text = e.message?.content?.plainText else { return nil }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty || wrappers.contains(where: { t.hasPrefix($0) }) { return nil }
        return t
    }
}
