import SwiftUI

struct AgentGraphView: View {
    @Environment(\.theme) private var theme

    let agents: [AgentNode]

    private static let colW: Double = 268
    private static let rowH: Double = 128
    private let nodeW: Double = 212
    private let nodeH: Double = 92
    private static let padL: Double = 8
    private static let padT: Double = 14

    var body: some View {
        let layout = computeLayout()

        ZStack(alignment: .topLeading) {
            Canvas { ctx, _ in
                for a in agents where a.parentId != nil {
                    guard let pid = a.parentId, layout.byId[pid] != nil else { continue }
                    let x1 = layout.x(pid) + nodeW
                    let y1 = layout.y(pid) + nodeH / 2
                    let x2 = layout.x(a.id)
                    let y2 = layout.y(a.id) + nodeH / 2
                    var path = Path()
                    path.move(to: CGPoint(x: x1, y: y1))
                    let mx = (x1 + x2) / 2
                    path.addCurve(to: CGPoint(x: x2, y: y2),
                                  control1: CGPoint(x: mx, y: y1),
                                  control2: CGPoint(x: mx, y: y2))
                    ctx.stroke(path, with: .color(theme.borderStrong.opacity(0.55)), lineWidth: 1.5)
                }
            }
            .frame(width: layout.width, height: layout.height)

            ForEach(agents) { a in
                NodeCard(a: a)
                    .frame(width: nodeW)
                    .offset(x: layout.x(a.id), y: layout.y(a.id))
            }
        }
        .frame(width: layout.width, height: layout.height, alignment: .topLeading)
        .padding(.init(top: 6, leading: 24, bottom: 18, trailing: 24))
    }

    private struct Layout {
        let byId: [String: AgentNode]
        let depth: [String: Int]
        let slot: [String: Double]
        let width: Double
        let height: Double

        func x(_ id: String) -> Double { AgentGraphView.padL + Double(depth[id] ?? 0) * AgentGraphView.colW }
        func y(_ id: String) -> Double { AgentGraphView.padT + (slot[id] ?? 0) * AgentGraphView.rowH }
    }

    private func computeLayout() -> Layout {
        let byId = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, $0) })

        func depthOf(_ id: String) -> Int {
            var d = 0
            var cur = byId[id]?.parentId
            var seen: Set<String> = [id]
            // ponytail: guards a malformed/cyclic parentId chain (e.g. racy concurrent
            // transcript writers) from looping forever instead of terminating.
            while let p = cur, seen.insert(p).inserted { d += 1; cur = byId[p]?.parentId }
            return d
        }
        var depth = [String: Int]()
        for a in agents { depth[a.id] = depthOf(a.id) }

        var slot = [String: Double]()
        var next = 0.0
        var placing = Set<String>()
        func place(_ id: String) {
            guard placing.insert(id).inserted else { return }  // cycle guard, see depthOf
            let ch = agents.filter { $0.parentId == id }
            if ch.isEmpty {
                slot[id] = next
                next += 1
            } else {
                for c in ch { place(c.id) }
                slot[id] = ch.map { slot[$0.id] ?? 0 }.reduce(0, +) / Double(ch.count)
            }
        }
        for r in agents where r.parentId == nil { place(r.id) }
        if next == 0 { next = 1 }

        let maxDepth = agents.map { depth[$0.id] ?? 0 }.max() ?? 0
        let width = Self.padL + Double(maxDepth + 1) * Self.colW
        let height = Self.padT + next * Self.rowH

        return Layout(byId: byId, depth: depth, slot: slot,
                      width: width, height: height)
    }

}

/// Standalone so it (not the whole graph body) is what reads `app.selectedNodeId`:
/// selecting a node updates only the tapped card's ring, the parent body — and thus
/// `computeLayout()` — never re-runs on selection. ponytail.
private struct NodeCard: View {
    @Environment(AppState.self) private var app
    @Environment(\.theme) private var theme
    let a: AgentNode

    var body: some View {
        let col = theme.colors(a.status)
        let c = app.cost(a.tokens, a.model)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                StatusDot(color: col.main, soft: col.soft, size: 8, pulsing: a.status == .busy, ring: false)
                Text(a.label)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            HStack(spacing: 6) {
                Tag(text: a.agentType, fg: theme.accent, bg: theme.bg2, size: 10)
                Text(app.pricing.modelLabel(a.model))
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.text2)
            }
            HStack {
                Text("◇ \(Fmt.tokens(a.tokens.total))")
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.text2)
                Spacer()
                Text(c.missing ? "—" : Fmt.cost(c.cost))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(theme.text)
            }
        }
        .padding(.init(top: 11, leading: 13, bottom: 11, trailing: 13))
        .background(RoundedRectangle(cornerRadius: 11).fill(theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(theme.border, lineWidth: 1))
        .overlay(alignment: .leading) {
            Rectangle().fill(col.main).frame(width: 3).clipShape(RoundedRectangle(cornerRadius: 2))
        }
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(theme.accent, lineWidth: app.selectedNodeId == a.id ? 2 : 0))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
        .contentShape(Rectangle())
        .onTapGesture { app.selectedNodeId = a.id }
    }
}
