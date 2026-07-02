import SwiftUI

/// Repeating opacity pulse (mockup `@keyframes csPulse`).
struct Pulse: ViewModifier {
    @State private var on = false
    func body(content: Content) -> some View {
        content
            .opacity(on ? 0.35 : 1)
            .animation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}

extension View {
    @ViewBuilder func pulse(_ active: Bool = true) -> some View {
        if active { modifier(Pulse()) } else { self }
    }
}

/// Status dot with a soft 3px ring (mockup `box-shadow:0 0 0 3px soft`).
struct StatusDot: View {
    let color: Color
    let soft: Color
    var size: CGFloat = 9
    var pulsing: Bool = false
    var ring: Bool = true

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .pulse(pulsing)
            .padding(ring ? 3 : 0)
            .background(ring ? Circle().fill(soft) : nil)
    }
}

/// Small rounded label (model chips, type tags, "prix manquant" badge…).
struct Tag: View {
    let text: String
    var fg: Color
    var bg: Color
    var weight: Font.Weight = .semibold
    var size: CGFloat = 11

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: weight))
            .foregroundStyle(fg)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 6).fill(bg))
    }
}

/// Section header in caps (mockup `text-transform:uppercase; letter-spacing`).
struct GhostButton: View {
    @Environment(\.theme) private var theme
    let title: String
    var danger: Bool = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 12, weight: .medium))
                .foregroundStyle(danger ? theme.stErr : theme.text2)
                .padding(.horizontal, 11).padding(.vertical, 6)
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(danger ? theme.stErr.opacity(0.5) : theme.border, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SectionLabel: View {
    let text: String
    var color: Color
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(color)
    }
}

extension View {
    /// Panel card styling (mockup `background:panel; border; radius:14; shadow`).
    func card(_ theme: Theme) -> some View {
        self.padding(18)
            .background(RoundedRectangle(cornerRadius: 14).fill(theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.border, lineWidth: 1))
            .shadow(color: .black.opacity(theme.isDark ? 0.30 : 0.05), radius: 8, y: 3)
    }
}

extension Color {
    /// Hairline border helper.
    func hairline() -> some View { Rectangle().fill(self).frame(height: 1) }
}
