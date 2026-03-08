import Foundation

enum PipelineFeedback: Equatable, Sendable {
    case readiness
    case processing
    case success(transcription: String, injectionResult: TextInjectionResult)
    case failure(String)
}
