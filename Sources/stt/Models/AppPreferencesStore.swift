import Foundation

@MainActor
final class AppPreferencesStore: ObservableObject {
    @Published var injectionMode: TextInjectionMode {
        didSet { persist() }
    }

    @Published var appLanguage: AppLanguage {
        didSet { persist() }
    }

    @Published private(set) var hotkeyEnabled: Bool {
        didSet { persist() }
    }

    @Published var autoUnloadIdleModel: Bool {
        didSet { persist() }
    }

    private enum Keys {
        static let injectionMode = "app.preferences.injectionMode"
        static let appLanguage = "app.preferences.language"
        static let hotkeyEnabled = "app.preferences.hotkey.enabled"
        static let autoUnloadIdleModel = "app.preferences.autoUnloadIdleModel"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let rawMode = defaults.string(forKey: Keys.injectionMode) ?? TextInjectionMode.clipboardThenPaste.rawValue
        injectionMode = TextInjectionMode(rawValue: rawMode) ?? .clipboardThenPaste
        appLanguage = AppLanguage.fromPersistedCode(defaults.string(forKey: Keys.appLanguage))

        if defaults.object(forKey: Keys.hotkeyEnabled) == nil {
            hotkeyEnabled = true
        } else {
            hotkeyEnabled = defaults.bool(forKey: Keys.hotkeyEnabled)
        }

        if defaults.object(forKey: Keys.autoUnloadIdleModel) == nil {
            autoUnloadIdleModel = true
        } else {
            autoUnloadIdleModel = defaults.bool(forKey: Keys.autoUnloadIdleModel)
        }
    }

    func setHotkeyEnabled(_ enabled: Bool) {
        hotkeyEnabled = enabled
    }

    private func persist() {
        defaults.set(injectionMode.rawValue, forKey: Keys.injectionMode)
        defaults.set(appLanguage.persistedCode, forKey: Keys.appLanguage)
        defaults.set(hotkeyEnabled, forKey: Keys.hotkeyEnabled)
        defaults.set(autoUnloadIdleModel, forKey: Keys.autoUnloadIdleModel)
    }
}
