import AVFoundation
import Foundation

struct WAVValidationSummary: Equatable {
    let sampleRate: Double
    let channels: UInt32
    let durationSeconds: Double

    var brief: String {
        String(
            format: "%.0fHz / %dch / %.2fs",
            sampleRate,
            channels,
            durationSeconds
        )
    }

    var isWhisperCompatible: Bool {
        sampleRate == 16_000 && channels == 1
    }
}

enum WAVValidationError: LocalizedError {
    case formatMismatch(expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case .formatMismatch(let expected, let actual):
            return "WAV format mismatch. expected=\(expected), actual=\(actual)"
        }
    }
}

final class WAVValidationService {
    func validate(at url: URL) throws -> WAVValidationSummary {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat

        let duration = Double(file.length) / format.sampleRate
        let summary = WAVValidationSummary(
            sampleRate: format.sampleRate,
            channels: format.channelCount,
            durationSeconds: duration
        )

        guard summary.isWhisperCompatible else {
            throw WAVValidationError.formatMismatch(
                expected: "16000Hz/1ch",
                actual: "\(Int(summary.sampleRate))Hz/\(summary.channels)ch"
            )
        }

        return summary
    }
}
