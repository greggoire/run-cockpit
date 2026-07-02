import Foundation

enum AppearanceMode: String, Codable, Sendable, CaseIterable {
    case dark, light
}

/// UI language. rawValue matches the compiled .lproj folder name (en.lproj / fr.lproj).
enum Language: String, Codable, Sendable, CaseIterable {
    case en, fr
}

/// Tab shown when the app launches (mapped to `Route` in AppState).
enum StartTab: String, Codable, Sendable, CaseIterable {
    case active, stats, history
}

/// User preferences, persisted in App Support (never under ~/.claude).
/// Named `AppSettings` to avoid colliding with SwiftUI's `Settings` scene.
struct AppSettings: Codable, Sendable, Equatable {
    var appearance: AppearanceMode = .dark      // mockup default
    var notificationsEnabled: Bool = true       // in-app toggle, independent of OS authorization
    var notificationSound: Bool = true          // play a sound with the notification
    var editorAppPath: String? = nil            // IDE chosen by the user for the "IDE" button
    var startTab: StartTab = .active            // landing tab at launch
    var defaultPeriod: Int = -1                 // default stats/history period (-1=sem, -2=mois, -3=an, 0=tout)
    var language: Language = .en                // UI language; English is the base/default
    var groupByGitRemote: Bool = false          // collapse git worktrees/clones by remote URL
    var weekStartDay: Int = 2                   // Calendar.firstWeekday: 1=Sun, 2=Mon, 7=Sat

    init() {}

    // Tolerate missing keys so older settings.json files (written before a field
    // existed) keep their stored values instead of resetting everything to defaults.
    // Synthesized Codable would throw keyNotFound, which load()'s `try?` swallows.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        appearance = try c.decodeIfPresent(AppearanceMode.self, forKey: .appearance) ?? .dark
        notificationsEnabled = try c.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? true
        notificationSound = try c.decodeIfPresent(Bool.self, forKey: .notificationSound) ?? true
        weekStartDay      = try c.decodeIfPresent(Int.self,  forKey: .weekStartDay)      ?? 2
        editorAppPath = try c.decodeIfPresent(String.self, forKey: .editorAppPath)
        startTab = try c.decodeIfPresent(StartTab.self, forKey: .startTab) ?? .active
        defaultPeriod = try c.decodeIfPresent(Int.self, forKey: .defaultPeriod) ?? -1
        language = try c.decodeIfPresent(Language.self, forKey: .language) ?? .en
        groupByGitRemote = try c.decodeIfPresent(Bool.self, forKey: .groupByGitRemote) ?? false
    }

    static func load() -> AppSettings {
        guard let data = try? Data(contentsOf: Paths.settingsFile),
              let s = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return s
    }

    /// Returns false on failure so the caller can surface it — losing edited user
    /// settings silently is the one write worth reporting (unlike the self-healing cache).
    @discardableResult
    func save() -> Bool {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(self) else { return false }
        do { try data.write(to: Paths.settingsFile, options: .atomic); return true }
        catch { return false }
    }
}
