import SwiftUI

// MARK: - Markdown segment parsing

private enum MDSegment {
    case text(String)
    case code(lang: String?, content: String)
}

private func parseSegments(_ body: String) -> [MDSegment] {
    var result: [MDSegment] = []
    let pattern = #"```([^\n`]*)\n([\s\S]*?)```"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [.text(body)] }
    let ns = body as NSString
    let matches = regex.matches(in: body, range: NSRange(location: 0, length: ns.length))
    var cursor = 0
    for m in matches {
        if m.range.location > cursor {
            let pre = ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
            if !pre.isEmpty { result.append(.text(pre)) }
        }
        let langRaw = m.range(at: 1).length > 0
            ? ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
            : ""
        let content = ns.substring(with: m.range(at: 2))
        result.append(.code(lang: langRaw.isEmpty ? nil : langRaw, content: content))
        cursor = m.range.location + m.range.length
    }
    if cursor < ns.length {
        let tail = ns.substring(from: cursor)
        if !tail.isEmpty { result.append(.text(tail)) }
    }
    return result.isEmpty ? [.text(body)] : result
}

/// Per-agent ordered action stream (mockup "Flux d'actions"): assistant reasoning
/// text + tool calls with input summary, status and result preview. Driven by the
/// selected node, so it reacts to graph selection for free.
struct FluxView: View {
    @Environment(\.theme) private var theme
    @Environment(AppState.self) private var app
    let node: AgentNode
    @State private var autoScroll = true

    private var stepCount: Int { node.actions.filter { $0.kind == .tool }.count }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    header
                    if node.actions.isEmpty {
                        Text(app.t("No detailed actions"))
                            .font(.system(size: 12))
                            .foregroundStyle(theme.text3)
                            .padding(.top, 8)
                    } else {
                        // Positional id: stable across live re-parses (append-only stream) so
                        // the lazy stack diffs instead of rebuilding + keeps scroll. ponytail.
                        ForEach(Array(node.actions.enumerated()), id: \.offset) { _, row in
                            if row.kind == .text { textRow(row) } else { toolRow(row) }
                        }
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
            .onChange(of: node.actions.count) {
                if autoScroll || node.status == .busy { proxy.scrollTo("_bottom") }
            }
            // ponytail: deferred scroll — LazyVStack needs a layout pass before scrollTo works
            .onChange(of: node.label) {
                autoScroll = true
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(50))
                    proxy.scrollTo("_bottom")
                }
            }
            .onAppear {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(50))
                    proxy.scrollTo("_bottom")
                }
            }
        }
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: 9) {
            Tag(text: node.label, fg: theme.accent, bg: theme.accentSoft, size: 11)
                .lineLimit(1)
            Text(app.t("Sequence of this agent's actions — input, result, status."))
                .font(.system(size: 11))
                .foregroundStyle(theme.text3)
            Spacer(minLength: 8)
            Text(app.t("%lld steps", stepCount))
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(theme.text3)
        }
        .padding(.bottom, 13)
    }

    // MARK: rows

    private func textRow(_ r: ActionEvent) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Rectangle()
                .fill(theme.text3)
                .frame(width: 7, height: 7)
                .rotationEffect(.degrees(45))
                .frame(width: 16, alignment: .center)
                .padding(.top, 3)
            markdownBody(r.body)
        }
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private func markdownBody(_ body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(parseSegments(body).enumerated()), id: \.offset) { _, seg in
                switch seg {
                case .text(let s):
                    // ponytail: AttributedString gives inline MD (bold/italic/`code`) for free
                    if let attr = try? AttributedString(
                        markdown: s,
                        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
                    ) {
                        Text(attr)
                            .font(.system(size: 12))
                            .foregroundStyle(theme.text2)
                            .lineSpacing(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(s)
                            .font(.system(size: 12))
                            .foregroundStyle(theme.text2)
                            .lineSpacing(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                case .code(let lang, let content):
                    codeBlock(lang: lang, content: content)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func codeBlock(lang: String?, content: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let lang {
                Text(lang)
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.text3)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.bg2)
                theme.border.frame(height: 1)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Text(content.hasSuffix("\n") ? String(content.dropLast()) : content)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(theme.text)
                    .lineSpacing(2)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(theme.panel)
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(theme.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private func toolRow(_ r: ActionEvent) -> some View {
        let tc = toolColor(r.tool)
        let cardBg = r.running ? theme.stBusySoft : (r.isError ? theme.stErrSoft : theme.panel)
        let cardBorder = r.running ? theme.stBusy : (r.isError ? theme.stErr : theme.border)
        return HStack(alignment: .top, spacing: 13) {
            Circle()
                .fill(r.running ? theme.stBusy : (r.isError ? theme.stErr : theme.stDone))
                .frame(width: 9, height: 9)
                .pulse(r.running)
                .frame(width: 16, alignment: .center)
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Tag(text: r.tool, fg: tc.fg, bg: tc.bg, weight: .bold, size: 10.5)
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    Text(r.summary)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if r.running || r.isError {
                        Tag(text: r.running ? app.t("in progress") : app.t("error"),
                            fg: r.running ? theme.stBusy : theme.stErr,
                            bg: r.running ? theme.stBusySoft : theme.stErrSoft,
                            weight: .bold, size: 9)
                    }
                    Text(r.running ? "live" : (r.durationMs.map { Fmt.duration($0) } ?? ""))
                        .font(.system(size: 10.5))
                        .monospacedDigit()
                        .foregroundStyle(theme.text3)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 9).fill(cardBg))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(cardBorder, lineWidth: 1))

                HStack(spacing: 12) {
                    if let t = r.time { Text(Fmt.clock(t)) }
                    if r.tokens > 0 { Text("◇ \(Fmt.tokens(r.tokens))") }
                    if let m = r.meta { Text(app.t(m)).foregroundStyle(theme.text2) }
                }
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(theme.text3)
                .padding(.leading, 2)
            }
        }
        .padding(.bottom, 12)
    }

    // MARK: tool color — maps onto existing palette (no `violet` token). ponytail.
    private func toolColor(_ tool: String) -> (fg: Color, bg: Color) {
        switch tool.lowercased() {
        case "bash":                  return (theme.stIdle, theme.stIdleSoft)
        case "edit", "multiedit", "write", "notebookedit":
                                       return (theme.stBusy, theme.stBusySoft)
        case "grep", "glob":          return (theme.accent, theme.accentSoft)
        case "agent", "task":         return (theme.accent, theme.accentSoft)
        default:                       return (theme.text2, theme.bg2)
        }
    }
}
