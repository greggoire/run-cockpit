import Foundation

enum Agents {
    /// Count tool_use blocks in a transcript into a ToolStats (used for the root node).
    static func countTools(_ entries: [TranscriptEntry]) -> ToolStats {
        var s = ToolStats()
        for e in entries where e.type == "assistant" {
            guard case .blocks(let blocks)? = e.message?.content else { continue }
            for b in blocks where b.type == "tool_use" {
                switch b.name?.lowercased() {
                case "bash":                    s.bash += 1
                case "read":                    s.read += 1
                case "edit", "multiedit",
                     "write", "notebookedit":   s.edit += 1
                case "grep", "glob",
                     "websearch", "webfetch":   s.search += 1
                default:                        s.other += 1
                }
            }
        }
        return s
    }

    /// Ordered per-agent action stream: assistant reasoning text + tool calls with
    /// input summary, correlated to their tool_result for status/error/preview.
    static func actionStream(_ entries: [TranscriptEntry], live: Bool) -> [ActionEvent] {
        // Pass 1: tool_use.id → result (error flag + short preview).
        var results: [String: (isError: Bool, preview: String)] = [:]
        for e in entries where e.type == "user" {
            guard case .blocks(let blocks)? = e.message?.content else { continue }
            for b in blocks where b.type == "tool_result" {
                guard let id = b.tool_use_id else { continue }
                results[id] = (b.is_error == true, String(b.content?.plainText.prefix(200) ?? ""))
            }
        }

        // Pass 2: assistant turns → ordered events.
        var out: [ActionEvent] = []
        for e in entries where e.type == "assistant" {
            guard case .blocks(let blocks)? = e.message?.content else { continue }
            let outTokens = e.message?.usage?.output_tokens ?? 0
            var turnTokenSpent = false  // attribute the turn's output tokens to its first event only
            func nextTokens() -> Int {
                guard !turnTokenSpent else { return 0 }
                turnTokenSpent = true
                return outTokens
            }
            for b in blocks {
                switch b.type {
                case "text":
                    let body = (b.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !body.isEmpty else { continue }
                    out.append(ActionEvent(kind: .text, time: e.date, body: body, tokens: nextTokens()))
                case "tool_use":
                    let tool = b.name ?? "?"
                    var ev = ActionEvent(kind: .tool, time: e.date,
                                         tool: tool, summary: summarize(tool, b.input),
                                         tokens: nextTokens())
                    if let id = b.id, let r = results[id] {
                        ev.isError = r.isError
                        if r.isError { ev.meta = r.preview.isEmpty ? "error" : r.preview }
                        else if tool.lowercased() == "agent" || tool.lowercased() == "task" {
                            ev.meta = "escalated response"
                        }
                    } else if live {
                        ev.running = true   // no result yet on a live session
                    }
                    out.append(ev)
                default:
                    continue
                }
            }
        }
        return out
    }

    /// Tool-specific, human-readable summary of a tool_use input. Paths folded to ~.
    private static func summarize(_ tool: String, _ i: MessageContent.ToolInput?) -> String {
        func home(_ p: String) -> String {
            let h = NSHomeDirectory()
            return p.hasPrefix(h) ? "~" + p.dropFirst(h.count) : p
        }
        guard let i else { return tool }
        switch tool.lowercased() {
        case "bash":
            return i.command ?? i.description ?? "bash"
        case "read":
            var s = i.file_path.map(home) ?? "fichier"
            if let o = i.offset, let l = i.limit { s += "  · l. \(o)–\(o + l)" }
            return s
        case "edit", "multiedit", "write", "notebookedit":
            return i.file_path.map(home) ?? tool
        case "grep", "glob":
            var s = i.pattern ?? i.glob ?? "motif"
            if let p = i.path { s += "  ↳ \(home(p))" }
            return s
        case "agent", "task":
            let t = i.subagent_type ?? "agent"
            return i.description.map { "\(t) — \($0)" } ?? t
        case "webfetch":
            return i.url ?? "url"
        case "websearch":
            return i.query ?? "recherche"
        default:
            return i.description ?? i.command ?? tool
        }
    }

    private static func agentId(fromFile name: String) -> String? {
        guard name.hasPrefix("agent-"), name.hasSuffix(".jsonl") else { return nil }
        return String(name.dropFirst("agent-".count).dropLast(".jsonl".count))
    }

    /// Build sub-agent nodes for a session. Root node is supplied by the caller.
    static func subAgents(projectDir: URL, sessionId: String,
                          parentEntries: [TranscriptEntry], sessionLive: Bool) -> [AgentNode] {
        let dir = Paths.subagentsDir(projectDir: projectDir, sessionId: sessionId)
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return []
        }
        let agentFiles = contents.filter { $0.lastPathComponent.hasPrefix("agent-") && $0.pathExtension == "jsonl" }

        // 1. Spawn map: agentId -> (parentId, toolUseResult). Parent file spawns root-level agents.
        var spawn: [String: (parent: String, tur: ToolUseResult)] = [:]
        func collect(_ entries: [TranscriptEntry], parent: String) {
            for e in entries {
                if let tur = e.toolUseResult, let aid = tur.agentId {
                    spawn[aid] = (parent, tur)
                }
            }
        }
        collect(parentEntries, parent: "root")

        // Parse each agent file once; reuse for spawn linkage + token aggregation.
        var parsed: [String: [TranscriptEntry]] = [:]
        for f in agentFiles {
            guard let aid = agentId(fromFile: f.lastPathComponent) else { continue }
            parsed[aid] = Transcript.parse(f)
        }
        for (aid, entries) in parsed { collect(entries, parent: aid) }

        // Terminal <task-notification>s — authoritative "done" for async sub-agents.
        // A notif about agent X lives in X's parent transcript (root or a parent agent).
        var notifiedDone = Transcript.notifiedDoneAgentIds(parentEntries)
        for (_, entries) in parsed { notifiedDone.formUnion(Transcript.notifiedDoneAgentIds(entries)) }

        // 2. Build a node per agent file.
        var nodes: [AgentNode] = []
        let dec = JSONDecoder()
        for f in agentFiles {
            guard let aid = agentId(fromFile: f.lastPathComponent) else { continue }
            let entries = parsed[aid] ?? []
            let info = spawn[aid]

            // metadata sidecar
            let metaURL = dir.appendingPathComponent("agent-\(aid).meta.json")
            let meta = (try? Data(contentsOf: metaURL)).flatMap { try? dec.decode(AgentMeta.self, from: $0) }

            let agentType = info?.tur.agentType ?? meta?.agentType ?? "agent"
            let model = info?.tur.resolvedModel ?? Transcript.lastModel(entries)
            let tokens = Transcript.dedupTokens(entries)
            let dates = entries.compactMap { $0.date }
            let start = dates.min()
            let statusStr = info?.tur.status
            // ponytail: pas de staleness — la notif terminale suffit ; ajouter un
            // filet mtime si un jour des agents crashent sans notif.
            let finished = statusStr == "completed"
                || notifiedDone.contains(aid)
                || Transcript.isFinished(entries)
            let status: SessionStatus = finished ? .done : (sessionLive ? .busy : .done)
            let end: Date? = status == .done ? dates.max() : nil
            let tools = info?.tur.toolStats?.domain ?? countTools(entries)
            let prompt = info?.tur.prompt ?? meta?.description ?? ""
            let label = meta?.description.map { String($0.prefix(48)) } ?? agentType

            nodes.append(AgentNode(
                id: aid, parentId: info?.parent ?? "root",
                label: label.isEmpty ? agentType : label,
                agentType: agentType, model: model, status: status,
                tokens: tokens, start: start, end: end, tools: tools, prompt: prompt,
                actions: actionStream(entries, live: status == .busy)))
        }

        // Workflow subagents: wf_xxx container + children from subagents/workflows/wf_xxx/.
        nodes += workflowNodes(projectDir: projectDir, sessionId: sessionId,
                               sessionLive: sessionLive, notifiedDone: notifiedDone)

        // Ensure parent references resolve; orphan parents fall back to root.
        let ids = Set(nodes.map(\.id)).union(["root"])
        return nodes.map { n in
            guard let pid = n.parentId, pid == "root" || ids.contains(pid) else {
                var c = n; c.parentId = "root"; return c
            }
            return n
        }
    }

    /// Build synthetic workflow container nodes + their child agents.
    private static func workflowNodes(projectDir: URL, sessionId: String,
                                      sessionLive: Bool, notifiedDone: Set<String>) -> [AgentNode] {
        let fm = FileManager.default
        let wfAgentsDir = Paths.subagentWorkflowsDir(projectDir: projectDir, sessionId: sessionId)
        let wfMetaDir   = Paths.workflowsDir(projectDir: projectDir, sessionId: sessionId)
        guard let subdirs = try? fm.contentsOfDirectory(at: wfAgentsDir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        var result: [AgentNode] = []

        for wfSubdir in subdirs {
            guard (try? wfSubdir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            let wfId = wfSubdir.lastPathComponent   // e.g. "wf_b2891268-d44"

            // Name from scripts/<name>-<wfId>.js
            let scriptsDir = wfMetaDir.appendingPathComponent("scripts")
            let suffix = "-\(wfId).js"
            let scriptName = (try? fm.contentsOfDirectory(atPath: scriptsDir.path))?
                .first { $0.hasSuffix(suffix) }
                .map { String($0.dropLast(suffix.count)) }
                ?? wfId

            // Start time from workflows/wf_xxx.json
            struct WFMeta: Decodable { let timestamp: Date? }
            let wfMetaURL = wfMetaDir.appendingPathComponent("\(wfId).json")
            let wfStart = (try? Data(contentsOf: wfMetaURL))
                .flatMap { try? dec.decode(WFMeta.self, from: $0) }?.timestamp

            // Child agents
            let agentFiles = (try? fm.contentsOfDirectory(at: wfSubdir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]))?
                .filter { $0.lastPathComponent.hasPrefix("agent-") && $0.pathExtension == "jsonl" } ?? []

            var children: [AgentNode] = []
            var aggregateTokens = TokenBuckets()
            var allDone = !agentFiles.isEmpty

            for f in agentFiles {
                guard let aid = agentId(fromFile: f.lastPathComponent) else { continue }
                let entries = Transcript.parse(f)
                let metaURL = wfSubdir.appendingPathComponent("agent-\(aid).meta.json")
                let meta = (try? Data(contentsOf: metaURL)).flatMap { try? dec.decode(AgentMeta.self, from: $0) }
                let agentType = meta?.agentType ?? "agent"
                let model = Transcript.lastModel(entries)
                let tokens = Transcript.dedupTokens(entries)
                let dates = entries.compactMap { $0.date }
                let finished = notifiedDone.contains(aid) || Transcript.isFinished(entries)
                let status: SessionStatus = finished ? .done : (sessionLive ? .busy : .done)
                let end: Date? = status == .done ? dates.max() : nil
                let label = meta?.description.map { String($0.prefix(48)) } ?? agentType
                aggregateTokens += tokens
                if status != .done { allDone = false }
                children.append(AgentNode(
                    id: aid, parentId: wfId,
                    label: label.isEmpty ? agentType : label,
                    agentType: agentType, model: model, status: status,
                    tokens: tokens, start: dates.min(), end: end,
                    tools: countTools(entries), prompt: meta?.description ?? "",
                    actions: actionStream(entries, live: status == .busy)))
            }

            let wfStatus: SessionStatus = allDone ? .done : (sessionLive ? .busy : .done)
            let wfEnd: Date? = wfStatus == .done ? children.compactMap(\.end).max() : nil
            result.append(AgentNode(
                id: wfId, parentId: "root",
                label: scriptName, agentType: "workflow", model: "",
                status: wfStatus, tokens: aggregateTokens,
                start: wfStart, end: wfEnd, tools: ToolStats(), prompt: "",
                actions: []))
            result += children
        }
        return result
    }

    /// Number of sub-agents currently active (busy) for a live session.
    static func activeCount(_ agents: [AgentNode]) -> Int {
        agents.filter { $0.id != "root" && $0.status == .busy }.count
    }
}
