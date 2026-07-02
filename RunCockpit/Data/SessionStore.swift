import Foundation

/// Stateless IO orchestration: live list, history list, full detail.
/// All methods are blocking and meant to run off the main actor.
enum SessionStore {

    // MARK: Active (living) sessions

    static func listActive() -> [SessionSummary] {
        Registry.liveSessions().compactMap { reg -> SessionSummary? in
            let loc = Paths.locateTranscript(sessionId: reg.sessionId)
            let entries = loc.map { Transcript.parse($0.file) } ?? []
            let sum = Transcript.summarize(entries, fallback: reg.name ?? String(reg.sessionId.prefix(8)))

            var subActive = 0
            var subCount = 0
            if let loc {
                let subs = Agents.subAgents(projectDir: loc.projectDir, sessionId: reg.sessionId,
                                            parentEntries: entries, sessionLive: true)
                subActive = Agents.activeCount(subs)
                subCount = subs.count
            }
            var status: SessionStatus = (reg.status == "busy") ? .busy : .idle
            if subActive > 0 { status = .busy }     // PRD override: sub-agent actif renforce 🟢

            let lastActivity = max(reg.updatedDate, sum.lastDate ?? reg.updatedDate)

            return SessionSummary(
                id: reg.sessionId, pid: reg.pid, live: true, status: status,
                title: sum.title, titleIsCommand: sum.titleIsCommand, cwd: reg.cwd,
                branch: sum.branch, model: sum.model,
                startedAt: reg.startedDate, lastActivity: lastActivity, endedAt: nil,
                tours: sum.tours, subActive: subActive, tokens: sum.tokens, agentCount: subCount)
        }
    }

    // MARK: History (terminated) sessions

    /// `since` bounds the scan: uncached transcripts older than it (by mtime ≈ end time)
    /// are skipped entirely so we never parse history outside the requested period.
    static func listHistory(liveIds: Set<String>, cache: HistoryCache, since: Date? = nil, pricing: PricingTable) -> [SessionSummary] {
        var out: [SessionSummary] = []
        for dir in Paths.projectDirs() {
            for file in Paths.transcripts(in: dir) {
                let sessionId = file.deletingPathExtension().lastPathComponent
                guard Registry.isValidSessionId(sessionId) else { continue }  // O1/O4: untrusted filename → reject non-UUID before it reaches paths/shell
                if liveIds.contains(sessionId) { continue }      // active → not history
                let mtime = Paths.mtime(file)

                if let c = cache.get(sessionId, mtime: mtime) {
                    out.append(summary(from: c)); continue
                }
                if let since, mtime < since { continue }          // out of period → don't parse

                let entries = Transcript.parse(file)
                if entries.isEmpty { continue }
                let sum = Transcript.summarize(entries, fallback: String(sessionId.prefix(8)))
                let start = sum.firstDate ?? mtime
                let end = sum.lastDate ?? mtime
                let cached = CachedSummary(
                    sessionId: sessionId, mtime: mtime,
                    title: sum.title, titleIsCommand: sum.titleIsCommand,
                    cwd: sum.cwd.isEmpty ? dir.lastPathComponent : sum.cwd,
                    branch: sum.branch,
                    model: pricing.resolve(sum.model),
                    startedAt: start, endedAt: end, durationMs: end.timeIntervalSince(start) * 1000,
                    tokens: sum.tokens,
                    agentCount: agentFileCount(projectDir: dir, sessionId: sessionId),
                    tours: sum.tours)
                cache.put(cached)
                out.append(summary(from: cached))
            }
        }
        cache.save()
        return out.sorted { $0.startedAt > $1.startedAt }
    }

    private static func summary(from c: CachedSummary) -> SessionSummary {
        SessionSummary(
            id: c.sessionId, pid: nil, live: false, status: .done,
            title: c.title, titleIsCommand: c.titleIsCommand ?? false, cwd: c.cwd, branch: c.branch, model: c.model,
            startedAt: c.startedAt, lastActivity: c.endedAt ?? c.startedAt, endedAt: c.endedAt,
            tours: c.tours, subActive: 0, tokens: c.tokens, agentCount: c.agentCount)
    }

    /// Cheap change-detector for a session detail: mtimes of the transcript + agent
    /// files only, no parsing. Lets the live watcher skip a full reparse when nothing
    /// actually changed. ponytail.
    static func detailFingerprint(sessionId: String) -> String? {
        guard let loc = Paths.locateTranscript(sessionId: sessionId) else { return nil }
        var parts = [String(Paths.mtime(loc.file).timeIntervalSince1970)]
        let dir = Paths.subagentsDir(projectDir: loc.projectDir, sessionId: sessionId)
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        for f in files where f.lastPathComponent.hasPrefix("agent-") {
            parts.append(f.lastPathComponent + ":" + String(Paths.mtime(f).timeIntervalSince1970))
        }
        return parts.sorted().joined(separator: "|")
    }

    private static func agentFileCount(projectDir: URL, sessionId: String) -> Int {
        let dir = Paths.subagentsDir(projectDir: projectDir, sessionId: sessionId)
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return files.filter { $0.lastPathComponent.hasPrefix("agent-") && $0.pathExtension == "jsonl" }.count
    }

    // MARK: Full detail

    static func detail(sessionId: String, lang: Language, pricing: PricingTable) -> SessionDetail? {
        guard let loc = Paths.locateTranscript(sessionId: sessionId) else { return nil }
        let entries = Transcript.parse(loc.file)

        let live = Registry.liveSessions().first { $0.sessionId == sessionId }
        let isLive = live != nil
        let rootStatus: SessionStatus = isLive ? ((live?.status == "busy") ? .busy : .idle) : .done

        let sum = Transcript.summarize(entries, fallback: live?.name ?? String(sessionId.prefix(8)))
        let cwd = live?.cwd ?? (sum.cwd.isEmpty ? "" : sum.cwd)

        let root = AgentNode(
            id: "root", parentId: nil,
            label: sum.title, agentType: "orchestrating", model: isLive ? sum.model : pricing.resolve(sum.model), status: rootStatus,
            tokens: sum.tokens, start: sum.firstDate,
            end: (isLive && rootStatus == .busy) ? nil : sum.lastDate,
            tools: Agents.countTools(entries),
            prompt: sum.firstPrompt,
            actions: Agents.actionStream(entries, live: rootStatus == .busy))

        let subs = Agents.subAgents(projectDir: loc.projectDir, sessionId: sessionId,
                                    parentEntries: entries, sessionLive: isLive)
        let resolvedSubs = isLive ? subs : subs.map { var n = $0; n.model = pricing.resolve($0.model); return n }
        let agents = [root] + resolvedSubs

        let summary = SessionSummary(
            id: sessionId, pid: live?.pid, live: isLive, status: rootStatus,
            title: sum.title, titleIsCommand: sum.titleIsCommand, cwd: cwd,
            branch: sum.branch, model: isLive ? sum.model : pricing.resolve(sum.model),
            startedAt: sum.firstDate ?? Date(), lastActivity: sum.lastDate ?? Date(),
            endedAt: isLive ? nil : sum.lastDate,
            tours: sum.tours, subActive: Agents.activeCount(resolvedSubs), tokens: sum.tokens)

        return SessionDetail(summary: summary, agents: agents, timeline: timeline(agents, lang: lang))
    }

    /// Chronological events (ported from the mockup's buildTimeline).
    private static func timeline(_ agents: [AgentNode], lang: Language) -> [TimelineEvent] {
        guard let root = agents.first(where: { $0.parentId == nil }) else { return [] }
        var ev: [TimelineEvent] = []
        if let s = root.start { ev.append(TimelineEvent(time: s, kind: .start, label: tr("Session started", lang))) }
        for a in agents where a.parentId != nil {
            if let s = a.start {
                ev.append(TimelineEvent(time: s, kind: .spawn, label: tr("Sub-agent “%@” launched — %@", lang, [a.agentType, a.label])))
            }
            if a.status == .done, let e = a.end, let s = a.start {
                ev.append(TimelineEvent(time: e, kind: .done, label: tr("%@ finished", lang, [a.label]), durationMs: e.timeIntervalSince(s) * 1000))
            } else if a.status != .done {
                ev.append(TimelineEvent(time: Date(), kind: .active, label: tr("%@ in progress…", lang, [a.label])))
            }
        }
        return ev.sorted { $0.time < $1.time }
    }
}
