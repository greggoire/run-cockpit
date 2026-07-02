import SwiftUI

struct HistoryView: View {
    @Environment(AppState.self) private var app
    @Environment(\.theme) private var theme

    var body: some View {
        @Bindable var app = app
        VStack(spacing: 0) {
            header(app: $app)
            content
        }
        .background(theme.bg)
    }

    private func header(app: Bindable<AppState>) -> some View {
        HStack(spacing: 12) {
            Text(app.wrappedValue.t("History")).font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.text)
            Spacer()
            SegmentedControl(options: AppState.periodOptions, selection: app.wrappedValue.historyPeriod) {
                app.wrappedValue.setHistoryPeriod($0)
            }
            HStack(spacing: 8) {
                Text("⌕").foregroundStyle(theme.text3)
                TextField(app.wrappedValue.t("Search title, project, branch…"), text: app.historySearch)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
            }
            .padding(.horizontal, 11).padding(.vertical, 6)
            .frame(maxWidth: 320)
            .background(RoundedRectangle(cornerRadius: 9).fill(theme.bg2))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(theme.border, lineWidth: 1))
        }
        .frame(height: 54)
        .padding(.horizontal, 28)
        .background(theme.panel)
        .overlay(alignment: .bottom) { theme.border2.frame(height: 1) }
    }

    @ViewBuilder
    private var content: some View {
        if app.historyLoading && app.history.isEmpty {
            VStack {
                Spacer()
                Text(app.t("Computing history…")).foregroundStyle(theme.text3)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let visible = app.filteredHistory   // compute once (was read 4× per render)
            ScrollView {
                LazyVStack(spacing: 0) {         // virtualize: don't build off-screen rows
                    headerRow
                    ForEach(visible) { s in
                        row(s)
                    }
                    footer(visible)
                }
                .frame(maxWidth: 1180)
                .frame(maxWidth: .infinity)
                .padding(.top, 18).padding(.horizontal, 28).padding(.bottom, 24)
            }
        }
    }

    // Shared 8-cell column layout.
    private func columns<Dot: View, Sess: View, Proj: View, Dt: View, Dur: View, Tok: View, Cost: View, Ag: View>(
        @ViewBuilder dot: () -> Dot,
        @ViewBuilder session: () -> Sess,
        @ViewBuilder projet: () -> Proj,
        @ViewBuilder date: () -> Dt,
        @ViewBuilder duree: () -> Dur,
        @ViewBuilder tokens: () -> Tok,
        @ViewBuilder cout: () -> Cost,
        @ViewBuilder agents: () -> Ag
    ) -> some View {
        HStack(spacing: 12) {
            dot().frame(width: 14, alignment: .center)
            session().frame(maxWidth: .infinity, alignment: .leading)
            projet().frame(width: 200, alignment: .leading)
            date().frame(width: 110, alignment: .leading)
            duree().frame(width: 70, alignment: .trailing)
            tokens().frame(width: 70, alignment: .trailing)
            cout().frame(width: 80, alignment: .trailing)
            agents().frame(width: 56, alignment: .trailing)
        }
    }

    private var headerRow: some View {
        columns(
            dot: { Text("") },
            session: { SectionLabel(text: app.t("Session"), color: theme.text3) },
            projet: { SectionLabel(text: app.t("Project · branch"), color: theme.text3) },
            date: { SectionLabel(text: app.t("Date"), color: theme.text3) },
            duree: { SectionLabel(text: app.t("Duration"), color: theme.text3) },
            tokens: { SectionLabel(text: app.t("Tokens"), color: theme.text3) },
            cout: { SectionLabel(text: app.t("Cost"), color: theme.text3) },
            agents: { SectionLabel(text: app.t("Agents"), color: theme.text3) }
        )
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { theme.border.frame(height: 1) }
    }

    private func row(_ s: SessionSummary) -> some View {
        let c = app.cost(s.tokens, s.model)
        return columns(
            dot: { Circle().fill(theme.stDone).frame(width: 7, height: 7) },
            session: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.displayTitle(s)).font(.system(size: 12.5, weight: .medium)).foregroundStyle(theme.text)
                        .lineLimit(1).truncationMode(.tail)
                    Text(app.pricing.modelLabel(s.model)).font(.system(size: 10.5)).foregroundStyle(theme.text3)
                }
            },
            projet: {
                VStack(alignment: .leading) {
                    Text(app.projectLabel(s)).font(.system(size: 11, design: .monospaced)).foregroundStyle(theme.text2)
                        .lineLimit(1).truncationMode(.middle)
                    Text(s.branch).font(.system(size: 10, design: .monospaced)).foregroundStyle(theme.text3)
                }
            },
            date: { Text(Fmt.dateTime(s.startedAt)).font(.system(size: 11.5)).foregroundStyle(theme.text2) },
            duree: {
                Text(Fmt.duration(s.endedAt.map { ($0.timeIntervalSince(s.startedAt)) * 1000 }))
                    .font(.system(size: 11.5)).monospacedDigit().foregroundStyle(theme.text2)
            },
            tokens: { Text(Fmt.tokens(s.tokens.total)).font(.system(size: 11.5)).monospacedDigit().foregroundStyle(theme.text2) },
            cout: {
                Text(c.missing ? "—" : Fmt.cost(c.cost)).font(.system(size: 11.5, weight: .medium))
                    .monospacedDigit().foregroundStyle(theme.text)
            },
            agents: { Text("\(s.agentCount)").font(.system(size: 11.5)).monospacedDigit().foregroundStyle(theme.text2) }
        )
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { theme.border2.frame(height: 1) }
        .contentShape(Rectangle())
        .onTapGesture { app.openSession(s.id) }
    }

    private func footer(_ visible: [SessionSummary]) -> some View {
        let totalTokens = visible.reduce(0) { $0 + $1.tokens.total }
        let totalCost = visible.reduce(0.0) { $0 + app.cost($1.tokens, $1.model).cost }
        return HStack(spacing: 28) {
            Spacer()
            Text(app.t("%d / %d sessions", visible.count, app.history.count)).foregroundStyle(theme.text2)
            (Text(app.t("Σ tokens ")).foregroundStyle(theme.text2)
                + Text(Fmt.tokens(totalTokens)).bold().foregroundColor(theme.text))
            (Text(app.t("Σ cost ")).foregroundStyle(theme.text2)
                + Text(Fmt.cost(totalCost)).bold().foregroundColor(theme.text))
        }
        .font(.system(size: 12))
        .padding(.top, 13)
        .overlay(alignment: .top) { theme.border.frame(height: 1) }
    }
}
