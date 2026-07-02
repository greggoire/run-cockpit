import SwiftUI

struct ActiveDashboardView: View {
    @Environment(AppState.self) private var app
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            header
            body0
        }
        .background(theme.bg)
    }

    private var header: some View {
        HStack {
            Text(app.t("Active sessions"))
                .font(.system(size: 15, weight: .semibold))
                .tracking(-0.3)
                .foregroundStyle(theme.text)
            Spacer()
            HStack(spacing: 7) {
                StatusDot(color: theme.stBusy, soft: theme.stBusySoft, size: 7, pulsing: true, ring: false)
                Text(app.t("Real-time · %d live sessions", app.liveCount))
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.text2)
            }
        }
        .frame(height: 54)
        .padding(.horizontal, 28)
        .background(theme.panel)
        .overlay(alignment: .bottom) { theme.border2.hairline() }
    }

    private var body0: some View {
        ScrollView {
            VStack {
                HStack(alignment: .top, spacing: 26) {
                    column(
                        dotMain: theme.stIdle, dotSoft: theme.stIdleSoft,
                        label: app.t("Awaiting your action"), count: app.attendCount,
                        cards: app.attendCards, emptyText: app.t("No session awaits your action.")
                    )
                    column(
                        dotMain: theme.stBusy, dotSoft: theme.stBusySoft,
                        label: app.t("In progress"), count: app.busyCount,
                        cards: app.busyCards, emptyText: app.t("No session in progress.")
                    )
                }
            }
            .frame(maxWidth: 1080)
            .padding(.top, 24)
            .padding(.horizontal, 28)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func column(dotMain: Color, dotSoft: Color, label: String, count: Int, cards: [SessionSummary], emptyText: String) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 8) {
                StatusDot(color: dotMain, soft: dotSoft, size: 9)
                SectionLabel(text: label, color: theme.text2)
                Text("\(count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.text3)
            }
            if cards.isEmpty {
                Text(emptyText)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.text3)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(22)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(theme.border, style: StrokeStyle(lineWidth: 1, dash: [5]))
                    )
            } else {
                VStack(spacing: 13) {
                    ForEach(cards) { SessionCardView(summary: $0) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}
