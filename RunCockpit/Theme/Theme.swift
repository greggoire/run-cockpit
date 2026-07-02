import SwiftUI

// MARK: - Color hex helpers

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xff) / 255
        let g = Double((hex >> 8) & 0xff) / 255
        let b = Double(hex & 0xff) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
    static func whiteA(_ a: Double) -> Color { Color(.sRGB, white: 1, opacity: a) }
    static func blackA(_ a: Double) -> Color { Color(.sRGB, white: 0, opacity: a) }
    static func rgba(_ hex: UInt32, _ a: Double) -> Color {
        Color(.sRGB,
              red: Double((hex >> 16) & 0xff) / 255,
              green: Double((hex >> 8) & 0xff) / 255,
              blue: Double(hex & 0xff) / 255,
              opacity: a)
    }
}

/// Design tokens mirrored from the mockup's CSS custom properties.
struct Theme: Sendable {
    let isDark: Bool
    let bg, bg2, panel, panel2: Color
    let border, border2, borderStrong: Color
    let text, text2, text3: Color
    let accent, accentSoft: Color
    let stBusy, stBusySoft, stIdle, stIdleSoft, stDone, stDoneSoft: Color
    let stErr, stErrSoft: Color

    static let light = Theme(
        isDark: false,
        bg: Color(hex: 0xf4f4f2), bg2: Color(hex: 0xe9e9e5), panel: .white, panel2: Color(hex: 0xfafaf9),
        border: .blackA(0.085), border2: .blackA(0.05), borderStrong: .blackA(0.16),
        text: Color(hex: 0x1b1b18), text2: Color(hex: 0x67675e), text3: Color(hex: 0x9b9b91),
        accent: Color(hex: 0x2f6df6), accentSoft: .rgba(0x2f6df6, 0.11),
        stBusy: Color(hex: 0x1f9d57), stBusySoft: .rgba(0x1f9d57, 0.13),
        stIdle: Color(hex: 0xd9881a), stIdleSoft: .rgba(0xd9881a, 0.14),
        stDone: Color(hex: 0x8a8a82), stDoneSoft: .rgba(0x8a8a82, 0.13),
        stErr: Color(hex: 0xd64545), stErrSoft: .rgba(0xd64545, 0.12))

    static let dark = Theme(
        isDark: true,
        bg: Color(hex: 0x151517), bg2: Color(hex: 0x1c1c1f), panel: Color(hex: 0x212125), panel2: Color(hex: 0x26262a),
        border: .whiteA(0.09), border2: .whiteA(0.05), borderStrong: .whiteA(0.2),
        text: Color(hex: 0xededed), text2: Color(hex: 0x9d9da3), text3: Color(hex: 0x69696f),
        accent: Color(hex: 0x5b8cff), accentSoft: .rgba(0x5b8cff, 0.16),
        stBusy: Color(hex: 0x34c97a), stBusySoft: .rgba(0x34c97a, 0.15),
        stIdle: Color(hex: 0xf0a93a), stIdleSoft: .rgba(0xf0a93a, 0.15),
        stDone: Color(hex: 0x85858d), stDoneSoft: .rgba(0x85858d, 0.15),
        stErr: Color(hex: 0xff6b6b), stErrSoft: .rgba(0xff6b6b, 0.14))

    func colors(_ s: SessionStatus) -> (main: Color, soft: Color) {
        switch s {
        case .busy: return (stBusy, stBusySoft)
        case .idle: return (stIdle, stIdleSoft)
        case .done: return (stDone, stDoneSoft)
        }
    }
}

/// Localized status label (was frozen French inside `colors()`). Source = English keys.
func statusLabel(_ s: SessionStatus, _ lang: Language) -> String {
    switch s {
    case .busy: return tr("In progress", lang)
    case .idle: return tr("Waiting for you", lang)
    case .done: return tr("Done", lang)
    }
}

// MARK: - Environment injection

private struct ThemeKey: EnvironmentKey {
    static let defaultValue: Theme = .dark
}
extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

// MARK: - Formatters (ported from the mockup's JS helpers)

enum Fmt {
    /// Tokens: 1234 → "1.2k", 1_500_000 → "1.5M".
    static func tokens(_ n: Int) -> String {
        let d = Double(n)
        if d >= 1e6 {
            let v = d / 1e6
            return trim(String(format: d >= 1e7 ? "%.1f" : "%.2f", v)) + "M"
        }
        if d >= 1e3 {
            let v = d / 1e3
            return trim(String(format: d >= 1e5 ? "%.0f" : "%.1f", v)) + "k"
        }
        return "\(n)"
    }

    private static func trim(_ s: String) -> String {
        guard s.contains(".") else { return s }
        var out = s
        while out.hasSuffix("0") { out.removeLast() }
        if out.hasSuffix(".") { out.removeLast() }
        return out
    }

    /// Duration from milliseconds.
    static func duration(_ ms: Double?) -> String {
        guard let ms, ms >= 0 else { return "—" }
        let s = ms / 1000
        if s < 60 { return "\(Int(s.rounded()))s" }
        let m = s / 60
        if m < 60 { return "\(Int(m.rounded(.down)))m \(pad(Int((s.truncatingRemainder(dividingBy: 60)).rounded())))s" }
        let h = Int((m / 60).rounded(.down))
        return "\(h)h \(pad(Int(m.truncatingRemainder(dividingBy: 60).rounded(.down))))m"
    }

    private static func pad(_ n: Int) -> String { String(format: "%02d", n) }

    /// Cost in dollars.
    static func cost(_ n: Double?) -> String {
        guard let n else { return "$0" }
        if n >= 100 { return "$" + String(format: "%.0f", n) }
        if n >= 1 { return "$" + String(format: "%.2f", n) }
        return "$" + String(format: "%.3f", n)
    }

    /// Relative time, French.
    static func relative(_ date: Date, now: Date = Date()) -> String {
        let s = max(0, Int(now.timeIntervalSince(date).rounded()))
        if s < 60 { return "il y a \(s)s" }
        let m = s / 60
        if m < 60 { return "il y a \(m)min" }
        let h = m / 60
        if h < 24 { return "il y a \(h)h" }
        return "il y a \(h / 24)j"
    }

    private static let clockFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "HH:mm"
        return f
    }()
    private static let dayFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "dd MMM HH:mm"
        return f
    }()

    static func clock(_ d: Date) -> String { clockFmt.string(from: d) }
    static func dateTime(_ d: Date) -> String { dayFmt.string(from: d) }

    /// Strip the `[1m]` 1M-context suffix to get the base model id.
    static func alias(_ model: String) -> String { model.replacingOccurrences(of: "[1m]", with: "") }
}
