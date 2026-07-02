import SwiftUI
import Observation

enum Route: Hashable { case active, stats, history, pricing, detail, settings }

@MainActor
@Observable
final class AppState {
    // Navigation
    var route: Route = .active
    var detailFrom: Route = .active
    var selectedSessionId: String?
    var selectedNodeId: String? = "root"

    // Data
    // didSet → recomputeStats(): `stats` is stored, refreshed only when an input changes.
    var active: [SessionSummary] = [] { didSet { recomputeStats() } }
    var history: [SessionSummary] = [] { didSet { recomputeStats() } }
    var historyLoading = false
    var detail: SessionDetail?
    var detailLoadAttempted = false

    // UI
    var historySearch = ""
    var historyPeriod = -1           // -1=sem, -2=mois, -3=an, 0=tout
    var statsPeriod = -1 { didSet { recomputeStats() } }   // -1=sem, -2=mois, -3=an, 0=tout
    var statsProject = "all" { didSet { recomputeStats() } }
    var statsModel = "all" { didSet { recomputeStats() } }
    var loadedSince: Date?          // history scan cutoff currently loaded (nil = everything)
    var toast: String?
    var settings: AppSettings { didSet { recomputeStats() } }
    var pricing: PricingTable { didSet { recomputeStats() } }

    private var lastStatus: [String: SessionStatus] = [:]
    private var detailFingerprint: String?   // last loaded detail's mtime signature
    private var watcher: Watcher?
    private var toastWork: DispatchWorkItem?
    private var booted = false

    // Git-remote project grouping: cwd → normalized remote (or "" = no remote).
    var gitRemotes: [String: String] = [:] { didSet { recomputeStats() } }
    private let remoteCache = GitRemoteCache()

    init() {
        settings = .load()
        pricing = .load()
        route = Self.defaultRoute(for: settings.startTab)
        historyPeriod = settings.defaultPeriod
        statsPeriod = settings.defaultPeriod
        gitRemotes = remoteCache.map   // warm start: no git calls for known cwds
        #if DEBUG
        pricingResolveSelfCheck()
        #endif
    }

    // MARK: Project identity (git-remote grouping)

    /// Grouping key for a session — normalized remote when enabled & known, else cwd.
    func projectKey(_ s: SessionSummary) -> String {
        ProjectIdentity.key(cwd: s.cwd, remotes: gitRemotes, enabled: settings.groupByGitRemote)
    }

    /// Display label for a session's project (short repo name or `~`-collapsed path).
    func projectLabel(_ s: SessionSummary) -> String {
        ProjectIdentity.label(forKey: projectKey(s))
    }

    /// Probe git remotes for any not-yet-cached cwds in the background, then merge
    /// into `gitRemotes` (reactive re-render). No-op unless the feature is enabled.
    func resolveRemotes() {
        guard settings.groupByGitRemote else { return }
        let unknown = Set((active + history).map(\.cwd)).filter { !$0.isEmpty && remoteCache.map[$0] == nil }
        guard !unknown.isEmpty else { return }
        Task.detached(priority: .utility) { [weak self] in
            var found: [String: String] = [:]
            for cwd in unknown {
                let raw = GitRemote.remote(forCwd: cwd) ?? ""
                found[cwd] = raw.isEmpty ? "" : GitRemote.normalize(raw)
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                for (k, v) in found { self.remoteCache.put(k, v) }
                self.remoteCache.save()
                self.gitRemotes.merge(found) { _, new in new }
            }
        }
    }

    private static func defaultRoute(for tab: StartTab) -> Route {
        switch tab {
        case .active:  return .active
        case .stats:   return .stats
        case .history: return .history
        }
    }

    // MARK: Derived

    var theme: Theme { settings.appearance == .dark ? .dark : .light }
    var attendCards: [SessionSummary] { active.filter { $0.status == .idle } }
    var busyCards: [SessionSummary] { active.filter { $0.status == .busy } }
    var attendCount: Int { attendCards.count }
    var busyCount: Int { busyCards.count }
    var liveCount: Int { active.count }
    var historyCount: Int { history.count }

    var filteredHistory: [SessionSummary] {
        let cut = Self.periodStart(historyPeriod, weekStartDay: settings.weekStartDay)
        let q = historySearch.trimmingCharacters(in: .whitespaces).lowercased()
        return history.filter {
            $0.startedAt >= cut &&
            (q.isEmpty
             || $0.title.lowercased().contains(q)
             || $0.cwd.lowercased().contains(q)
             || projectLabel($0).lowercased().contains(q)
             || $0.branch.lowercased().contains(q)
             || $0.model.lowercased().contains(q))
        }
    }

    /// Period presets shared by the dashboard + history segmented controls.
    static let periodOptions: [(label: String, value: Int)] = [("Sem.", -1), ("Mois", -2), ("Année", -3), ("Tout", 0)]

    /// Cutoff date for a period in days (0 = tout → distantPast).
    static func cutoff(_ days: Int, now: Date = Date()) -> Date {
        days > 0 ? now.addingTimeInterval(-Double(days) * 86_400) : .distantPast
    }

    static func periodStart(_ period: Int, weekStartDay: Int = 2, now: Date = Date()) -> Date {
        switch period {
        case -1:
            var c = Calendar(identifier: .gregorian)
            c.firstWeekday = weekStartDay
            return c.dateInterval(of: .weekOfYear, for: now)?.start ?? now.addingTimeInterval(-7 * 86_400)
        case -2:
            return Calendar.current.dateInterval(of: .month, for: now)?.start ?? now.addingTimeInterval(-30 * 86_400)
        case -3:
            return Calendar.current.dateInterval(of: .year, for: now)?.start ?? now.addingTimeInterval(-365 * 86_400)
        default:
            return period > 0 ? now.addingTimeInterval(-Double(period) * 86_400) : .distantPast
        }
    }

    func cost(_ t: TokenBuckets, _ model: String) -> (cost: Double, missing: Bool) {
        pricing.cost(t, model: model)
    }

    /// Aggregated dashboard data — STORED, not recomputed on each access. StatsView reads it
    /// ~9× per body pass; rebuild only when an input changes (didSet hooks above + StatsView
    /// .onAppear) and only while the dashboard is visible.
    private(set) var stats = StatsData()

    func recomputeStats() {
        guard route == .stats else { return }   // only the dashboard reads `stats`
        stats = StatsData.build(active: active, history: history,
                                period: statsPeriod, project: statsProject, model: statsModel,
                                pricing: pricing, theme: theme, lang: settings.language,
                                groupByRemote: settings.groupByGitRemote, remotes: gitRemotes,
                                weekStartDay: settings.weekStartDay)
    }

    // MARK: Lifecycle

    func start() {
        guard !booted else { return }
        booted = true
        Notifier.shared.onOpenSession = { [weak self] id in self?.openSession(id) }
        Notifier.shared.bootstrap()
        watcher = Watcher { [weak self] in self?.onFSChange() }
        watcher?.start()
        refreshActive()
        switch settings.defaultPeriod {
        case -3, 0: loadedSince = nil
        case -2:    loadedSince = Self.cutoff(62)
        case -1:    loadedSince = Self.cutoff(14)
        default:    loadedSince = Self.cutoff(max(90, settings.defaultPeriod))
        }
        loadHistory()
    }

    private func onFSChange() {
        refreshActive()
        loadHistory()
        if route == .detail, let id = selectedSessionId { loadDetail(id) }
    }

    // MARK: Loading

    func refreshActive() {
        Task.detached(priority: .userInitiated) {
            let list = SessionStore.listActive()
            await MainActor.run { [weak self] in self?.applyActive(list) }
        }
    }

    private func applyActive(_ list: [SessionSummary]) {
        for s in list {
            if lastStatus[s.id] == .busy && s.status == .idle {
                Notifier.shared.notifyIdle(sessionId: s.id, title: displayTitle(s),
                                           enabled: settings.notificationsEnabled,
                                           sound: settings.notificationSound,
                                           lang: settings.language)
            }
        }
        lastStatus = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0.status) })
        active = list
        resolveRemotes()
    }

    func loadHistory() {
        historyLoading = true
        let since = loadedSince
        let pricing = pricing
        Task.detached(priority: .utility) {
            let cache = HistoryCache()
            let liveIds = Set(Registry.liveSessions().map { $0.sessionId })
            let list = SessionStore.listHistory(liveIds: liveIds, cache: cache, since: since, pricing: pricing)
            await MainActor.run { [weak self] in
                self?.history = list
                self?.historyLoading = false
                self?.resolveRemotes()
            }
        }
    }

    /// Widen the loaded scan window if a period needs more than what's loaded, then reload.
    private func ensureLoaded(_ period: Int) {
        let effective: Int
        switch period {
        case -1: effective = 14   // 2 semaines pour comparaison semaine précédente
        case -2: effective = 62   // 2 mois
        case -3, 0: effective = 0 // tout charger
        default: effective = period
        }
        let need: Date = effective > 0 ? Self.cutoff(effective) : .distantPast
        if need < (loadedSince ?? .distantPast) {
            loadedSince = effective > 0 ? need : nil
            loadHistory()
        }
    }

    func setHistoryPeriod(_ days: Int) { historyPeriod = days; ensureLoaded(days) }
    func setStatsPeriod(_ days: Int)   { statsPeriod = days; ensureLoaded(days) }

    func loadDetail(_ id: String, force: Bool = false) {
        let known = force ? nil : detailFingerprint
        let lang = settings.language
        let pricing = pricing
        Task.detached(priority: .userInitiated) {
            let fp = SessionStore.detailFingerprint(sessionId: id)
            if let known, fp == known { return }   // unchanged → no reparse, no re-render
            let d = SessionStore.detail(sessionId: id, lang: lang, pricing: pricing)
            await MainActor.run { [weak self] in
                self?.detail = d
                self?.detailFingerprint = fp
                self?.detailLoadAttempted = true
            }
        }
    }

    // MARK: Navigation

    func go(_ r: Route) { route = r; recomputeStats() }   // refresh dashboard on entry (guarded inside)

    func openSession(_ id: String) {
        detailFrom = (route == .history) ? .history : .active
        selectedSessionId = id
        selectedNodeId = "root"
        detail = nil
        detailLoadAttempted = false
        detailFingerprint = nil
        route = .detail
        loadDetail(id, force: true)
    }

    func goBack() {
        route = detailFrom
        recomputeStats()   // dashboard may have gone stale while in detail
        detail = nil
        detailLoadAttempted = false
        detailFingerprint = nil
        selectedSessionId = nil
    }

    // MARK: Settings & pricing

    func toggleTheme() {
        settings.appearance = theme.isDark ? .light : .dark
        persistSettings()
    }

    func setNotifications(_ on: Bool) {
        settings.notificationsEnabled = on
        persistSettings()
    }

    func setNotificationSound(_ on: Bool) {
        settings.notificationSound = on
        persistSettings()
    }

    func setAppearance(_ mode: AppearanceMode) {
        settings.appearance = mode
        persistSettings()
    }

    func setStartTab(_ tab: StartTab) {
        settings.startTab = tab
        persistSettings()
    }

    func setDefaultPeriod(_ days: Int) {
        settings.defaultPeriod = days
        persistSettings()
    }

    func setLanguage(_ lang: Language) {
        settings.language = lang
        persistSettings()
        // Views re-render reactively, but the parsed detail/timeline labels are
        // baked at parse time → re-parse the open one so they switch too.
        if route == .detail, let id = selectedSessionId { loadDetail(id, force: true) }
    }

    func setGroupByGitRemote(_ on: Bool) {
        settings.groupByGitRemote = on
        persistSettings()
        resolveRemotes()   // enabling kicks off detection; disabling is instant (key == cwd)
    }

    func setWeekStartDay(_ day: Int) {
        settings.weekStartDay = day
        persistSettings()
    }

    /// Forget cached remotes and re-probe — for the rare case a project's remote changed.
    func redetectProjects() {
        remoteCache.clear()
        remoteCache.save()
        gitRemotes = [:]
        resolveRemotes()
        showToast(t("Project detection refreshed"))
    }

    /// Re-pick the IDE used by the "IDE" button (global, all sessions).
    func chooseEditor() {
        guard let url = SystemActions.chooseApplication(lang: settings.language) else { return }
        settings.editorAppPath = url.path
        persistSettings()
        showToast(t("IDE: %@", url.deletingPathExtension().lastPathComponent))
    }

    /// Forget the chosen IDE — the next "IDE" click prompts again.
    func clearEditor() {
        settings.editorAppPath = nil
        persistSettings()
        showToast(t("IDE reset"))
    }

    func resetSettings() {
        settings = AppSettings()
        persistSettings()
        showToast(t("Settings reset"))
    }

    func revealSettingsFile() { SystemActions.reveal(Paths.settingsFile) }

    func savePricing() {
        if !pricing.save() { showToast(t("Could not save pricing")) }
    }

    func resetPricing() {
        pricing = .defaults
        if !pricing.save() { showToast(t("Could not save pricing")) }
    }

    /// Surfaces a failed settings write (losing user edits silently is the one write worth
    /// reporting — the cache is self-healing, so its `try?` stays). Reuses the toast.
    private func persistSettings() {
        if !settings.save() { showToast(t("Could not save settings")) }
    }

    /// Localizes a session title at display time. Command sessions store the raw command name
    /// (the "Command" prefix is NOT baked in at parse → stays correct when language changes).
    func displayTitle(_ s: SessionSummary) -> String {
        s.titleIsCommand ? t("Command %@", s.title) : s.title
    }

    // MARK: Toast

    func showToast(_ s: String) {
        toast = s
        toastWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.toast = nil }
        toastWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4, execute: w)
    }

    // MARK: Session actions

    func copySessionID(_ id: String) {
        SystemActions.copy(id)
        showToast(t("ID copied"))
    }

    func revealInFinder(cwd: String) {
        if !SystemActions.revealInFinder(path: cwd) {
            showToast(t("Folder not found"))
        }
    }

    func resumeSession(id: String, cwd: String, live: Bool) {
        guard !live else { showToast(t("Session already active")); return }
        if !SystemActions.resume(sessionId: id, cwd: cwd) {
            showToast(t("Project folder not found"))
        }
    }

    func terminateSession(pid: Int?) {
        guard let pid, SystemActions.terminate(pid: pid) else {
            showToast(t("Session already ended"))
            return
        }
        refreshActive()   // FSEvents also fires when claude drops its registry file
    }

    func openInEditor(cwd: String) {
        guard !cwd.isEmpty else { showToast(t("Folder not found")); return }
        if let path = settings.editorAppPath, FileManager.default.fileExists(atPath: path) {
            SystemActions.open(path: cwd, withAppAt: URL(fileURLWithPath: path))
            return
        }
        guard let appURL = SystemActions.chooseApplication(lang: settings.language) else { return }
        settings.editorAppPath = appURL.path
        persistSettings()
        SystemActions.open(path: cwd, withAppAt: appURL)
    }
}
