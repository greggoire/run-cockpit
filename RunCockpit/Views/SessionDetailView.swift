import SwiftUI

enum BottomTab { case chrono, flux }

struct SessionDetailView: View {
    @Environment(AppState.self) private var app
    @Environment(\.theme) private var theme
    @State private var bottomTab: BottomTab = .chrono
    @State private var isExpanded: Bool = false

    var body: some View {
        if let detail = app.detail {
            content(detail)
        } else if !app.detailLoadAttempted {
            VStack(spacing: 0) {
                HStack {
                    Button("‹") { app.goBack() }
                        .buttonStyle(.plain)
                        .font(.system(size: 14))
                        .foregroundStyle(theme.text2)
                        .frame(width: 28, height: 28)
                        .background(RoundedRectangle(cornerRadius: 8).fill(theme.panel2))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border, lineWidth: 1))
                        .contentShape(Rectangle())
                        .padding(13)
                    Spacer()
                }
                Spacer()
                ProgressView()
                Text(app.t("Loading…"))
                    .font(.system(size: 13))
                    .foregroundStyle(theme.text2)
                    .padding(.top, 8)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.bg)
        } else {
            VStack(spacing: 0) {
                HStack {
                    Button("‹") { app.goBack() }
                        .buttonStyle(.plain)
                        .font(.system(size: 14))
                        .foregroundStyle(theme.text2)
                        .frame(width: 28, height: 28)
                        .background(RoundedRectangle(cornerRadius: 8).fill(theme.panel2))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border, lineWidth: 1))
                        .contentShape(Rectangle())
                        .padding(13)
                    Spacer()
                }
                Spacer()
                Image(systemName: "ellipsis.message")
                    .font(.system(size: 32))
                    .foregroundStyle(theme.text3)
                Text(app.t("No exchange in this session"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(theme.text2)
                    .padding(.top, 10)
                Text(app.t("The session is started but no command has been run yet."))
                    .font(.system(size: 12))
                    .foregroundStyle(theme.text3)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
                    .padding(.horizontal, 40)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.bg)
        }
    }

    @ViewBuilder
    private func content(_ detail: SessionDetail) -> some View {
        if let root = detail.agents.first(where: { $0.parentId == nil }) ?? detail.agents.first {
            let selected = detail.agents.first(where: { $0.id == app.selectedNodeId }) ?? root
            let col = theme.colors(detail.summary.status)

            VStack(spacing: 0) {
                header(detail, col: col)
                statStrip(detail, root: root)
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        SectionLabel(text: app.t("Agent tree"), color: theme.text3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.init(top: 13, leading: 24, bottom: 7, trailing: 24))
                        if !isExpanded {
                            ScrollView([.horizontal, .vertical]) {
                                AgentGraphView(agents: detail.agents)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        bottomPanel(detail: detail, selected: selected)
                            .frame(height: isExpanded ? nil : 260)
                            .frame(maxHeight: isExpanded ? .infinity : 260)
                    }
                    .frame(maxWidth: .infinity)
                    InspectorView(node: selected)
                        .frame(width: 344)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.bg)
        } else {
            EmptyView()
        }
    }

    /// Tabbed bottom panel: lifecycle Chronologie (session-wide) | per-agent Flux d'actions.
    @ViewBuilder
    private func bottomPanel(detail: SessionDetail, selected: AgentNode) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                tabButton(.chrono, title: app.t("Timeline"),
                          subtitle: app.t("Lifecycle · whole session"), live: false)
                tabButton(.flux, title: app.t("Action flow"),
                          subtitle: app.t("Agent: %@", selected.label), live: selected.status == .busy)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
                } label: {
                    Image(systemName: isExpanded
                          ? "arrow.down.right.and.arrow.up.left"
                          : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.text)
                        .frame(width: 28, height: 28)
                        .background(RoundedRectangle(cornerRadius: 6).fill(theme.panel2))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.border, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.init(top: 10, leading: 24, bottom: 0, trailing: 24))
            .background(theme.panel2)
            .overlay(alignment: .bottom) { theme.border.frame(height: 1) }

            if bottomTab == .chrono {
                TimelineView(events: detail.timeline)
            } else {
                FluxView(node: selected)
            }
        }
    }

    @ViewBuilder
    private func tabButton(_ tab: BottomTab, title: String, subtitle: String, live: Bool) -> some View {
        let on = bottomTab == tab
        Button { bottomTab = tab } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(on ? theme.text : theme.text2)
                    if live {
                        Circle().fill(theme.stBusy).frame(width: 6, height: 6).pulse(true)
                    }
                }
                Text(subtitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.text2)
                    .lineLimit(1)
            }
            .padding(.init(top: 8, leading: 12, bottom: 10, trailing: 12))
            .background(on ? theme.bg : Color.clear)
            .overlay(alignment: .bottom) {
                Rectangle().fill(on ? theme.accent : .clear).frame(height: 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func header(_ detail: SessionDetail, col: (main: Color, soft: Color)) -> some View {
        HStack(spacing: 13) {
            Button {
                app.goBack()
            } label: {
                Text("‹")
                    .font(.system(size: 14))
                    .foregroundStyle(theme.text2)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 8).fill(theme.panel2))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border, lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            StatusDot(color: col.main, soft: col.soft, size: 9, pulsing: detail.summary.status == .busy)

            VStack(alignment: .leading, spacing: 1) {
                Text(app.displayTitle(detail.summary))
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("\(app.projectLabel(detail.summary)) · \(detail.summary.branch) · \(statusLabel(detail.summary.status, app.settings.language))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(theme.text2)
            }

            Spacer()

            HStack(spacing: 7) {
                Button { app.resumeSession(id: detail.summary.id, cwd: detail.summary.cwd, live: detail.summary.live) } label: {
                    Text(app.t("↻ Resume"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(theme.accent))
                }
                .buttonStyle(.plain)
                .disabled(detail.summary.live)
                .opacity(detail.summary.live ? 0.4 : 1)

                GhostButton(title: "Finder") { app.revealInFinder(cwd: detail.summary.cwd) }
                GhostButton(title: "IDE") { app.openInEditor(cwd: detail.summary.cwd) }
                GhostButton(title: app.t("Copy ID")) { app.copySessionID(detail.summary.id) }
            }
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 26)
        .background(theme.panel)
        .overlay(alignment: .bottom) { theme.border2.frame(height: 1) }
    }

    @ViewBuilder
    private func statStrip(_ detail: SessionDetail, root: AgentNode) -> some View {
        let totalCost = detail.agents.reduce(0.0) { $0 + app.cost($1.tokens, $1.model).cost }
        HStack(spacing: 0) {
            statCell(app.t("Tokens"), Fmt.tokens(detail.totalTokens.total))
            statCell(app.t("Cost"), Fmt.cost(totalCost))
            statCell(app.t("Duration"), Fmt.duration(root.durationMs))
            statCell(app.t("Turns"), "\(detail.summary.tours)")
            statCell(app.t("Agents"), "\(detail.agentCount)", divider: false)
        }
        .background(theme.panel)
        .overlay(alignment: .bottom) { theme.border2.frame(height: 1) }
    }

    @ViewBuilder
    private func statCell(_ label: String, _ value: String, divider: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            SectionLabel(text: label, color: theme.text3)
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .monospacedDigit()
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 22)
        .overlay(alignment: .trailing) { if divider { theme.border2.frame(width: 1) } }
    }
}
