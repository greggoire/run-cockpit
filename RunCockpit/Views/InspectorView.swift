import SwiftUI

struct InspectorView: View {
    @Environment(AppState.self) private var app
    @Environment(\.theme) private var theme

    let node: AgentNode

    var body: some View {
        let col = theme.colors(node.status)
        let c = app.cost(node.tokens, node.model)

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 9) {
                    StatusDot(color: col.main, soft: col.soft, size: 9)
                    Text(node.label)
                        .font(.system(size: 14, weight: .semibold))
                }

                HStack(spacing: 7) {
                    Tag(text: node.agentType, fg: theme.accent, bg: theme.accentSoft)
                    Tag(text: app.pricing.modelLabel(node.model), fg: theme.text2, bg: theme.bg2, weight: .medium)
                    Tag(text: statusLabel(node.status, app.settings.language), fg: col.main, bg: col.soft)
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: app.t("Tokens"), color: theme.text3)
                    LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading),
                                        GridItem(.flexible(), alignment: .leading)], spacing: 10) {
                        bucket(app.t("Input"), node.tokens.input)
                        bucket(app.t("Output"), node.tokens.output)
                        bucket(app.t("5 min cache"), node.tokens.cacheWrite5m)
                        bucket(app.t("1 hr cache"), node.tokens.cacheWrite1h)
                        bucket(app.t("Cache read"), node.tokens.cacheRead)
                    }
                }

                HStack {
                    Text(app.t("Estimated cost"))
                        .font(.system(size: 12))
                        .foregroundStyle(theme.text2)
                    Spacer()
                    if c.missing {
                        Tag(text: app.t("missing price"), fg: theme.stIdle, bg: theme.stIdleSoft, size: 10)
                    } else {
                        Text(Fmt.cost(c.cost))
                            .font(.system(size: 17, weight: .bold))
                            .monospacedDigit()
                    }
                }
                .padding(.init(top: 11, leading: 13, bottom: 11, trailing: 13))
                .background(RoundedRectangle(cornerRadius: 10).fill(theme.bg2))

                VStack(alignment: .leading, spacing: 11) {
                    SectionLabel(text: app.t("Time"), color: theme.text3)
                    LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading),
                                        GridItem(.flexible(), alignment: .leading)], spacing: 11) {
                        timeCell(app.t("Start"), node.start.map { Fmt.clock($0) } ?? "—")
                        timeCell(app.t("End"), node.end.map { Fmt.clock($0) } ?? "—")
                        timeCell(app.t("Duration"), Fmt.duration(node.durationMs))
                    }
                }

                VStack(alignment: .leading, spacing: 9) {
                    SectionLabel(text: app.t("Tools"), color: theme.text3)
                    if node.tools.displayPairs.isEmpty {
                        Text("—").foregroundStyle(theme.text3)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 7)], alignment: .leading, spacing: 7) {
                            ForEach(node.tools.displayPairs, id: \.0) { pair in
                                HStack(spacing: 4) {
                                    Text(pair.0)
                                        .font(.system(size: 11))
                                        .foregroundStyle(theme.text2)
                                    Text("\(pair.1)")
                                        .font(.system(size: 11, weight: .semibold))
                                        .monospacedDigit()
                                        .foregroundStyle(theme.text)
                                }
                                .padding(.horizontal, 9)
                                .padding(.vertical, 3)
                                .background(RoundedRectangle(cornerRadius: 7).fill(theme.bg2))
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: app.t("Task"), color: theme.text3)
                    Text(node.prompt.isEmpty ? "—" : node.prompt)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.text2)
                        .lineSpacing(3)
                        .padding(.init(top: 11, leading: 13, bottom: 11, trailing: 13))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 10).fill(theme.bg2))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.border2, lineWidth: 1))
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.panel)
        .overlay(alignment: .leading) { theme.border.frame(width: 1) }
    }

    private func bucket(_ l: String, _ v: Int) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(l)
                .font(.system(size: 10.5))
                .foregroundStyle(theme.text3)
            Text(Fmt.tokens(v))
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
        }
    }

    private func timeCell(_ l: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(l)
                .font(.system(size: 10.5))
                .foregroundStyle(theme.text3)
            Text(v)
                .font(.system(size: 12.5, weight: .medium))
                .monospacedDigit()
        }
    }
}
