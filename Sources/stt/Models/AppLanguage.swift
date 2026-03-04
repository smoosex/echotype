import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case auto
    case zhHans = "zh-Hans"
    case english = "en"

    var id: String { rawValue }

    var persistedCode: String { rawValue }

    static func fromPersistedCode(_ code: String?) -> AppLanguage {
        guard let trimmed = code?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return .auto
        }

        let normalized = trimmed
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
        switch normalized {
        case "zh", "zh-hans":
            return .zhHans
        case "en":
            return .english
        case "auto":
            return .auto
        default:
            return AppLanguage(rawValue: trimmed) ?? .auto
        }
    }

    static func current(defaults: UserDefaults = .standard) -> AppLanguage {
        fromPersistedCode(defaults.string(forKey: "app.preferences.language"))
    }

    func resolvedLocalizationCode(preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        switch self {
        case .auto:
            let preferred = preferredLanguages.first?.lowercased() ?? "en"
            return preferred.hasPrefix("zh") ? "zh-hans" : "en"
        case .zhHans:
            return "zh-hans"
        case .english:
            return "en"
        }
    }
}
