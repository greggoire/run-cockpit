import Foundation

extension Language {
    /// The compiled .lproj sub-bundle for this language (en.lproj / fr.lproj).
    /// ponytail: Bundle(path:) is uniqued by Foundation, cheap on repeat;
    /// memoize into [Language: Bundle] only if profiling ever flags it.
    var bundle: Bundle {
        Bundle.main.path(forResource: rawValue, ofType: "lproj")
            .flatMap(Bundle.init(path:)) ?? .main
    }

    /// Endonym shown in the language picker (never itself translated).
    var displayName: String {
        switch self {
        case .en: return "English"
        case .fr: return "Français"
        }
    }
}

/// Resolve `key` in `lang`. Key == the English source string (String Catalog
/// default), so a missing entry falls back to the key itself → English is
/// always a safe fallback, never a raw missing-key.
func tr(_ key: String, _ lang: Language, _ args: [CVarArg] = []) -> String {
    // English IS the source string (= the key), so resolve it directly — never
    // touch a bundle, which would otherwise leak the system language on a
    // non-English Mac. Only non-source languages look up the compiled table.
    let s = lang == .en ? key : lang.bundle.localizedString(forKey: key, value: key, table: nil)
    return args.isEmpty ? s : String(format: s, arguments: args)
}

extension AppState {
    /// View-facing accessor. Reactive: reads `settings.language`, so any view
    /// `body` that calls it re-renders the instant the language changes.
    func t(_ key: String, _ args: CVarArg...) -> String {
        tr(key, settings.language, args)
    }
}
