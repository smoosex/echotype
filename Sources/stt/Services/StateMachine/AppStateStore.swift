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

    func reset() {
        state = .idle
    }
}
