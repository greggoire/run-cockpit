import SwiftUI

struct TimelineView: View {
    @Environment(AppState.self) private var app
    @Environment(\.theme) private var theme

    let events: [TimelineEvent]
    @State private var autoScroll = true

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    SectionLabel(text: app.t("Timeline"), color: theme.text3)
                        .padding(.bottom, 11)
                    ForEach(Array(events.enumerated()), id: \.offset) { _, ev in
                        HStack(alignment: .top, spacing: 10) {
                            Text(Fmt.clock(ev.time))
                                .font(.system(size: 11))
                                .monospacedDigit()
                                .foregroundStyle(theme.text3)
                                .frame(width: 54, alignment: .trailing)
                            let dc = dotColor(ev.kind)
                            Circle()
                                .fill(dc)
                                .frame(width: 7, height: 7)
                                .pulse(ev.kind == .active)
                                .frame(width: 16, alignment: .center)
                                .padding(.top, 4)
                            Text(ev.label)
                                .font(.system(size: 12))
                                .foregroundStyle(theme.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(ev.durationMs.map { Fmt.duration($0) } ?? "")
                                .font(.system(size: 11))
                                .monospacedDigit()
                                .foregroundStyle(theme.text3)
                        }
                        .padding(.vertical, 5)
                    }
                    Color.clear.frame(height: 0).id("_bottom")
                }
                .padding(.init(top: 13, leading: 24, bottom: 18, trailing: 24))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(theme.panel2)
            .overlay(alignment: .top) { theme.border2.frame(height: 1) }
            .onScrollGeometryChange(for: Bool.self) { geo in
                geo.contentOffset.y + geo.containerSize.height >= geo.contentSize.height - 40
            } action: { _, atBottom in
                autoScroll = atBottom
            }
            .onScrollGeometryChange(for: Bool.self) { geo in
                geo.contentOffset.y + geo.containerSize.height >= geo.contentSize.height - 40
            } action: { _, atBottom in
                autoScroll = atBottom
            }
            .onChange(of: events.count) {
                if autoScroll { proxy.scrollTo("_bottom") }
            }
            .onAppear { proxy.scrollTo("_bottom") }
        }
    }

    private func dotColor(_ k: TimelineKind) -> Color {
        switch k {
        case .start: return theme.accent
        case .spawn: return theme.text3
        case .done: return theme.stBusy
        case .active: return theme.stIdle
        }
    }
}
