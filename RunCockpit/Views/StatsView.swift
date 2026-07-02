import SwiftUI

// MARK: - Aggregated dashboard data (ported from the mockup's buildStats)

struct StatsData {
    struct KPI: Identifiable { let id = UUID(); let label, value, sub: String; let subColor: Color }
    struct DayBar: Identifiable { let id = UUID(); let frac: Double; let hasCost: Bool; let title: String }
    struct Bucket: Identifiable { let id = UUID(); let label, val, pct: String; let color: Color; let frac: Double }
    struct ModelRow: Identifiable { let id = UUID(); let label, nStr, costStr: String; let frac: Double }
    struct ProjectRow: Identifiable { let id = UUID(); let label, pct, costStr: String; let frac: Double }
    struct TopSession: Identifiable { let id: String; let title, project, tokensStr, costStr: String; let dotColor: Color }
    struct Opt: Identifiable { let id: String; let label: String }

    var sessionCount = 0
    var periodDays = 30
    var kpis: [KPI] = []
    var dayBars: [DayBar] = []
    var dayGap: CGFloat = 4
    var dayAxisOld = ""
    var dayAxisNew = ""
    var dayBarsLabel = ""
    var buckets: [Bucket] = []          // doubles as stacked segments + legend
    var modelRows: [ModelRow] = []
    var projectRows: [ProjectRow] = []
    var topSessions: [TopSession] = []
    var projectOptions: [Opt] = []
    var modelOptions: [Opt] = []

    static func build(active: [SessionSummary], history: [SessionSummary],
                      period: Int, project: String, model: String,
                      pricing: PricingTable, theme: Theme, lang: Language,
                      groupByRemote: Bool = false, remotes: [String: String] = [:],
                      weekStartDay: Int = 2,
                      now: Date = Date()) -> StatsData {
        func L(_ k: String, _ a: CVarArg...) -> String { tr(k, lang, a) }
        func pkey(_ s: SessionSummary) -> String {
            ProjectIdentity.key(cwd: s.cwd, remotes: remotes, enabled: groupByRemote)
        }
        let day = 86_400.0
        let all = active + history
        let todayStart = Calendar.current.startOfDay(for: now)
        func di(_ d: Date) -> Int {
            Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: d), to: todayStart).day ?? 0
        }
        func match(_ s: SessionSummary) -> Bool {
            (project == "all" || pkey(s) == project) && (model == "all" || Fmt.alias(s.model) == model)
        }
        func c(_ s: SessionSummary) -> Double { pricing.cost(s.tokens, model: s.model).cost }

        var cur: [SessionSummary]
        var prev: [SessionSummary]
        var periodStartDate: Date
        switch period {
        case -1:
            var cal = Calendar(identifier: .gregorian)
            cal.firstWeekday = weekStartDay
            let weekStart = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now.addingTimeInterval(-7 * day)
            let prevWeekStart = weekStart.addingTimeInterval(-7 * day)
            cur  = all.filter { $0.startedAt >= weekStart && $0.startedAt <= now && match($0) }
            prev = all.filter { $0.startedAt >= prevWeekStart && $0.startedAt < weekStart && match($0) }
            periodStartDate = weekStart
        case -2:
            let cal = Calendar.current
            let mStart = cal.dateInterval(of: .month, for: now)?.start ?? now.addingTimeInterval(-30 * day)
            let prevMStart = cal.date(byAdding: .month, value: -1, to: mStart) ?? mStart.addingTimeInterval(-30 * day)
            cur  = all.filter { $0.startedAt >= mStart && $0.startedAt <= now && match($0) }
            prev = all.filter { $0.startedAt >= prevMStart && $0.startedAt < mStart && match($0) }
            periodStartDate = mStart
        case -3:
            let cal = Calendar.current
            let yStart = cal.dateInterval(of: .year, for: now)?.start ?? now.addingTimeInterval(-365 * day)
            let prevYStart = cal.date(byAdding: .year, value: -1, to: yStart) ?? yStart.addingTimeInterval(-365 * day)
            cur  = all.filter { $0.startedAt >= yStart && $0.startedAt <= now && match($0) }
            prev = all.filter { $0.startedAt >= prevYStart && $0.startedAt < yStart && match($0) }
            periodStartDate = yStart
        default: // 0 = Tout
            cur  = all.filter { match($0) }
            prev = []
            periodStartDate = .distantPast
        }
        // Jours écoulés depuis le début de la période (inclusif) — évite les barres vides trompeuses
        let periodDays: Int
        if periodStartDate != .distantPast {
            let elapsed = Calendar.current.dateComponents([.day], from: periodStartDate, to: now).day ?? 0
            periodDays = max(1, elapsed + 1)
        } else {
            periodDays = 90
        }

        var d = StatsData()
        d.periodDays = periodDays
        d.sessionCount = cur.count

        let totalCost = cur.reduce(0.0) { $0 + c($1) }
        let prevCost  = prev.reduce(0.0) { $0 + c($1) }
        let totalTok  = cur.reduce(0) { $0 + $1.tokens.total }
        let agentCount = cur.reduce(0) { $0 + $1.agentCount }
        let avgCost = cur.isEmpty ? 0 : totalCost / Double(cur.count)

        var deltaSub = L("over the period"); var deltaColor = theme.text3
        if period != 0 && prevCost > 0 {
            let dp = (totalCost - prevCost) / prevCost * 100
            deltaSub = (dp >= 0 ? "▲ +" : "▼ ") + String(format: "%.0f", abs(dp)) + L("% vs prev.")
            deltaColor = dp >= 0 ? theme.stIdle : theme.stBusy
        }
        d.kpis = [
            .init(label: L("Total cost"), value: Fmt.cost(totalCost), sub: deltaSub, subColor: deltaColor),
            .init(label: "Tokens", value: Fmt.tokens(totalTok), sub: Fmt.cost(avgCost) + " / session", subColor: theme.text3),
            .init(label: "Sessions", value: "\(cur.count)",
                  sub: String(format: "%.1f", Double(cur.count) / Double(periodDays)) + L(" / day"), subColor: theme.text3),
            .init(label: L("Sub-agents launched"), value: "\(agentCount)",
                  sub: cur.isEmpty ? "—" : String(format: "%.1f", Double(agentCount) / Double(cur.count)) + " / session",
                  subColor: theme.text3),
        ]

        // Bar chart: toujours la période complète (jours futurs = barres vides)
        let barFmt = DateFormatter()
        barFmt.locale = Locale(identifier: lang.rawValue)
        if period == -3 {
            // ANNÉE — 12 barres fixes, label droit = Déc (pas le mois courant)
            let cal = Calendar.current
            var perMonth = [Double](repeating: 0, count: 12)
            for s in cur {
                let m = cal.component(.month, from: s.startedAt) - 1
                if m >= 0 && m < 12 { perMonth[m] += c(s) }
            }
            let maxC = max(0.0001, perMonth.max() ?? 0)
            barFmt.dateFormat = "MMM"
            let monthNames: [String] = (0..<12).map { i in
                var comps = DateComponents()
                comps.year = cal.component(.year, from: now); comps.month = i + 1; comps.day = 1
                return barFmt.string(from: cal.date(from: comps) ?? now)
            }
            d.dayBars      = perMonth.enumerated().map { i, cost in
                .init(frac: cost / maxC, hasCost: cost > 0, title: monthNames[i] + " – " + Fmt.cost(cost))
            }
            d.dayGap       = 10
            d.dayBarsLabel = L("Cost per month")
            d.dayAxisOld   = monthNames[0]
            d.dayAxisNew   = monthNames[11]
        } else if period == -1 || period == -2 {
            // SEMAINE (7 barres) ou MOIS (tous les jours) — indexation en avant depuis début de période
            let totalBars = period == -1 ? 7 : (Calendar.current.range(of: .day, in: .month, for: now)?.count ?? 30)
            func fwd(_ d: Date) -> Int {
                Calendar.current.dateComponents([.day],
                    from: Calendar.current.startOfDay(for: periodStartDate),
                    to: Calendar.current.startOfDay(for: d)).day ?? -1
            }
            var perDay = [Double](repeating: 0, count: totalBars)
            for s in cur { let i = fwd(s.startedAt); if i >= 0 && i < totalBars { perDay[i] += c(s) } }
            let maxC   = max(0.0001, perDay.max() ?? 0)
            barFmt.dateFormat = "dd MMM"
            d.dayBars      = perDay.enumerated().map { i, cost in
                let date = Calendar.current.date(byAdding: .day, value: i, to: periodStartDate) ?? periodStartDate
                return .init(frac: cost / maxC, hasCost: cost > 0, title: barFmt.string(from: date) + "  " + Fmt.cost(cost))
            }
            d.dayGap       = totalBars > 14 ? 4 : 10
            d.dayBarsLabel = L("Cost per day")
            d.dayAxisOld   = barFmt.string(from: periodStartDate)
            d.dayAxisNew   = barFmt.string(from: Calendar.current.date(byAdding: .day, value: totalBars - 1, to: periodStartDate) ?? now)
        } else {
            // TOUT — regroupement adaptatif selon la plage totale de données
            let cal       = Calendar.current
            let firstDate = cur.map { $0.startedAt }.min() ?? now
            let rangeDays = max(1, (cal.dateComponents([.day],
                from: cal.startOfDay(for: firstDate),
                to: cal.startOfDay(for: now)).day ?? 0) + 1)
            barFmt.dateFormat = "dd MMM"
            if rangeDays <= 60 {
                // Journalier
                var perDay = [Double](repeating: 0, count: rangeDays)
                for s in cur { let i = di(s.startedAt); if i >= 0 && i < rangeDays { perDay[i] += c(s) } }
                let series = Array(perDay.reversed())
                let maxC   = max(0.0001, series.max() ?? 0)
                d.dayBars      = series.enumerated().map { i, cost in
                    let daysAgo = rangeDays - 1 - i
                    let date = cal.date(byAdding: .day, value: -daysAgo, to: now) ?? now
                    return .init(frac: cost / maxC, hasCost: cost > 0, title: barFmt.string(from: date) + "  " + Fmt.cost(cost))
                }
                d.dayGap       = rangeDays > 14 ? 4 : 10
                d.dayBarsLabel = L("Cost per day")
                d.dayAxisOld   = barFmt.string(from: firstDate)
                d.dayAxisNew   = L("today")
            } else if rangeDays <= 730 {
                // Hebdomadaire
                let weekCount = rangeDays / 7 + 1
                var perWeek   = [Double](repeating: 0, count: weekCount)
                func wIdx(_ d: Date) -> Int {
                    let off = (cal.dateComponents([.day],
                        from: cal.startOfDay(for: firstDate),
                        to: cal.startOfDay(for: d)).day ?? -1)
                    return off >= 0 ? off / 7 : -1
                }
                for s in cur { let i = wIdx(s.startedAt); if i >= 0 && i < weekCount { perWeek[i] += c(s) } }
                let maxC   = max(0.0001, perWeek.max() ?? 0)
                d.dayBars      = perWeek.enumerated().map { i, cost in
                    let weekStart = cal.date(byAdding: .day, value: i * 7, to: firstDate) ?? firstDate
                    return .init(frac: cost / maxC, hasCost: cost > 0, title: barFmt.string(from: weekStart) + "  " + Fmt.cost(cost))
                }
                d.dayGap       = weekCount > 26 ? 7 : 10
                d.dayBarsLabel = L("Cost per week")
                d.dayAxisOld   = barFmt.string(from: firstDate)
                d.dayAxisNew   = L("today")
            } else {
                // Mensuel
                let monthCount = max(1, (cal.dateComponents([.month], from: firstDate, to: now).month ?? 0) + 1)
                var perMonth   = [Double](repeating: 0, count: monthCount)
                for s in cur {
                    let diff = cal.dateComponents([.month], from: firstDate, to: s.startedAt).month ?? -1
                    if diff >= 0 && diff < monthCount { perMonth[diff] += c(s) }
                }
                let maxC   = max(0.0001, perMonth.max() ?? 0)
                barFmt.dateFormat = "MMM yy"
                d.dayBars      = perMonth.enumerated().map { i, cost in
                    let monthStart = cal.date(byAdding: .month, value: i, to: firstDate) ?? firstDate
                    return .init(frac: cost / maxC, hasCost: cost > 0, title: barFmt.string(from: monthStart) + "  " + Fmt.cost(cost))
                }
                d.dayGap       = 10
                d.dayBarsLabel = L("Cost per month")
                d.dayAxisOld   = barFmt.string(from: firstDate)
                d.dayAxisNew   = L("today")
            }
        }

        // Répartition des tokens
        var bi = 0, bo = 0, bw = 0, br = 0
        for s in cur {
            bi += s.tokens.input; bo += s.tokens.output
            bw += s.tokens.cacheWrite5m + s.tokens.cacheWrite1h; br += s.tokens.cacheRead
        }
        let bt = Double(max(1, bi + bo + bw + br))
        let bdefs: [(String, Int, Color)] = [
            (L("Input"), bi, theme.accent), (L("Output"), bo, theme.stBusy),
            (L("Cache write"), bw, theme.stIdle), (L("Cache read"), br, theme.text3),
        ]
        d.buckets = bdefs.map { def in
            let pct = Double(def.1) / bt * 100
            return .init(label: def.0, val: Fmt.tokens(def.1),
                         pct: String(format: pct < 10 ? "%.1f" : "%.0f", pct) + "%",
                         color: def.2, frac: Double(def.1) / bt)
        }

        // Coût par modèle
        var mAgg: [String: (c: Double, n: Int)] = [:]
        for s in cur { let k = Fmt.alias(s.model); var v = mAgg[k] ?? (0, 0); v.c += c(s); v.n += 1; mAgg[k] = v }
        let mMax = max(0.0001, mAgg.values.map { $0.c }.max() ?? 0)
        d.modelRows = mAgg.sorted { $0.value.c > $1.value.c }.map {
            .init(label: pricing.modelLabel($0.key), nStr: "\($0.value.n) sess.",
                  costStr: Fmt.cost($0.value.c), frac: max(0.03, $0.value.c / mMax))
        }

        // Coût par projet
        var pAgg: [String: Double] = [:]
        for s in cur { pAgg[pkey(s), default: 0] += c(s) }
        let pMax = max(0.0001, pAgg.values.max() ?? 0)
        d.projectRows = pAgg.sorted { $0.value > $1.value }.map {
            .init(label: ProjectIdentity.label(forKey: $0.key),
                  pct: totalCost > 0 ? String(format: "%.0f", $0.value / totalCost * 100) + "%" : "0%",
                  costStr: Fmt.cost($0.value), frac: $0.value / pMax)
        }

        // Sessions les plus coûteuses
        d.topSessions = cur.map { ($0, c($0)) }.sorted { $0.1 > $1.1 }.prefix(5).map { pair in
            let s = pair.0
            let title = s.titleIsCommand ? tr("Command %@", lang, [s.title]) : s.title
            return .init(id: s.id, title: title, project: ProjectIdentity.label(forKey: pkey(s)),
                         tokensStr: Fmt.tokens(s.tokens.total), costStr: Fmt.cost(pair.1),
                         dotColor: theme.colors(s.status).main)
        }

        // Filtres
        d.projectOptions = [.init(id: "all", label: L("All projects"))]
            + Set(all.map { pkey($0) }).sorted().map { .init(id: $0, label: ProjectIdentity.label(forKey: $0)) }
        d.modelOptions = [.init(id: "all", label: L("All models"))]
            + Set(all.map { Fmt.alias($0.model) }).sorted().map { .init(id: $0, label: pricing.modelLabel($0)) }
        return d
    }
}

// MARK: - Dashboard view

struct StatsView: View {
    @Environment(AppState.self) private var app
    @Environment(\.theme) private var theme
    @State private var hoveredBar: Int? = nil

    private var s: StatsData { app.stats }

    var body: some View {
        VStack(spacing: 0) {
            header
            filterBar
            ScrollView {
                VStack(spacing: 18) {
                    kpiGrid
                    chartsRow
                    listsRow
                    topSessionsCard
                }
                .frame(maxWidth: 1180)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 28).padding(.top, 22).padding(.bottom, 40)
            }
        }
        .background(theme.bg)
        .onAppear { app.recomputeStats() }   // ensure fresh on entry regardless of nav path
    }

    private var header: some View {
        HStack {
            Text(app.t("Dashboard")).font(.system(size: 15, weight: .semibold)).tracking(-0.3).foregroundStyle(theme.text)
            Spacer()
            Text(app.t("%lld sessions over the period", s.sessionCount)).font(.system(size: 11.5)).foregroundStyle(theme.text2)
        }
        .frame(height: 54).padding(.horizontal, 28)
        .background(theme.panel)
        .overlay(alignment: .bottom) { theme.border2.frame(height: 1) }
    }

    private var filterBar: some View {
        @Bindable var app = app
        return HStack(spacing: 14) {
            Text(app.t("Period")).font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.text3)
            SegmentedControl(options: AppState.periodOptions, selection: app.statsPeriod) { app.setStatsPeriod($0) }
                .fixedSize()
            labeledSelect(app.t("Project"), selection: $app.statsProject, options: s.projectOptions, width: 200)
            labeledSelect(app.t("Model"), selection: $app.statsModel, options: s.modelOptions, width: 180)
            Spacer()
        }
        .padding(.horizontal, 28).frame(height: 48)
        .background(theme.panel2)
        .overlay(alignment: .bottom) { theme.border2.frame(height: 1) }
    }

    private func labeledSelect(_ label: String, selection: Binding<String>, options: [StatsData.Opt], width: CGFloat) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.text3)
            Picker("", selection: selection) {
                ForEach(options) { Text($0.label).tag($0.id) }
            }
            .labelsHidden().pickerStyle(.menu).tint(theme.text2)
            .frame(width: width)
        }
    }

    // MARK: cards

    private var kpiGrid: some View {
        HStack(spacing: 14) {
            ForEach(s.kpis) { k in
                VStack(alignment: .leading, spacing: 5) {
                    Text(k.label.uppercased()).font(.system(size: 11, weight: .bold)).tracking(0.4).foregroundStyle(theme.text3)
                    Text(k.value).font(.system(size: 25, weight: .bold)).monospacedDigit().tracking(-0.5).foregroundStyle(theme.text)
                    Text(k.sub).font(.system(size: 11.5)).foregroundStyle(k.subColor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(theme)
            }
        }
    }

    private var chartsRow: some View {
        // ponytail: fixed-height GeometryReader split ≈ mockup's 1.15/0.85.
        GeometryReader { g in
            let gap: CGFloat = 18
            HStack(spacing: gap) {
                costPerDayCard.frame(width: (g.size.width - gap) * 0.575)
                tokenBreakdownCard.frame(width: (g.size.width - gap) * 0.425)
            }
        }
        .frame(height: 214)
    }

    private var costPerDayCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: s.dayBarsLabel, color: theme.text3)
            ZStack(alignment: .top) {
                HStack(alignment: .bottom, spacing: s.dayGap) {
                    ForEach(Array(s.dayBars.enumerated()), id: \.offset) { i, b in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(hoveredBar == i
                                  ? theme.accent
                                  : (b.hasCost ? theme.accent.opacity(0.92) : theme.border.opacity(0.5)))
                            .frame(maxWidth: .infinity)
                            .frame(height: max(2, 150 * b.frac))
                            .onHover { hoveredBar = $0 ? i : nil }
                    }
                }
                if let idx = hoveredBar, idx < s.dayBars.count {
                    Text(s.dayBars[idx].title)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.text)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6)
                            .fill(theme.panel)
                            .shadow(color: .black.opacity(0.18), radius: 4, y: 1))
                        .fixedSize()
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 150).padding(.top, 8)
            HStack {
                Text(s.dayAxisOld); Spacer(); Text(s.dayAxisNew)
            }
            .font(.system(size: 10)).foregroundStyle(theme.text3).padding(.top, 6)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .card(theme)
    }

    private var tokenBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: app.t("Token breakdown"), color: theme.text3)
            GeometryReader { g in
                HStack(spacing: 0) {
                    ForEach(s.buckets) { seg in
                        Rectangle().fill(seg.color).frame(width: g.size.width * seg.frac)
                    }
                }
            }
            .frame(height: 14).clipShape(RoundedRectangle(cornerRadius: 4))
            VStack(spacing: 8) {
                ForEach(s.buckets) { b in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 3).fill(b.color).frame(width: 10, height: 10)
                        Text(b.label).font(.system(size: 11.5)).foregroundStyle(theme.text2)
                        Spacer()
                        Text(b.val).font(.system(size: 11.5, weight: .medium)).monospacedDigit().foregroundStyle(theme.text)
                        Text(b.pct).font(.system(size: 11)).monospacedDigit().foregroundStyle(theme.text3).frame(width: 42, alignment: .trailing)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .card(theme)
    }

    private var listsRow: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(text: app.t("Cost per model"), color: theme.text3)
                if s.modelRows.isEmpty { emptyLine } else {
                    ForEach(s.modelRows) { r in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.label).font(.system(size: 12.5, weight: .medium)).foregroundStyle(theme.text)
                                Text(r.nStr).font(.system(size: 10.5)).foregroundStyle(theme.text3)
                            }.frame(width: 120, alignment: .leading)
                            BarTrack(frac: r.frac, color: theme.accent)
                            Text(r.costStr).font(.system(size: 12.5, weight: .medium)).monospacedDigit()
                                .foregroundStyle(theme.text).frame(width: 70, alignment: .trailing)
                        }
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).card(theme)

            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(text: app.t("Cost per project"), color: theme.text3)
                if s.projectRows.isEmpty { emptyLine } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(s.projectRows) { r in
                                HStack(spacing: 12) {
                                    Text(r.label).font(.system(size: 11, design: .monospaced)).foregroundStyle(theme.text2)
                                        .lineLimit(1).truncationMode(.middle).frame(width: 150, alignment: .leading)
                                    BarTrack(frac: r.frac, color: theme.stBusy)
                                    Text(r.pct).font(.system(size: 11)).monospacedDigit().foregroundStyle(theme.text3).frame(width: 38, alignment: .trailing)
                                    Text(r.costStr).font(.system(size: 12.5, weight: .medium)).monospacedDigit()
                                        .foregroundStyle(theme.text).frame(width: 70, alignment: .trailing)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).card(theme)
        }
    }

    private var topSessionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: app.t("Most expensive sessions"), color: theme.text3)
            if s.topSessions.isEmpty { emptyLine } else {
                ForEach(s.topSessions) { t in
                    Button { app.openSession(t.id) } label: {
                        HStack(spacing: 12) {
                            Circle().fill(t.dotColor).frame(width: 7, height: 7)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.title).font(.system(size: 12.5, weight: .medium)).foregroundStyle(theme.text).lineLimit(1)
                                Text(t.project).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(theme.text3).lineLimit(1).truncationMode(.middle)
                            }
                            Spacer()
                            Text(t.tokensStr).font(.system(size: 11.5)).monospacedDigit().foregroundStyle(theme.text2).frame(width: 70, alignment: .trailing)
                            Text(t.costStr).font(.system(size: 12.5, weight: .semibold)).monospacedDigit().foregroundStyle(theme.text).frame(width: 70, alignment: .trailing)
                        }
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(theme)
    }

    private var emptyLine: some View {
        Text(app.t("No data for this period.")).font(.system(size: 12)).foregroundStyle(theme.text3).padding(.vertical, 6)
    }
}

// MARK: - Shared bits

/// Period segmented control (mockup `segBtn`), shared by dashboard + history.
struct SegmentedControl: View {
    @Environment(\.theme) private var theme
    let options: [(label: String, value: Int)]
    let selection: Int
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { o in
                let on = o.value == selection
                Button { onSelect(o.value) } label: {
                    Text(o.label).font(.system(size: 11.5, weight: .medium))
                        .lineLimit(1).fixedSize()
                        .foregroundStyle(on ? theme.text : theme.text2)
                        .padding(.horizontal, 11).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 7).fill(on ? theme.panel : .clear))
                        .overlay(on ? RoundedRectangle(cornerRadius: 7).stroke(theme.border, lineWidth: 1) : nil)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 9).fill(theme.bg2))
    }
}

private struct BarTrack: View {
    let frac: Double
    let color: Color
    @Environment(\.theme) private var theme
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.border)
                Capsule().fill(color).frame(width: max(3, g.size.width * min(1, frac)))
            }
        }.frame(height: 6)
    }
}

