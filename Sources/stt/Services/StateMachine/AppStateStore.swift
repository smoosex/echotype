import Foundation

@MainActor
final class AppStateStore: ObservableObject {
    @Published private(set) var state: AppState = .idle

    func startRecording() {
        guard case .idle = state else { return }
        state = .recording
    }

    func startProcessing() {
        guard case .recording = state else { return }
        state = .processing
    }

    func fail(_ message: String) {
        state = .error(message)
    }

    func reset() {
        state = .idle
    }
}
