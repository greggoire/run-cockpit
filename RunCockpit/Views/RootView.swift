import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var app
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
            mainContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.bg)
        }
        .background(theme.bg)
        .overlay(alignment: .bottom) { toast }
        .environment(\.theme, theme)
    }

    @ViewBuilder
    private var mainContent: some View {
        switch app.route {
        case .active:  ActiveDashboardView()
        case .stats:   StatsView()
        case .history: HistoryView()
        case .pricing: PricingView()
        case .detail:  SessionDetailView()
        case .settings: SettingsView()
        }
    }

    @ViewBuilder
    private var toast: some View {
        if let t = app.toast {
            HStack(spacing: 9) {
                Text("›").foregroundStyle(theme.stBusy)
                Text(t).font(.system(size: 12.5, design: .monospaced))
            }
            .foregroundStyle(theme.bg)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 10).fill(theme.text))
            .shadow(color: .black.opacity(0.3), radius: 15, y: 8)
            .padding(.bottom, 24)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

// MARK: - Sidebar

private struct Sidebar: View {
    @Environment(AppState.self) private var app
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            logo
            VStack(spacing: 3) {
                navButton(title: app.t("Active sessions"), glyph: "◉", route: .active,
                          trailing: app.attendCount > 0 ? .badge(app.attendCount) : .none)
                navButton(title: app.t("Dashboard"), glyph: "▦", route: .stats, trailing: .none)
                navButton(title: app.t("History"), glyph: "☰", route: .history,
                          trailing: .count(app.historyCount))
                navButton(title: app.t("Model pricing"), glyph: "$", route: .pricing, trailing: .none)
                navButton(title: app.t("Settings"), glyph: "⚙", route: .settings, trailing: .none)
            }
            Spacer()
            footer
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 16)
        .frame(width: 218)
        .background(theme.bg2)
        .overlay(alignment: .trailing) { theme.border.frame(width: 1) }
    }

    private var logo: some View {
        HStack(spacing: 9) {
            Image("Logo")
                .resizable()
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 7))
            Text("RunCockpit").font(.system(size: 14, weight: .semibold)).tracking(-0.3)
                .foregroundStyle(theme.text)
        }
        .padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 18)
    }

    enum Trailing { case none, badge(Int), count(Int) }

    private func navButton(title: String, glyph: String, route: Route, trailing: Trailing) -> some View {
        let active = app.route == route || (route == .active && app.route == .detail && app.detailFrom == .active)
            || (route == .history && app.route == .detail && app.detailFrom == .history)
        return Button { app.go(route) } label: {
            HStack(spacing: 10) {
                Text(glyph).font(.system(size: 14)).frame(width: 16)
                Text(title).font(.system(size: 13, weight: .medium))
                Spacer(minLength: 4)
                switch trailing {
                case .none: EmptyView()
                case .badge(let n):
                    Text("\(n)").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                        .frame(minWidth: 18, minHeight: 18).padding(.horizontal, 5)
                        .background(Capsule().fill(theme.stIdle))
                case .count(let n):
                    Text("\(n)").font(.system(size: 11)).monospacedDigit().foregroundStyle(theme.text3)
                }
            }
            .foregroundStyle(active ? theme.accent : theme.text2)
            .padding(.horizontal, 11).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 9).fill(active ? theme.accentSoft : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 11) {
            theme.border.frame(height: 1).padding(.bottom, 1)
            HStack(spacing: 8) {
                StatusDot(color: theme.stBusy, soft: theme.stBusySoft, size: 7, pulsing: true, ring: false)
                Text(app.t("FSEvents · read-only")).font(.system(size: 11)).foregroundStyle(theme.text2)
            }
            footerToggle(label: app.t("Theme"), value: theme.isDark ? "◐" : "◑") { app.toggleTheme() }
            footerToggle(label: app.t("Notifications"), value: app.settings.notificationsEnabled ? "ON" : "OFF") {
                app.setNotifications(!app.settings.notificationsEnabled)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 12)
    }

    private func footerToggle(label: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label).font(.system(size: 12))
                Spacer()
                Text(value).font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(theme.text2)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 8).fill(theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
