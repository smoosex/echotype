@preconcurrency import AVFoundation
import Foundation

enum AudioServiceError: LocalizedError {
    case microphonePermissionDenied
    case alreadyRecording
    case notRecording
    case tapCopyFailed
    case noAudioData
    case converterInitializationFailed
    case conversionFailed(String)

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone permission is not granted."
        case .alreadyRecording:
            return "Recording is already in progress."
        case .notRecording:
            return "Recording is not in progress."
        case .tapCopyFailed:
            return "Failed to capture audio buffer."
        case .noAudioData:
            return "No audio data captured."
        case .converterInitializationFailed:
            return "Failed to initialize audio converter."
        case .conversionFailed(let reason):
            return "Audio conversion failed: \(reason)"
        }
    }
}

final class AudioService: @unchecked Sendable {
    private let audioEngine = AVAudioEngine()
    private let bufferLock = NSLock()

    private var capturedBuffers: [AVAudioPCMBuffer] = []
    private var inputFormat: AVAudioFormat?
    private(set) var isRecording = false

    func startRecording() throws {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw AudioServiceError.microphonePermissionDenied
        }

        guard !isRecording else {
            throw AudioServiceError.alreadyRecording
        }

        let inputNode = audioEngine.inputNode
        let sourceFormat = inputNode.outputFormat(forBus: 0)
        inputFormat = sourceFormat

        capturedBuffers.removeAll(keepingCapacity: true)

        inputNode.installTap(onBus: 0, bufferSize: 2048, format: sourceFormat) { [weak self] buffer, _ in
            guard let self else { return }
            guard let copy = buffer.deepCopy() else { return }
            self.bufferLock.lock()
            self.capturedBuffers.append(copy)
            self.bufferLock.unlock()
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true
    }

    func stopRecording() throws -> URL {
        guard isRecording else {
            throw AudioServiceError.notRecording
        }

        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        isRecording = false

        var buffers: [AVAudioPCMBuffer] = []
        bufferLock.lock()
        buffers = capturedBuffers
        capturedBuffers.removeAll(keepingCapacity: false)
        bufferLock.unlock()

        guard !buffers.isEmpty else {
            throw AudioServiceError.noAudioData
        }

        guard let sourceFormat = inputFormat else {
            throw AudioServiceError.converterInitializationFailed
        }

        let outputURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("echotype-recording-\(UUID().uuidString).wav")

        try writeWAV(from: buffers, sourceFormat: sourceFormat, outputURL: outputURL)
        return outputURL
    }

    private func writeWAV(from buffers: [AVAudioPCMBuffer], sourceFormat: AVAudioFormat, outputURL: URL) throws {
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: true
        ) else {
            throw AudioServiceError.converterInitializationFailed
        }

        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw AudioServiceError.converterInitializationFailed
        }

        let outputFile = try AVAudioFile(
            forWriting: outputURL,
            settings: targetFormat.settings,
            commonFormat: .pcmFormatInt16,
            interleaved: true
        )

        for buffer in buffers {
            try convertAndWrite(
                inputBuffer: buffer,
                converter: converter,
                outputFile: outputFile,
                outputFormat: targetFormat
            )
        }
    }

    private func convertAndWrite(
        inputBuffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        outputFile: AVAudioFile,
        outputFormat: AVAudioFormat
    ) throws {
        converter.reset()
        let inputProvider = InputProvider(buffer: inputBuffer)

        let ratio = outputFormat.sampleRate / inputBuffer.format.sampleRate
        let estimatedFrames = max(AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio) + 32, 512)

        while true {
            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: estimatedFrames) else {
                throw AudioServiceError.conversionFailed("Failed to allocate output buffer.")
            }

            var conversionError: NSError?
            let status = converter.convert(to: outputBuffer, error: &conversionError, withInputFrom: inputProvider.nextBuffer)

            if let conversionError {
                throw conversionError
            }

            if outputBuffer.frameLength > 0 {
                try outputFile.write(from: outputBuffer)
            }

            switch status {
            case .haveData:
                continue
            case .inputRanDry, .endOfStream:
                return
            case .error:
                throw AudioServiceError.conversionFailed("Converter returned error status.")
            @unknown default:
                return
            }
        }
    }
}

private final class InputProvider: @unchecked Sendable {
    private var consumed = false
    private let buffer: AVAudioPCMBuffer

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func nextBuffer(
        _: AVAudioPacketCount,
        outStatus: UnsafeMutablePointer<AVAudioConverterInputStatus>
    ) -> AVAudioBuffer? {
        if consumed {
            outStatus.pointee = .endOfStream
            return nil
        }

        consumed = true
        outStatus.pointee = .haveData
        return buffer
    }
}

private extension AVAudioPCMBuffer {
    func deepCopy() -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else {
            return nil
        }

        copy.frameLength = frameLength
        let sourceListPointer = UnsafeMutablePointer<AudioBufferList>(mutating: audioBufferList)
        let sourceBuffers = UnsafeMutableAudioBufferListPointer(sourceListPointer)
        let destinationBuffers = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)

        guard sourceBuffers.count == destinationBuffers.count else {
            return nil
        }

        for index in 0..<sourceBuffers.count {
            guard
                let sourceData = sourceBuffers[index].mData,
                let destinationData = destinationBuffers[index].mData
            else {
                return nil
            }

            let byteCount = Int(sourceBuffers[index].mDataByteSize)
            memcpy(destinationData, sourceData, byteCount)
            destinationBuffers[index].mDataByteSize = sourceBuffers[index].mDataByteSize
        }

        return copy
    }
}
