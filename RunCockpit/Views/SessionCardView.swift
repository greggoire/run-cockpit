import SwiftUI

struct SessionCardView: View {
    @Environment(AppState.self) private var app
    @Environment(\.theme) private var theme
    let summary: SessionSummary
    @State private var confirmKill = false

    var body: some View {
        let col = theme.colors(summary.status)
        VStack(alignment: .leading, spacing: 9) {
            row1(col)
            row2
            row3
            theme.border2.hairline().padding(.vertical, 2)
            footer
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
        .contentShape(Rectangle())
        .onTapGesture { app.openSession(summary.id) }
    }

    private func row1(_ col: (main: Color, soft: Color)) -> some View {
        HStack {
            StatusDot(color: col.main, soft: col.soft, size: 9, pulsing: summary.status == .busy)
            Text(app.displayTitle(summary))
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(theme.text)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            Text(Fmt.duration(Date().timeIntervalSince(summary.startedAt) * 1000))
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(theme.text3)
        }
    }

    private var row2: some View {
        HStack(spacing: 6) {
            Text(app.projectLabel(summary))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(theme.text2)
                .lineLimit(1)
                .truncationMode(.middle)
            if !summary.branch.isEmpty {
                Text(summary.branch)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(theme.text3)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 5).fill(theme.bg2))
            }
            Spacer()
        }
    }

    private var row3: some View {
        HStack(spacing: 6) {
            Tag(text: app.pricing.modelLabel(summary.model), fg: theme.text2, bg: theme.bg2, weight: .medium, size: 10)
            Text("◇ \(Fmt.tokens(summary.tokens.total))")
                .font(.system(size: 10.5))
                .foregroundStyle(theme.text2)
            let c = app.cost(summary.tokens, summary.model)
            if c.missing {
                Tag(text: app.t("price missing"), fg: theme.stIdle, bg: theme.stIdleSoft, size: 10)
            } else {
                Text(Fmt.cost(c.cost))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.text)
            }
            if summary.subActive > 0 {
                Text(app.t("⌥ %d active", summary.subActive))
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.text2)
            }
            Spacer()
        }
    }

    private var footer: some View {
        let last = summary.status == .busy
            ? app.t("active · %@", Fmt.relative(summary.lastActivity))
            : app.t("waiting · %@", Fmt.relative(summary.lastActivity))
        return HStack {
            Text(last)
                .font(.system(size: 10.5))
                .foregroundStyle(theme.text3)
            Spacer()
            Button { confirmKill = true } label: {
                Text(app.t("✕ Terminate"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .contentShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(.red.opacity(0.35), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .confirmationDialog(app.t("Terminate this session?"), isPresented: $confirmKill) {
                Button(app.t("Terminate"), role: .destructive) { app.terminateSession(pid: summary.pid) }
                Button(app.t("Cancel"), role: .cancel) {}
            } message: {
                Text(app.t("The claude process will be stopped. Resumable later via Resume."))
            }
            Button {
                app.resumeSession(id: summary.id, cwd: summary.cwd, live: summary.live)
            } label: {
                Text(app.t("↻ Resume"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.text2)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .contentShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(theme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(summary.live)
            .opacity(summary.live ? 0.4 : 1)
        }
    }
}
