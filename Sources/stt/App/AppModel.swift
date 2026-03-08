import Foundation
import Combine

@MainActor
final class AppModel: ObservableObject {
    let stateStore = AppStateStore()
    let sttConfigurationStore = STTConfigurationStore()
    let preferencesStore = AppPreferencesStore()

    @Published private(set) var hotkeyHint = HotkeyShortcut.defaultShortcut.hint
    @Published private(set) var hotkeyGlyphHint = HotkeyShortcut.defaultShortcut.glyphHint
    @Published private(set) var hotkeyKeyCode = HotkeyShortcut.defaultShortcut.keyCode
    @Published private(set) var hotkeyModifiers = HotkeyShortcut.defaultShortcut.normalizedModifiers
    @Published private(set) var hotkeyEnabled = true
    @Published private(set) var hotkeyError: String?
    @Published private(set) var hotkeyWarning: String?
    @Published private(set) var currentLanguage: AppLanguage
    @Published private(set) var lastRecordingFile: String?
    @Published private(set) var lastAudioValidation: String?
    @Published private(set) var lastTranscription: String?
    @Published private(set) var transcriptionHint: String
    @Published private(set) var injectionStatus: String
    @Published private(set) var microphonePermission: PermissionState = .notDetermined
    @Published private(set) var accessibilityPermission: PermissionState = .denied
    @Published private(set) var onboardingCompleted: Bool
    @Published private(set) var performanceSummary: String
    @Published private(set) var metricsDirectoryPath: String
    @Published private(set) var selfTestSummary: String
    @Published private(set) var recordingLevel: Double = 0

    private let hotkeyService = HotkeyService()
    private let audioService = AudioService()
    private let wavValidationService = WAVValidationService()
    private let textInjectionService = TextInjectionService()
    private let permissionService = PermissionService()
    private let onboardingWindowService = OnboardingWindowService()
    private let recordingOverlayWindowService = RecordingOverlayWindowService()
    private let processMetricsSampler = ProcessMetricsSampler()
    private let performanceReportService = PerformanceReportService()
    private let stabilitySelfTestService = StabilitySelfTestService()
    private let onboardingDefaultsKey = "onboarding.completed"
    private let minimumPerformanceSamples = 20
    private struct RecordingPreparation {
        let configuration: STTConfiguration
        let task: Task<Bool, Never>
    }

    private var lastKnownShortcut = HotkeyShortcut.defaultShortcut
    private var onboardingDontShowAgainSelection = false
    private var openSettingsWindowHandler: (() -> Void)?
    private var onboardingAutoPresentationTask: DispatchWorkItem?
    private var pipelineFeedback: PipelineFeedback = .readiness
    private var performanceBaselineReport: PerformanceBaselineReport?
    private var recordingPreparation: RecordingPreparation?
    private var selfTestExecuted = false
    private var cancellables = Set<AnyCancellable>()

    init() {
        let initialLanguage = preferencesStore.appLanguage
        currentLanguage = initialLanguage
        transcriptionHint = ""
        injectionStatus = L10n.text(L10nKey.appInjectionIdle, language: initialLanguage)
        performanceSummary = L10n.text(L10nKey.appPerformanceNoSamples, language: initialLanguage)
        metricsDirectoryPath = L10n.text(L10nKey.appMetricsNA, language: initialLanguage)
        selfTestSummary = L10n.text(L10nKey.appSelfTestNotRun, language: initialLanguage)
        onboardingCompleted = UserDefaults.standard.bool(forKey: onboardingDefaultsKey)
        onboardingDontShowAgainSelection = onboardingCompleted
        metricsDirectoryPath = performanceReportService.metricsDirectoryPath()
        bindLanguageChanges()
        bindSTTConfigurationChanges()
        bindRecordingLevelChanges()
        refreshPermissionStates()
        applyPipelineFeedback(.readiness)
        refreshPerformanceSummary()
        configureHotkey()
        scheduleOnboardingPresentationIfNeeded()
        Task { [weak self] in
            await self?.loadPersistedPerformanceReport()
        }
    }

    private func bindLanguageChanges() {
        preferencesStore.$appLanguage
            .removeDuplicates()
            .sink { [weak self] language in
                guard let self else { return }
                currentLanguage = language
                applyPipelineFeedback(pipelineFeedback)
                if !selfTestExecuted {
                    selfTestSummary = L10n.text(L10nKey.appSelfTestNotRun, language: language)
                }
                refreshPerformanceSummary()
                applyHotkeyPresentation(shortcut: lastKnownShortcut, enabled: hotkeyEnabled)
                refreshOnboardingWindowIfNeeded()
            }
            .store(in: &cancellables)
    }

    private func bindSTTConfigurationChanges() {
        sttConfigurationStore.$readinessRevision
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                guard case .readiness = pipelineFeedback else { return }
                applyPipelineFeedback(.readiness)
            }
            .store(in: &cancellables)
    }

    private func bindRecordingLevelChanges() {
        audioService.recordingLevelPublisher
            .removeDuplicates(by: { abs($0 - $1) < 0.01 })
            .sink { [weak self] level in
                guard let self else { return }
                recordingLevel = level
                recordingOverlayWindowService.updateLevel(level)
            }
            .store(in: &cancellables)
    }

    func handlePrimaryAction() {
        refreshPermissionStates()
        switch stateStore.state {
        case .idle:
            startRecordingFlow()
        case .recording:
            stopRecordingFlow()
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

    func runStabilitySelfTest(iterations: Int = 200) {
        Task { [weak self] in
            guard let self else { return }
            let result = await stabilitySelfTestService.run(
                iterations: iterations,
                stateStore: stateStore,
                textInjectionService: textInjectionService
            )
            selfTestExecuted = true
            selfTestSummary = result.summary
            AppLogger.app.info("Stability self-test completed: \(result.summary)")
        }
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
        hotkeyKeyCode = shortcut.keyCode
        hotkeyModifiers = shortcut.normalizedModifiers
    }

    private func formatHotkeyHint(shortcut: HotkeyShortcut, enabled: Bool) -> String {
        let base = shortcut.hint
        if enabled {
            return base
        }
        return L10n.text(L10nKey.appHotkeyDisabledFormat, language: currentLanguage, base)
    }

    private func startRecordingFlow() {
        do {
            try audioService.startRecording()
            stateStore.startRecording()
            startRecordingPreparation()
            lastTranscription = nil
            lastAudioValidation = nil
            showRecordingOverlay()
            applyPipelineFeedback(.readiness)
            AppLogger.audio.info("Recording started")
        } catch {
            hideRecordingOverlay()
            stateStore.reset()
            applyPipelineFeedback(.failure(error.localizedDescription))
            AppLogger.audio.error("Recording start failed: \(error.localizedDescription)")
        }
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

    private func stopRecordingFlow() {
        hideRecordingOverlay()
        lastTranscription = nil
        stateStore.startProcessing()
        applyPipelineFeedback(.processing)

        Task { [weak self] in
            await self?.finalizeRecordingFlow()
        }
    }

    private func startRecordingPreparation() {
        recordingPreparation?.task.cancel()

        let configuration = sttConfigurationStore.makeConfiguration()
        guard configuration.isModelInstalled else {
            recordingPreparation = nil
            return
        }

        let task = Task(priority: .utility) {
            do {
                let sttService = STTService(configuration: configuration)
                try await sttService.beginRecordingPreparation()
                return true
            } catch is CancellationError {
                AppLogger.stt.info("Recording preparation cancelled: \(configuration.selectedModel.title, privacy: .public)")
                return false
            } catch {
                AppLogger.stt.error("Recording preparation failed: \(error.localizedDescription)")
                return false
            }
        }

        recordingPreparation = RecordingPreparation(
            configuration: configuration,
            task: task
        )
    }

    private func finishRecordingPreparation(_ preparation: RecordingPreparation?) async {
        guard let preparation else { return }
        let didAcquirePreparation = await preparation.task.value
        guard didAcquirePreparation else { return }

        let sttService = STTService(configuration: preparation.configuration)
        await sttService.endRecordingPreparation()
    }

    private func showRecordingOverlay() {
        recordingOverlayWindowService.show()
        recordingOverlayWindowService.updateLevel(recordingLevel)
    }

    private func hideRecordingOverlay() {
        recordingOverlayWindowService.hide()
        recordingLevel = 0
    }

    private func runTranscription(
        audioURL: URL,
        audioDurationSeconds: Double,
        pipelineStart: Date
    ) async {
        defer {
            try? FileManager.default.removeItem(at: audioURL)
        }

        var success = false
        var sttDurationSeconds: Double?
        var injectionResultValue = "skipped"
        var pipelineError: String?

        do {
            let configuration = sttConfigurationStore.makeConfiguration()
            let sttService = STTService(configuration: configuration)
            let sttStart = Date()
            let text = try await sttService.transcribe(audioURL: audioURL)
            sttDurationSeconds = Date().timeIntervalSince(sttStart)
            AppLogger.stt.info("Transcription succeeded")
            let injectionResult = try textInjectionService.inject(
                text: text,
                mode: preferencesStore.injectionMode
            )
            injectionResultValue = injectionResult.persistenceValue
            AppLogger.injection.info("Injection result: \(injectionResult.persistenceValue)")
            applyPipelineFeedback(.success(transcription: text, injectionResult: injectionResult))
            success = true
            stateStore.reset()
        } catch {
            AppLogger.stt.error("Transcription failed: \(error.localizedDescription)")
            pipelineError = error.localizedDescription
            applyPipelineFeedback(.failure(error.localizedDescription))
            stateStore.reset()
        }

        let endToEndSeconds = Date().timeIntervalSince(pipelineStart)
        let processMetrics = processMetricsSampler.stop()
        let run = TranscriptionRunRecord(
            id: UUID().uuidString,
            finishedAtISO8601: ISO8601DateFormatter().string(from: Date()),
            audioFileName: audioURL.lastPathComponent,
            audioDurationSeconds: audioDurationSeconds,
            sttDurationSeconds: sttDurationSeconds,
            endToEndDurationSeconds: endToEndSeconds,
            injectionMode: preferencesStore.injectionMode.rawValue,
            injectionResult: injectionResultValue,
            success: success,
            errorMessage: pipelineError,
            processMetrics: processMetrics
        )
        let report = await performanceReportService.appendRunAndRefresh(
            run,
            minSamples: minimumPerformanceSamples
        )
        performanceBaselineReport = report
        refreshPerformanceSummary()
    }

    private func localizedTranscriptionHint(for feedback: PipelineFeedback) -> String {
        switch feedback {
        case .readiness:
            return sttConfigurationStore.readinessText
        case .processing:
            return L10n.text(L10nKey.appTranscriptionProcessing, language: currentLanguage)
        case .success:
            return L10n.text(L10nKey.appTranscriptionSuccess, language: currentLanguage)
        case let .failure(message):
            return L10n.text(L10nKey.appTranscriptionErrorFormat, language: currentLanguage, message)
        }
    }

    private func localizedInjectionStatus(for feedback: PipelineFeedback) -> String {
        switch feedback {
        case .readiness, .processing:
            return L10n.text(L10nKey.appInjectionIdle, language: currentLanguage)
        case let .success(_, injectionResult):
            switch injectionResult {
            case .clipboardOnly:
                return L10n.text(L10nKey.appInjectionCopied, language: currentLanguage)
            case .pasteShortcutSent:
                return L10n.text(L10nKey.appInjectionPasted, language: currentLanguage)
            case .fallbackToClipboard:
                return L10n.text(L10nKey.appInjectionFallbackCopied, language: currentLanguage)
            }
        case .failure:
            return L10n.text(L10nKey.appInjectionSkipped, language: currentLanguage)
        }
    }

    private func applyPipelineFeedback(_ feedback: PipelineFeedback) {
        pipelineFeedback = feedback

        switch feedback {
        case .success(let transcription, _):
            lastTranscription = transcription
        case .processing, .readiness, .failure:
            if case .failure = feedback {
                lastTranscription = nil
            }
        }

        transcriptionHint = localizedTranscriptionHint(for: feedback)
        injectionStatus = localizedInjectionStatus(for: feedback)
    }

    private func finalizeRecordingFlow() async {
        let preparation = recordingPreparation
        recordingPreparation = nil

        do {
            let outputURL = try await audioService.stopRecording()
            lastRecordingFile = outputURL.lastPathComponent
            AppLogger.audio.info("Recording stopped; output: \(outputURL.lastPathComponent)")

            let summary = try wavValidationService.validate(at: outputURL)
            lastAudioValidation = summary.brief
            AppLogger.audio.info("WAV validated: \(summary.brief)")

            processMetricsSampler.start()
            let pipelineStart = Date()
            await runTranscription(
                audioURL: outputURL,
                audioDurationSeconds: summary.durationSeconds,
                pipelineStart: pipelineStart
            )
        } catch {
            stateStore.reset()
            applyPipelineFeedback(.failure(error.localizedDescription))
            AppLogger.audio.error("Recording pipeline failed: \(error.localizedDescription)")
        }

        await finishRecordingPreparation(preparation)
    }

    private func loadPersistedPerformanceReport() async {
        let report = await performanceReportService.loadOrGenerateBaselineReport(minSamples: minimumPerformanceSamples)
        performanceBaselineReport = report
        refreshPerformanceSummary()
    }

    private func refreshPerformanceSummary() {
        guard let report = performanceBaselineReport else {
            performanceSummary = L10n.text(L10nKey.appPerformanceNoSamples, language: currentLanguage)
            return
        }

        let readiness = report.readiness == "ready"
            ? L10n.text(L10nKey.appPerformanceReadinessReady, language: currentLanguage)
            : L10n.text(L10nKey.appPerformanceReadinessCollecting, language: currentLanguage)

        if let p50 = report.p50EndToEndSeconds {
            let p95Text = report.p95EndToEndSeconds.map { String(format: "%.2fs", $0) }
                ?? L10n.text(L10nKey.appMetricsNA, language: currentLanguage)
            performanceSummary = L10n.text(
                L10nKey.appPerformanceSummaryWithP50Format,
                language: currentLanguage,
                report.sampleCount,
                report.successRate * 100,
                p50,
                p95Text,
                readiness
            )
        } else {
            performanceSummary = L10n.text(
                L10nKey.appPerformanceSummaryBasicFormat,
                language: currentLanguage,
                report.sampleCount,
                report.successRate * 100,
                readiness
            )
        }
    }
}
