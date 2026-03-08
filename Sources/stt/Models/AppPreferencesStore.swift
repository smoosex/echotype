import Foundation

@MainActor
final class AppPreferencesStore: ObservableObject {
    @Published var injectionMode: TextInjectionMode {
        didSet { persist() }
    }

    @Published var keepAudioFiles: Bool {
        didSet { persist() }
    }

    @Published var appLanguage: AppLanguage {
        didSet { persist() }
    }

    @Published private(set) var hotkeyEnabled: Bool {
        didSet { persist() }
    }

    private enum Keys {
        static let injectionMode = "app.preferences.injectionMode"
        static let keepAudioFiles = "app.preferences.keepAudioFiles"
        static let appLanguage = "app.preferences.language"
        static let hotkeyEnabled = "app.preferences.hotkey.enabled"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let rawMode = defaults.string(forKey: Keys.injectionMode) ?? TextInjectionMode.clipboardThenPaste.rawValue
        injectionMode = TextInjectionMode(rawValue: rawMode) ?? .clipboardThenPaste
        keepAudioFiles = defaults.bool(forKey: Keys.keepAudioFiles)
        appLanguage = AppLanguage.fromPersistedCode(defaults.string(forKey: Keys.appLanguage))

        if defaults.object(forKey: Keys.hotkeyEnabled) == nil {
            hotkeyEnabled = true
        } else {
            hotkeyEnabled = defaults.bool(forKey: Keys.hotkeyEnabled)
        }
    }

    func setHotkeyEnabled(_ enabled: Bool) {
        hotkeyEnabled = enabled
    }

    private func persist() {
        defaults.set(injectionMode.rawValue, forKey: Keys.injectionMode)
        defaults.set(keepAudioFiles, forKey: Keys.keepAudioFiles)
        defaults.set(appLanguage.persistedCode, forKey: Keys.appLanguage)
        defaults.set(hotkeyEnabled, forKey: Keys.hotkeyEnabled)
    }
}
