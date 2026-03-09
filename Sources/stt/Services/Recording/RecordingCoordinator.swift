import Combine
import Foundation

@MainActor
final class RecordingCoordinator {
    private final class RecordingSession {
        let id = UUID()
        let configuration: STTConfiguration
        let sttService: STTService?
        var preparationTask: Task<Bool, Never>?
        var preparationReady = false
        var isPreparing = false

        init(configuration: STTConfiguration, sttService: STTService?) {
            self.configuration = configuration
            self.sttService = sttService
        }
    }

    private let stateStore: AppStateStore
    private let audioService: AudioService
    private let mediaPlaybackControlService: MediaPlaybackControlService
    private let wavValidationService: WAVValidationService
    private let textInjectionService: TextInjectionService
    private let recordingOverlayWindowService: RecordingOverlayWindowService
    private let overlayResultHoldDuration: Duration

    private var activeSession: RecordingSession?
    private var overlaySessionID = UUID()
    private var cancellables = Set<AnyCancellable>()

    init(
        stateStore: AppStateStore,
        audioService: AudioService = AudioService(),
        mediaPlaybackControlService: MediaPlaybackControlService = MediaPlaybackControlService(),
        wavValidationService: WAVValidationService = WAVValidationService(),
        textInjectionService: TextInjectionService = TextInjectionService(),
        recordingOverlayWindowService: RecordingOverlayWindowService = RecordingOverlayWindowService(),
        overlayResultHoldDuration: Duration = .milliseconds(720)
    ) {
        self.stateStore = stateStore
        self.audioService = audioService
        self.mediaPlaybackControlService = mediaPlaybackControlService
        self.wavValidationService = wavValidationService
        self.textInjectionService = textInjectionService
        self.recordingOverlayWindowService = recordingOverlayWindowService
        self.overlayResultHoldDuration = overlayResultHoldDuration
        bindRecordingLevelChanges()
    }

    func startRecording(configuration: STTConfiguration) {
        do {
            mediaPlaybackControlService.pauseActivePlayback()
            try audioService.startRecording()
            let sttService = shouldPrepareRecording(for: configuration)
                ? STTService(configuration: configuration)
                : nil
            let session = RecordingSession(configuration: configuration, sttService: sttService)
            activeSession?.preparationTask?.cancel()
            activeSession = session
            stateStore.startRecording()
            showRecordingOverlay()
            startRecordingPreparation(for: session)
            AppLogger.audio.info("Recording started")
        } catch {
            hideRecordingOverlay()
            stateStore.reset()
            activeSession = nil
            AppLogger.audio.error("Recording start failed: \(error.localizedDescription)")
        }
    }

    private func shouldPrepareRecording(for configuration: STTConfiguration) -> Bool {
        switch configuration.selectedModel.family {
        case .whisperKit:
            return configuration.whisperModelFolder != nil
        case .qwen3ASR:
            return configuration.isModelInstalled
        }
    }

    func stopRecording(injectionMode: TextInjectionMode) {
        guard case .recording = stateStore.state else { return }
        stateStore.startProcessing()
        recordingOverlayWindowService.setPreparationAccessoryVisible(false)
        recordingOverlayWindowService.updateMode(activeSession?.isPreparing == true ? .loading : .transcribing)

        Task { [weak self] in
            await self?.finalizeRecordingFlow(injectionMode: injectionMode)
        }
    }

    private func bindRecordingLevelChanges() {
        audioService.recordingLevelPublisher
            .removeDuplicates(by: { abs($0 - $1) < 0.01 })
            .sink { [weak self] level in
                self?.recordingOverlayWindowService.updateLevel(level)
            }
            .store(in: &cancellables)
    }

    private func startRecordingPreparation(for session: RecordingSession) {
        recordingOverlayWindowService.setPreparationAccessoryVisible(false)

        guard let sttService = session.sttService else {
            session.isPreparing = false
            session.preparationReady = false
            return
        }

        session.isPreparing = true
        session.preparationReady = false
        recordingOverlayWindowService.setPreparationAccessoryVisible(true)
        let sessionID = session.id
        let configuration = session.configuration
        let task = Task(priority: .utility) {
            do {
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

        session.preparationTask = task

        Task { [weak self] in
            let didAcquirePreparation = await task.value
            await MainActor.run {
                self?.handleRecordingPreparationCompletion(
                    id: sessionID,
                    didAcquirePreparation: didAcquirePreparation
                )
            }
        }
    }

    private func finishRecordingPreparation(
        for session: RecordingSession,
        didAcquirePreparation: Bool
    ) async {
        guard didAcquirePreparation, let sttService = session.sttService else { return }
        await sttService.endRecordingPreparation()
    }

    private func showRecordingOverlay() {
        overlaySessionID = UUID()
        recordingOverlayWindowService.show(mode: .recording)
        recordingOverlayWindowService.updateLevel(0)
    }

    private func hideRecordingOverlay() {
        overlaySessionID = UUID()
        recordingOverlayWindowService.hide()
    }

    private func finalizeRecordingFlow(injectionMode: TextInjectionMode) async {
        guard let session = activeSession else {
            stateStore.reset()
            hideRecordingOverlay()
            return
        }

        var didAcquirePreparation = session.preparationReady

        do {
            let outputURL = try await audioService.stopRecording()
            AppLogger.audio.info("Recording stopped; output: \(outputURL.lastPathComponent)")

            let summary = try wavValidationService.validate(at: outputURL)
            AppLogger.audio.info("WAV validated: \(summary.brief)")

            if session.isPreparing {
                didAcquirePreparation = await awaitRecordingPreparation(for: session)
            }

            recordingOverlayWindowService.updateMode(.transcribing)
            let transcribeService = session.sttService ?? STTService(configuration: session.configuration)

            do {
                let text = try await transcribeService.transcribe(audioURL: outputURL)
                AppLogger.stt.info("Transcription succeeded")
                let injectionResult = try textInjectionService.inject(text: text, mode: injectionMode)
                AppLogger.injection.info("Injection result: \(injectionResult.persistenceValue)")
                stateStore.reset()
                recordingOverlayWindowService.updateMode(.success)
            } catch {
                AppLogger.stt.error("Transcription failed: \(error.localizedDescription)")
                stateStore.reset()
                recordingOverlayWindowService.updateMode(.failure)
            }

            try? FileManager.default.removeItem(at: outputURL)
        } catch {
            stateStore.reset()
            AppLogger.audio.error("Recording pipeline failed: \(error.localizedDescription)")
            recordingOverlayWindowService.updateMode(.failure)
        }

        let finishedSessionID = session.id
        await finishRecordingPreparation(for: session, didAcquirePreparation: didAcquirePreparation)
        completeRecordingPreparationCycle(id: finishedSessionID)
        await hideRecordingOverlayAfterResult(for: overlaySessionID)
    }

    private func handleRecordingPreparationCompletion(
        id: UUID,
        didAcquirePreparation: Bool
    ) {
        guard let session = activeSession, session.id == id else { return }
        session.isPreparing = false
        session.preparationReady = didAcquirePreparation
        recordingOverlayWindowService.setPreparationAccessoryVisible(false)
    }

    private func awaitRecordingPreparation(for session: RecordingSession) async -> Bool {
        guard let preparationTask = session.preparationTask else { return false }
        let didAcquirePreparation = await preparationTask.value
        handleRecordingPreparationCompletion(id: session.id, didAcquirePreparation: didAcquirePreparation)
        return didAcquirePreparation
    }

    private func completeRecordingPreparationCycle(id: UUID) {
        guard let session = activeSession, session.id == id else { return }
        session.preparationTask = nil
        session.isPreparing = false
        session.preparationReady = false
        recordingOverlayWindowService.setPreparationAccessoryVisible(false)
        activeSession = nil
    }

    private func hideRecordingOverlayAfterResult(for sessionID: UUID) async {
        try? await Task.sleep(for: overlayResultHoldDuration)
        guard overlaySessionID == sessionID else { return }
        hideRecordingOverlay()
    }
}
