import SwiftUI

/// Global application settings. Mirrors PricingView's header + scrollable cards;
/// every control saves immediately via an AppState mutator (which calls settings.save()).
struct SettingsView: View {
    @Environment(AppState.self) private var app
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .background(theme.bg)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 0) {
            Text(app.t("Settings")).font(.system(size: 15, weight: .semibold)).tracking(-0.3)
                .foregroundStyle(theme.text)
            Spacer()
            Text(app.t("Saved · %@", Self.settingsPathDisplay))
                .font(.system(size: 11)).foregroundStyle(theme.text3)
                .lineLimit(1).truncationMode(.middle)
        }
        .frame(height: 54)
        .padding(.horizontal, 28)
        .background(theme.panel)
        .overlay(alignment: .bottom) { theme.border2.frame(height: 1) }
    }

    // MARK: - Content

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                appearanceCard
                languageCard
                editorCard
                defaultsCard
                projectsCard
                notificationsCard
                costsCard
                maintenanceCard
            }
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28).padding(.vertical, 26)
        }
    }

    // MARK: - Sections

    private var appearanceCard: some View {
        sectionCard(app.t("Appearance")) {
            settingRow(app.t("Theme"), app.t("Dark or light, applied to the whole app.")) {
                segment([app.t("Dark"), app.t("Light")], selected: theme.isDark ? 0 : 1) {
                    app.setAppearance($0 == 0 ? .dark : .light)
                }
            }
        }
    }

    private var languageCard: some View {
        sectionCard(app.t("Language")) {
            settingRow(app.t("Language"), app.t("Interface language for the whole app.")) {
                segment([Language.en.displayName, Language.fr.displayName],
                        selected: app.settings.language == .en ? 0 : 1) {
                    app.setLanguage($0 == 0 ? .en : .fr)
                }
            }
        }
    }

    private var editorCard: some View {
        sectionCard(app.t("Editor & external apps")) {
            settingRow(app.t("IDE application"),
                       app.t("App opened by a session's “IDE” button.")) {
                HStack(spacing: 8) {
                    Text(editorName).font(.system(size: 12)).foregroundStyle(theme.text2).lineLimit(1)
                    GhostButton(title: app.t("Change…")) { app.chooseEditor() }
                    if app.settings.editorAppPath != nil {
                        GhostButton(title: app.t("Reset")) { app.clearEditor() }
                    }
                }
            }
        }
    }

    private var defaultsCard: some View {
        sectionCard(app.t("Default display")) {
            settingRow(app.t("Start tab"), app.t("View shown when the app opens.")) {
                segment([app.t("Active sessions"), app.t("Dashboard"), app.t("History")], selected: startTabIndex) {
                    app.setStartTab([.active, .stats, .history][$0])
                }
            }
            divider
            settingRow(app.t("Default period"),
                       app.t("Preselected range for the dashboard and history.")) {
                SegmentedControl(options: AppState.periodOptions, selection: app.settings.defaultPeriod) {
                    app.setDefaultPeriod($0)
                }
                .fixedSize()
            }
            divider
            settingRow(app.t("First day of week"),
                       app.t("Used to calculate the current week range on the dashboard.")) {
                segment([app.t("Monday"), app.t("Sunday"), app.t("Saturday")],
                        selected: [2, 1, 7].firstIndex(of: app.settings.weekStartDay) ?? 0) {
                    app.setWeekStartDay([2, 1, 7][$0])
                }
            }
        }
    }

    private var projectsCard: some View {
        sectionCard(app.t("Projects")) {
            settingRow(app.t("Group projects by Git remote"),
                       app.t("Merge Git worktrees and clones that share the same remote URL into a single project.")) {
                toggle(app.settings.groupByGitRemote) { app.setGroupByGitRemote($0) }
            }
            divider
            settingRow(app.t("Re-detect"),
                       app.t("Forget cached Git remotes and probe each project again.")) {
                GhostButton(title: app.t("Re-detect")) { app.redetectProjects() }
            }
        }
    }

    private var notificationsCard: some View {
        sectionCard(app.t("Notifications")) {
            settingRow(app.t("Notifications enabled"),
                       app.t("Get notified when a session starts waiting for action.")) {
                toggle(app.settings.notificationsEnabled) { app.setNotifications($0) }
            }
            divider
            settingRow(app.t("Sound"), app.t("Play a sound with the notification.")) {
                toggle(app.settings.notificationSound) { app.setNotificationSound($0) }
            }
        }
    }

    private var costsCard: some View {
        sectionCard(app.t("Costs & pricing")) {
            settingRow(app.t("Model prices"),
                       app.t("$/M token rates used to compute session costs.")) {
                GhostButton(title: app.t("Open")) { app.go(.pricing) }
            }
        }
    }

    private var maintenanceCard: some View {
        sectionCard(app.t("Maintenance")) {
            settingRow(app.t("Version"), app.t("Installed RunCockpit version.")) {
                Text(appVersion).font(.system(size: 12)).monospacedDigit().foregroundStyle(theme.text2)
            }
            divider
            settingRow(app.t("Settings file"), app.t("settings.json in Application Support.")) {
                GhostButton(title: app.t("Open in Finder")) { app.revealSettingsFile() }
            }
            divider
            settingRow(app.t("Reset settings"),
                       app.t("Restores theme, IDE and preferences to their defaults.")) {
                GhostButton(title: app.t("Reset"), danger: true) { app.resetSettings() }
            }
        }
    }

    // MARK: - Building blocks

    private func sectionCard<C: View>(_ label: String, @ViewBuilder _ rows: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(text: label, color: theme.text2)
            rows()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(theme)
    }

    private func settingRow<C: View>(_ title: String, _ desc: String,
                                     @ViewBuilder _ control: () -> C) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(theme.text)
                Text(desc).font(.system(size: 11.5)).foregroundStyle(theme.text2).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            control()
        }
    }

    private var divider: some View { theme.border2.frame(height: 1) }

    /// Local enum-friendly segmented control, styled like `SegmentedControl`.
    private func segment(_ labels: [String], selected: Int,
                         onSelect: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 2) {
            ForEach(Array(labels.enumerated()), id: \.offset) { i, label in
                let on = i == selected
                Button { onSelect(i) } label: {
                    Text(label).font(.system(size: 11.5, weight: .medium))
                        .lineLimit(1).fixedSize()
                        .foregroundStyle(on ? theme.text : theme.text2)
                        .padding(.horizontal, 11).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 7).fill(on ? theme.panel : .clear))
                        .overlay(on ? RoundedRectangle(cornerRadius: 7).stroke(theme.border, lineWidth: 1) : nil)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 9).fill(theme.bg2))
        .fixedSize()
    }

    private func toggle(_ isOn: Bool, _ set: @escaping (Bool) -> Void) -> some View {
        Toggle("", isOn: Binding(get: { isOn }, set: set))
            .labelsHidden()
            .toggleStyle(.switch)
            .tint(theme.accent)
    }

    // MARK: - Derived

    private var editorName: String {
        guard let p = app.settings.editorAppPath else { return app.t("None (asked on first click)") }
        return URL(fileURLWithPath: p).deletingPathExtension().lastPathComponent
    }

    private var startTabIndex: Int {
        switch app.settings.startTab {
        case .active:  return 0
        case .stats:   return 1
        case .history: return 2
        }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "—"
        let b = info?["CFBundleVersion"] as? String ?? "—"
        return "\(v) (\(b))"
    }

    private static var settingsPathDisplay: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let p = Paths.settingsFile.path
        return p.hasPrefix(home) ? "~" + p.dropFirst(home.count) : p
    }
}
