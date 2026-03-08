import Foundation

enum L10nKey {
    static let commonOk = "common.ok"

    static let menuShortcutsFormat = "menu.shortcuts_format"
    static let menuNotSet = "menu.not_set"
    static let menuSettings = "menu.settings"
    static let menuQuit = "menu.quit"
    static let menuWelcomeGuide = "menu.welcome_guide"
    static let menuWelcomeGuideNew = "menu.welcome_guide_new"

    static let settingsTabGeneral = "settings.tab.general"
    static let settingsTabEngine = "settings.tab.engine"
    static let settingsSectionLanguage = "settings.section.language"
    static let settingsLanguage = "settings.language"
    static let settingsSectionStatus = "settings.section.status"
    static let settingsCurrentState = "settings.current_state"
    static let settingsHotkey = "settings.hotkey"
    static let settingsSectionHotkey = "settings.section.hotkey"
    static let settingsGlobalShortcut = "settings.global_shortcut"
    static let settingsEnableGlobalHotkey = "settings.enable_global_hotkey"
    static let settingsDefault = "settings.default"
    static let settingsHotkeyHelp = "settings.hotkey_help"
    static let settingsHotkeyRestoredDefault = "settings.hotkey_restored_default"
    static let settingsHotkeyClearedReverted = "settings.hotkey_cleared_reverted"
    static let settingsHotkeyUpdatedFormat = "settings.hotkey_updated_format"
    static let settingsGlobalHotkeyEnabled = "settings.global_hotkey_enabled"
    static let settingsGlobalHotkeyDisabled = "settings.global_hotkey_disabled"
    static let settingsEnabled = "settings.enabled"
    static let settingsDisabled = "settings.disabled"
    static let settingsSectionBehavior = "settings.section.behavior"
    static let settingsInjectionMode = "settings.injection_mode"
    static let settingsSectionPermissions = "settings.section.permissions"
    static let settingsRefreshStatus = "settings.refresh_status"
    static let settingsPermissionsHelp = "settings.permissions_help"
    static let settingsSectionPrivacy = "settings.section.privacy"
    static let settingsKeepTempAudio = "settings.keep_temp_audio"
    static let settingsKeepTempAudioHelp = "settings.keep_temp_audio_help"
    static let settingsInstall = "settings.install"
    static let settingsSectionLanguageHint = "settings.section.language_hint"
    static let settingsSectionModel = "settings.section.model"
    static let settingsModel = "settings.model"
    static let settingsDelete = "settings.delete"
    static let settingsInstalled = "settings.installed"
    static let settingsNotInstalled = "settings.not_installed"
    static let settingsModelOptionFormat = "settings.model_option_format"

    static let permissionMicrophone = "permission.microphone"
    static let permissionAccessibility = "permission.accessibility"
    static let permissionRequest = "permission.request"
    static let permissionOpenSettings = "permission.open_settings"
    static let permissionAuthorized = "permission.authorized"
    static let permissionDenied = "permission.denied"
    static let permissionRestricted = "permission.restricted"
    static let permissionNotDetermined = "permission.not_determined"

    static let welcomeWindowTitle = "welcome.window_title"
    static let welcomeTitle = "welcome.title"
    static let welcomeSubtitle = "welcome.subtitle"
    static let welcomePermissions = "welcome.permissions"
    static let welcomeHowItWorks = "welcome.how_it_works"
    static let welcomeRefreshStatus = "welcome.refresh_status"
    static let welcomeStep1 = "welcome.step1"
    static let welcomeStep2 = "welcome.step2"
    static let welcomeStep3 = "welcome.step3"
    static let welcomeStep4 = "welcome.step4"
    static let welcomeDontShowAgain = "welcome.dont_show_again"
    static let welcomeClose = "welcome.close"
    static let welcomeStartUsing = "welcome.start_using"

    static let languageOptionAuto = "language.option.auto"
    static let languageOptionChinese = "language.option.chinese"
    static let languageOptionEnglish = "language.option.english"

    static let stateIdle = "state.idle"
    static let stateRecording = "state.recording"
    static let stateProcessing = "state.processing"
    static let stateErrorFormat = "state.error_format"

    static let injectionModeClipboardOnly = "injection.mode.clipboard_only"
    static let injectionModeClipboardPaste = "injection.mode.clipboard_paste"
    static let errorClipboardFailed = "error.clipboard_failed"
    static let errorPasteFailed = "error.paste_failed"

    static let whisperTranscriptionAuto = "whisper_transcription.auto"
    static let whisperTranscriptionChinese = "whisper_transcription.chinese"
    static let whisperTranscriptionEnglish = "whisper_transcription.english"

    static let appInjectionIdle = "app.injection.idle"
    static let appPerformanceNoSamples = "app.performance.no_samples"
    static let appMetricsNA = "app.metrics.na"
    static let appSelfTestNotRun = "app.selftest.not_run"
    static let appHotkeyDisabledFormat = "app.hotkey.disabled_format"
    static let appTranscriptionProcessing = "app.transcription.processing"
    static let appTranscriptionSuccess = "app.transcription.success"
    static let appTranscriptionErrorFormat = "app.transcription.error_format"
    static let appInjectionPasted = "app.injection.pasted"
    static let appInjectionCopied = "app.injection.copied"
    static let appInjectionFallbackCopied = "app.injection.fallback_copied"
    static let appInjectionSkipped = "app.injection.skipped"
    static let appPerformanceSummaryWithP50Format = "app.performance.summary_with_p50_format"
    static let appPerformanceSummaryBasicFormat = "app.performance.summary_basic_format"
    static let appPerformanceReadinessReady = "app.performance.readiness_ready"
    static let appPerformanceReadinessCollecting = "app.performance.readiness_collecting"

    static let sttReady = "stt.ready"
    static let sttSelectedModelNotInstalledFormat = "stt.selected_model_not_installed_format"
    static let sttInstallingFormat = "stt.installing_format"
    static let sttLoadingFormat = "stt.loading_format"
    static let sttInstalledFormat = "stt.installed_format"
    static let sttDeletingFormat = "stt.deleting_format"
    static let sttDeletedFormat = "stt.deleted_format"
    static let sttInstallFailed = "stt.install_failed"
    static let sttDeleteFailedWithDetailFormat = "stt.delete_failed_with_detail_format"

    static let errorTranscriptionOutputEmpty = "error.transcription_output_empty"
    static let errorSTTModelNotInstalledFormat = "error.stt_model_not_installed_format"
    static let errorWhisperKitLoadFailedFormat = "error.whisperkit_load_failed_format"
    static let errorQwenLoadFailedFormat = "error.qwen_load_failed_format"
    static let errorSTTTranscriptionFailedFormat = "error.stt_transcription_failed_format"
    static let errorSTTTimeoutFormat = "error.stt_timeout_format"

    static let hotkeyConflictSpotlight = "hotkey.conflict.spotlight"
    static let hotkeyConflictInputSource = "hotkey.conflict.input_source"
    static let hotkeyConflictAppSwitcher = "hotkey.conflict.app_switcher"
    static let hotkeyConflictWindowCycle = "hotkey.conflict.window_cycle"
    static let hotkeyConflictQuit = "hotkey.conflict.quit"
    static let hotkeyRegistrationFailedFormat = "hotkey.registration_failed_format"
    static let hotkeyDispatcherUnavailable = "hotkey.dispatcher_unavailable"
    static let hotkeyAlreadyInUse = "hotkey.already_in_use"
    static let hotkeyRejectedBySystem = "hotkey.rejected_by_system"
    static let hotkeyInvalidCombination = "hotkey.invalid_combination"
    static let hotkeyUnknownError = "hotkey.unknown_error"
    static let hotkeyRevertedDefaultFormat = "hotkey.reverted_default_format"
    static let hotkeyRevertDefaultFailedFormat = "hotkey.revert_default_failed_format"
}

struct L10n {
    static func text(_ key: String, language: AppLanguage, _ args: CVarArg...) -> String {
        let code = language.resolvedLocalizationCode()
        return localizedText(for: key, code: code, args: args)
    }

    static func text(_ key: String, _ args: CVarArg...) -> String {
        let code = AppLanguage.current().resolvedLocalizationCode()
        return localizedText(for: key, code: code, args: args)
    }

    private static func localizedText(for key: String, code: String, args: [CVarArg]) -> String {
        let bundle = bundle(for: code)
        let localized = bundle.localizedString(forKey: key, value: nil, table: "Localizable")
        let base = localized == key ? Bundle.module.localizedString(forKey: key, value: key, table: "Localizable") : localized

        guard !args.isEmpty else { return base }
        let locale = Locale(identifier: code)
        return String(format: base, locale: locale, arguments: args)
    }

    private static func bundle(for code: String) -> Bundle {
        for candidate in lprojCandidates(for: code) {
            if let path = Bundle.module.path(forResource: candidate, ofType: "lproj"),
               let localizedBundle = Bundle(path: path) {
                return localizedBundle
            }
        }

        return Bundle.module
    }

    private static func lprojCandidates(for code: String) -> [String] {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var candidates: [String] = [trimmed]
        candidates.append(trimmed.lowercased())
        candidates.append(trimmed.replacingOccurrences(of: "_", with: "-"))
        candidates.append(trimmed.replacingOccurrences(of: "-", with: "_"))

        let lowered = trimmed
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
        if lowered == "zh-hans" {
            candidates.append("zh-Hans")
            candidates.append("zh_hans")
        } else if lowered == "zh-hant" {
            candidates.append("zh-Hant")
            candidates.append("zh_hant")
        }

        var deduped: [String] = []
        var seen = Set<String>()
        for item in candidates where !item.isEmpty {
            if seen.insert(item).inserted {
                deduped.append(item)
            }
        }
        return deduped
    }
}

extension AppLanguage {
    var localizedOptionTitle: String {
        localizedOptionTitle(in: .current())
    }

    func localizedOptionTitle(in displayLanguage: AppLanguage) -> String {
        switch self {
        case .auto:
            return L10n.text(L10nKey.languageOptionAuto, language: displayLanguage)
        case .zhHans:
            return L10n.text(L10nKey.languageOptionChinese, language: displayLanguage)
        case .english:
            return L10n.text(L10nKey.languageOptionEnglish, language: displayLanguage)
        }
    }
}
