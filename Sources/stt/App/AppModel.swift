import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    let stateStore = AppStateStore()
    let sttConfigurationStore = STTConfigurationStore()
    let preferencesStore = AppPreferencesStore()

    @Published private(set) var hotkeyHint = HotkeyShortcut.defaultShortcut.hint
    @Published private(set) var hotkeyGlyphHint = HotkeyShortcut.defaultShortcut.glyphHint
    @Published private(set) var hotkeyEnabled = true
    @Published private(set) var hotkeyError: String?
    @Published private(set) var hotkeyWarning: String?
    @Published private(set) var currentLanguage: AppLanguage
    @Published private(set) var microphonePermission: PermissionState = .notDetermined
    @Published private(set) var accessibilityPermission: PermissionState = .denied
    @Published private(set) var onboardingCompleted: Bool

    private let hotkeyService = HotkeyService()
    private let permissionService = PermissionService()
    private let onboardingWindowService = OnboardingWindowService()
    private let onboardingDefaultsKey = "onboarding.completed"
    private let recordingCoordinator: RecordingCoordinator

    private var lastKnownShortcut = HotkeyShortcut.defaultShortcut
    private var onboardingDontShowAgainSelection = false
    private var openSettingsWindowHandler: (() -> Void)?
    private var onboardingAutoPresentationTask: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    init() {
        recordingCoordinator = RecordingCoordinator(stateStore: stateStore)

        let initialLanguage = preferencesStore.appLanguage
        currentLanguage = initialLanguage
        onboardingCompleted = UserDefaults.standard.bool(forKey: onboardingDefaultsKey)
        onboardingDontShowAgainSelection = onboardingCompleted
        bindLanguageChanges()
        refreshPermissionStates()
        configureHotkey()
        scheduleOnboardingPresentationIfNeeded()
    }

    private func bindLanguageChanges() {
        preferencesStore.$appLanguage
            .removeDuplicates()
            .sink { [weak self] language in
                guard let self else { return }
                currentLanguage = language
                applyHotkeyPresentation(shortcut: lastKnownShortcut, enabled: hotkeyEnabled)
                refreshOnboardingWindowIfNeeded()
            }
            .store(in: &cancellables)
    }

    func handlePrimaryAction() {
        refreshPermissionStates()
        switch stateStore.state {
        case .idle:
            recordingCoordinator.startRecording(configuration: sttConfigurationStore.makeConfiguration())
        case .recording:
            recordingCoordinator.stopRecording(injectionMode: preferencesStore.injectionMode)
        case .processing:
            break
        }
    }

    func requestMicrophonePermission() {
        Task { [weak self] in
            guard let self else { return }
            let state = await permissionService.requestMicrophonePermission()
            microphonePermission = state
            refreshPermissionStates()
            refreshOnboardingWindowIfNeeded()
            AppLogger.permissions.info("Microphone permission requested; state=\(state.rawValue)")
        }
    }

    func requestAccessibilityPermission() {
        _ = permissionService.requestAccessibilityPermission()
        refreshPermissionStates()
        refreshOnboardingWindowIfNeeded()
        AppLogger.permissions.info("Accessibility prompt requested")
    }

    func refreshPermissions() {
        refreshPermissionStates()
        refreshOnboardingWindowIfNeeded()
    }

    func openMicrophoneSettings() {
        permissionService.openMicrophoneSettings()
    }

    func openAccessibilitySettings() {
        permissionService.openAccessibilitySettings()
    }

    func completeOnboarding() {
        onboardingCompleted = true
        UserDefaults.standard.set(true, forKey: onboardingDefaultsKey)
        refreshOnboardingWindowIfNeeded()
    }

    func resetOnboarding() {
        onboardingCompleted = false
        UserDefaults.standard.set(false, forKey: onboardingDefaultsKey)
        refreshOnboardingWindowIfNeeded()
    }

    func openWelcomeGuide() {
        onboardingDontShowAgainSelection = onboardingCompleted
        onboardingWindowService.present(
            title: L10n.text(L10nKey.welcomeWindowTitle, language: currentLanguage),
            content: makeWelcomeGuideView()
        )
    }

    func dismissWelcomeGuide(dontShowAgain: Bool) {
        onboardingAutoPresentationTask?.cancel()
        onboardingAutoPresentationTask = nil
        onboardingWindowService.close()
        applyOnboardingPreference(dontShowAgain: dontShowAgain)
    }

    func startUsingFromWelcomeGuide(dontShowAgain: Bool) {
        onboardingAutoPresentationTask?.cancel()
        onboardingAutoPresentationTask = nil
        onboardingWindowService.close()
        applyOnboardingPreference(dontShowAgain: dontShowAgain)
        openSettingsWindow()
    }

    func openSettingsWindow() {
        openSettingsWindowHandler?()
    }

    func setOpenSettingsWindowHandler(_ handler: @escaping () -> Void) {
        openSettingsWindowHandler = handler
    }

    func setHotkeyEnabled(_ enabled: Bool) -> String? {
        if enabled {
            return enableHotkeyIfPossible()
        }

        hotkeyService.unregister()
        preferencesStore.setHotkeyEnabled(false)
        hotkeyEnabled = false
        hotkeyError = nil
        hotkeyWarning = HotkeyConflictAdvisor.warning(for: lastKnownShortcut)
        applyHotkeyPresentation(shortcut: lastKnownShortcut, enabled: false)
        AppLogger.app.info("Global hotkey disabled")
        return nil
    }

    func restoreDefaultHotkey() -> String? {
        let defaultShortcut = HotkeyShortcut.defaultShortcut
        return updateHotkey(
            keyCode: defaultShortcut.keyCode,
            modifiers: defaultShortcut.modifiers
        )
    }

    func updateHotkey(keyCode: UInt32, modifiers: UInt32) -> String? {
        let candidate = HotkeyShortcut(keyCode: keyCode, modifiers: modifiers)
        let isEnabled = preferencesStore.hotkeyEnabled

        do {
            try hotkeyService.register(shortcut: candidate)
            lastKnownShortcut = candidate
            if isEnabled {
                hotkeyService.enable()
            } else {
                hotkeyService.unregister()
            }
            applyHotkeyPresentation(shortcut: candidate, enabled: isEnabled)
            hotkeyError = nil
            hotkeyWarning = HotkeyConflictAdvisor.warning(for: candidate)
            AppLogger.app.info("Global hotkey updated: \(candidate.hint); enabled=\(isEnabled)")
            return nil
        } catch {
            let failureReason = error.localizedDescription
            let fallbackMessage = recoverWithDefaultHotkey(
                originalFailureReason: failureReason,
                isEnabled: isEnabled
            )
            AppLogger.app.error("Global hotkey update failed: \(fallbackMessage)")
            return fallbackMessage
        }
    }

    private func configureHotkey() {
        hotkeyService.onHotKeyPressed = { [weak self] in
            DispatchQueue.main.async {
                self?.handlePrimaryAction()
            }
        }

        let storedShortcut = hotkeyService.currentShortcut()
        let initialShortcut = storedShortcut ?? .defaultShortcut
        lastKnownShortcut = initialShortcut

        if storedShortcut == nil {
            do {
                try hotkeyService.register(shortcut: initialShortcut)
            } catch {
                hotkeyError = error.localizedDescription
                hotkeyWarning = nil
                preferencesStore.setHotkeyEnabled(false)
                hotkeyEnabled = false
                applyHotkeyPresentation(shortcut: initialShortcut, enabled: false)
                AppLogger.app.error("Default hotkey initialization failed: \(error.localizedDescription)")
                return
            }
        }

        hotkeyEnabled = preferencesStore.hotkeyEnabled
        if !hotkeyEnabled {
            hotkeyService.unregister()
            applyHotkeyPresentation(shortcut: initialShortcut, enabled: false)
            hotkeyError = nil
            hotkeyWarning = HotkeyConflictAdvisor.warning(for: initialShortcut)
            return
        }

        hotkeyService.enable()
        applyHotkeyPresentation(shortcut: initialShortcut, enabled: true)
        hotkeyEnabled = true
        hotkeyError = nil
        hotkeyWarning = HotkeyConflictAdvisor.warning(for: initialShortcut)
        AppLogger.app.info("Global hotkey ready: \(initialShortcut.hint)")
    }

    private func recoverWithDefaultHotkey(
        originalFailureReason: String,
        isEnabled: Bool
    ) -> String {
        let fallback = HotkeyShortcut.defaultShortcut
        do {
            try hotkeyService.register(shortcut: fallback)
            lastKnownShortcut = fallback
            if isEnabled {
                hotkeyService.enable()
            } else {
                hotkeyService.unregister()
            }
            applyHotkeyPresentation(shortcut: fallback, enabled: isEnabled)
            hotkeyWarning = HotkeyConflictAdvisor.warning(for: fallback)
            let message = L10n.text(
                L10nKey.hotkeyRevertedDefaultFormat,
                language: currentLanguage,
                originalFailureReason,
                fallback.hint
            )
            hotkeyError = message
            return message
        } catch {
            let message = L10n.text(
                L10nKey.hotkeyRevertDefaultFailedFormat,
                language: currentLanguage,
                originalFailureReason,
                error.localizedDescription
            )
            preferencesStore.setHotkeyEnabled(false)
            hotkeyEnabled = false
            applyHotkeyPresentation(shortcut: fallback, enabled: false)
            hotkeyError = message
            AppLogger.app.error("Failed to recover default hotkey: \(error.localizedDescription)")
            hotkeyWarning = nil
            return message
        }
    }

    private func enableHotkeyIfPossible() -> String? {
        let shortcut = hotkeyService.currentShortcut() ?? lastKnownShortcut

        do {
            if hotkeyService.currentShortcut() == nil {
                try hotkeyService.register(shortcut: shortcut)
            }
            lastKnownShortcut = shortcut
            hotkeyService.enable()
            preferencesStore.setHotkeyEnabled(true)
            hotkeyEnabled = true
            applyHotkeyPresentation(shortcut: shortcut, enabled: true)
            hotkeyError = nil
            hotkeyWarning = HotkeyConflictAdvisor.warning(for: shortcut)
            AppLogger.app.info("Global hotkey enabled: \(shortcut.hint)")
            return nil
        } catch {
            preferencesStore.setHotkeyEnabled(false)
            hotkeyEnabled = false
            applyHotkeyPresentation(shortcut: shortcut, enabled: false)
            hotkeyWarning = nil
            hotkeyError = error.localizedDescription
            AppLogger.app.error("Global hotkey enable failed: \(error.localizedDescription)")
            return error.localizedDescription
        }
    }

    private func applyHotkeyPresentation(shortcut: HotkeyShortcut, enabled: Bool) {
        hotkeyHint = formatHotkeyHint(shortcut: shortcut, enabled: enabled)
        hotkeyGlyphHint = shortcut.glyphHint
    }

    private func formatHotkeyHint(shortcut: HotkeyShortcut, enabled: Bool) -> String {
        let base = shortcut.hint
        if enabled {
            return base
        }
        return L10n.text(L10nKey.appHotkeyDisabledFormat, language: currentLanguage, base)
    }

    private func refreshPermissionStates() {
        microphonePermission = permissionService.microphoneState()
        accessibilityPermission = permissionService.accessibilityState()
    }

    private func scheduleOnboardingPresentationIfNeeded() {
        guard !onboardingCompleted else { return }
        onboardingAutoPresentationTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard !self.onboardingCompleted else { return }
            self.openWelcomeGuide()
        }
        onboardingAutoPresentationTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: task)
    }

    private func refreshOnboardingWindowIfNeeded() {
        onboardingWindowService.update(
            title: L10n.text(L10nKey.welcomeWindowTitle, language: currentLanguage),
            content: makeWelcomeGuideView()
        )
    }

    private func makeWelcomeGuideView() -> WelcomeGuideView {
        WelcomeGuideView(
            appLanguage: currentLanguage,
            microphonePermission: microphonePermission,
            accessibilityPermission: accessibilityPermission,
            initiallyDontShowAgain: onboardingDontShowAgainSelection,
            onRequestMicrophone: { [weak self] in self?.requestMicrophonePermission() },
            onRequestAccessibility: { [weak self] in self?.requestAccessibilityPermission() },
            onRefreshPermissions: { [weak self] in self?.refreshPermissions() },
            onOpenMicrophoneSettings: { [weak self] in self?.openMicrophoneSettings() },
            onOpenAccessibilitySettings: { [weak self] in self?.openAccessibilitySettings() },
            onDontShowAgainChanged: { [weak self] value in
                self?.onboardingDontShowAgainSelection = value
            },
            onStartUsing: { [weak self] dontShowAgain in
                self?.startUsingFromWelcomeGuide(dontShowAgain: dontShowAgain)
            },
            onDismiss: { [weak self] dontShowAgain in
                self?.dismissWelcomeGuide(dontShowAgain: dontShowAgain)
            }
        )
    }

    private func applyOnboardingPreference(dontShowAgain: Bool) {
        if dontShowAgain {
            completeOnboarding()
        } else {
            resetOnboarding()
        }
    }
}
