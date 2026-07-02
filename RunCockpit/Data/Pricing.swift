import Foundation

/// Per-model tariffs in $ / million tokens (5 buckets).
struct PricingProfile: Codable, Sendable, Equatable {
    var label: String
    var input: Double
    var output: Double
    var cw5m: Double    // cache write 5 min
    var cw1h: Double    // cache write 1 h
    var read: Double    // cache read
}

struct PricingTable: Codable, Sendable, Equatable {
    /// Keyed by base model id (alias `[1m]` stripped).
    var profiles: [String: PricingProfile]
    /// Claude Code short aliases → concrete model id. Resolved at session-close time.
    var aliasMap: [String: String] = [:]

    // $/M token rates. Source: https://platform.claude.com/docs/en/about-claude/pricing
    // ponytail: status suffixes (limited availability/deprecated/retired) are
    // English-only — localizing static model metadata isn't worth splitting the
    // table into name+status. Thread a Language here if a FR toggle is ever wanted.
    static let defaultAliases: [String: String] = [
        "fable":  "claude-fable-5",
        "sonnet": "claude-sonnet-5",
        "haiku":  "claude-haiku-4-5",
        "opus":   "claude-opus-4-8",
        // opusplan and best intentionally excluded: bimodal / provider-conditional
    ]
    static let defaults = PricingTable(profiles: [
        "claude-fable-5":    PricingProfile(label: "Claude Fable 5",    input: 10,   output: 50, cw5m: 12.50, cw1h: 20,   read: 1.00),
        "claude-mythos-5":   PricingProfile(label: "Claude Mythos 5 (limited availability)", input: 10, output: 50, cw5m: 12.50, cw1h: 20, read: 1.00),
        "claude-opus-4-8":   PricingProfile(label: "Claude Opus 4.8",   input: 5,    output: 25, cw5m: 6.25,  cw1h: 10,   read: 0.50),
        "claude-opus-4-7":   PricingProfile(label: "Claude Opus 4.7",   input: 5,    output: 25, cw5m: 6.25,  cw1h: 10,   read: 0.50),
        "claude-opus-4-6":   PricingProfile(label: "Claude Opus 4.6",   input: 5,    output: 25, cw5m: 6.25,  cw1h: 10,   read: 0.50),
        "claude-opus-4-5":   PricingProfile(label: "Claude Opus 4.5",   input: 5,    output: 25, cw5m: 6.25,  cw1h: 10,   read: 0.50),
        "claude-opus-4-1":   PricingProfile(label: "Claude Opus 4.1 (deprecated)", input: 15, output: 75, cw5m: 18.75, cw1h: 30, read: 1.50),
        "claude-opus-4-0":   PricingProfile(label: "Claude Opus 4 (retired)",     input: 15, output: 75, cw5m: 18.75, cw1h: 30, read: 1.50),
        // Introductory pricing through Aug 31, 2026; reverts to $3/$15 (standard rate) after.
        "claude-sonnet-5": PricingProfile(label: "Claude Sonnet 5", input: 2,    output: 10, cw5m: 2.50,  cw1h: 4,    read: 0.20),
        "claude-sonnet-4-6": PricingProfile(label: "Claude Sonnet 4.6", input: 3,    output: 15, cw5m: 3.75,  cw1h: 6,    read: 0.30),
        "claude-sonnet-4-5": PricingProfile(label: "Claude Sonnet 4.5", input: 3,    output: 15, cw5m: 3.75,  cw1h: 6,    read: 0.30),
        "claude-sonnet-4-0": PricingProfile(label: "Claude Sonnet 4 (retired)",   input: 3,  output: 15, cw5m: 3.75,  cw1h: 6,  read: 0.30),
        "claude-haiku-4-5":  PricingProfile(label: "Claude Haiku 4.5",  input: 1,    output: 5,  cw5m: 1.25,  cw1h: 2,    read: 0.10),
        "claude-haiku-3-5":  PricingProfile(label: "Claude Haiku 3.5 (retired)",   input: 0.80, output: 4, cw5m: 1.00, cw1h: 1.60, read: 0.08),
    ], aliasMap: defaultAliases)

    /// Cost for a token bucket set under a given model. `missing` when the model
    /// has no profile → billed at 0 with a "prix manquant" badge.
    func cost(_ t: TokenBuckets, model: String) -> (cost: Double, missing: Bool) {
        guard let p = profiles[resolve(model)] else { return (0, true) }
        let c = (Double(t.input) * p.input
                 + Double(t.output) * p.output
                 + Double(t.cacheWrite5m) * p.cw5m
                 + Double(t.cacheWrite1h) * p.cw1h
                 + Double(t.cacheRead) * p.read) / 1e6
        return (c, false)
    }

    /// Display label for a model id, falling back to coarse family detection.
    func modelLabel(_ model: String) -> String {
        let a = resolve(model)
        if let p = profiles[a] { return p.label.replacingOccurrences(of: "Claude ", with: "") }
        if a.contains("opus") { return "Opus" }
        if a.contains("sonnet") { return "Sonnet" }
        if a.contains("haiku") { return "Haiku" }
        return a.isEmpty ? "?" : a
    }

    // Persistence (App Support)
    static func load() -> PricingTable {
        guard let data = try? Data(contentsOf: Paths.pricingFile),
              let t = try? JSONDecoder().decode(PricingTable.self, from: data) else {
            return .defaults
        }
        // Ensure default models are always present even if file predates them.
        var merged = t
        for (k, v) in PricingTable.defaults.profiles where merged.profiles[k] == nil {
            merged.profiles[k] = v
        }
        for (k, v) in PricingTable.defaultAliases where merged.aliasMap[k] == nil {
            merged.aliasMap[k] = v
        }
        return merged
    }

    /// Returns false on failure so the caller can surface it (user-edited rates lost silently otherwise).
    @discardableResult
    func save() -> Bool {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(self) else { return false }
        do { try data.write(to: Paths.pricingFile, options: .atomic); return true }
        catch { return false }
    }
}

extension PricingTable {
    // CodingKeys declared here so encode(to:) synthesis covers aliasMap
    // while init(from:) in extension preserves the memberwise initializer.
    enum CodingKeys: String, CodingKey { case profiles, aliasMap }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        profiles = try c.decode([String: PricingProfile].self, forKey: .profiles)
        aliasMap = (try? c.decode([String: String].self, forKey: .aliasMap)) ?? [:]
    }

    /// Strip `[1m]`, resolve CC alias → concrete model id, then normalize a
    /// trailing dated-snapshot suffix (e.g. "claude-haiku-4-5-20251001") down
    /// to the base id the profiles table is keyed by.
    func resolve(_ model: String) -> String {
        let stripped = model.replacingOccurrences(of: "[1m]", with: "")
        if let mapped = aliasMap[stripped] { return mapped }
        if profiles[stripped] != nil { return stripped }
        if let range = stripped.range(of: #"-\d{8}$"#, options: .regularExpression) {
            return String(stripped[..<range.lowerBound])
        }
        return stripped
    }
}

#if DEBUG
func pricingResolveSelfCheck() {
    let t = PricingTable.load()
    assert(t.resolve("claude-haiku-4-5-20251001") == "claude-haiku-4-5")
    assert(t.resolve("sonnet") == PricingTable.defaultAliases["sonnet"])
    assert(t.resolve("claude-opus-4-8") == "claude-opus-4-8")
}
#endif
