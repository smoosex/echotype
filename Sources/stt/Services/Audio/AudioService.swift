@preconcurrency import AVFoundation
import Combine
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
    private let levelLock = NSLock()
    private let recordingLevelSubject = CurrentValueSubject<Double, Never>(0)
    private let levelFloor: Float = 0.000_32
    private let minimumDecibels: Float = -50
    private let attackSmoothing: Float = 0.42
    private let releaseSmoothing: Float = 0.12
    private let levelEmissionInterval: TimeInterval = 1.0 / 30.0

    private var capturedBuffers: [AVAudioPCMBuffer] = []
    private var inputFormat: AVAudioFormat?
    private var smoothedLevel: Float = 0
    private var lastLevelEmissionUptime: TimeInterval = 0
    private(set) var isRecording = false
    
    var recordingLevelPublisher: AnyPublisher<Double, Never> {
        recordingLevelSubject.eraseToAnyPublisher()
    }

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
        resetLevelMeter()

        inputNode.installTap(onBus: 0, bufferSize: 2048, format: sourceFormat) { [weak self] buffer, _ in
            guard let self else { return }
            guard let copy = buffer.deepCopy() else { return }
            self.bufferLock.lock()
            self.capturedBuffers.append(copy)
            self.bufferLock.unlock()
            self.processMeterLevel(from: buffer)
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
        } catch {
            inputNode.removeTap(onBus: 0)
            inputFormat = nil
            bufferLock.lock()
            capturedBuffers.removeAll(keepingCapacity: false)
            bufferLock.unlock()
            resetLevelMeter()
            throw error
        }
    }

    func stopRecording() throws -> URL {
        guard isRecording else {
            throw AudioServiceError.notRecording
        }

        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        isRecording = false
        resetLevelMeter()

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

    private func processMeterLevel(from buffer: AVAudioPCMBuffer) {
        let now = ProcessInfo.processInfo.systemUptime
        let measuredLevel = normalizedLevel(from: buffer)
        var emittedLevel: Double?

        levelLock.lock()
        let smoothing = measuredLevel > smoothedLevel ? attackSmoothing : releaseSmoothing
        smoothedLevel += (measuredLevel - smoothedLevel) * smoothing
        if now - lastLevelEmissionUptime >= levelEmissionInterval {
            lastLevelEmissionUptime = now
            emittedLevel = Double(smoothedLevel)
        }
        levelLock.unlock()

        guard let emittedLevel else { return }
        publishRecordingLevel(emittedLevel)
    }

    private func resetLevelMeter() {
        levelLock.lock()
        smoothedLevel = 0
        lastLevelEmissionUptime = 0
        levelLock.unlock()
        publishRecordingLevel(0)
    }

    private func publishRecordingLevel(_ level: Double) {
        let clampedLevel = min(max(level, 0), 1)
        DispatchQueue.main.async { [recordingLevelSubject] in
            recordingLevelSubject.send(clampedLevel)
        }
    }

    private func normalizedLevel(from buffer: AVAudioPCMBuffer) -> Float {
        guard buffer.frameLength > 0 else {
            return 0
        }

        let rms: Float
        switch buffer.format.commonFormat {
        case .pcmFormatFloat32:
            rms = rootMeanSquare(
                channelData: buffer.floatChannelData,
                channelCount: Int(buffer.format.channelCount),
                frameLength: Int(buffer.frameLength)
            )
        case .pcmFormatInt16:
            rms = rootMeanSquare(
                channelData: buffer.int16ChannelData,
                channelCount: Int(buffer.format.channelCount),
                frameLength: Int(buffer.frameLength),
                scale: Float(Int16.max)
            )
        case .pcmFormatInt32:
            rms = rootMeanSquare(
                channelData: buffer.int32ChannelData,
                channelCount: Int(buffer.format.channelCount),
                frameLength: Int(buffer.frameLength),
                scale: Float(Int32.max)
            )
        default:
            return 0
        }

        guard rms > 0 else {
            return 0
        }

        let decibels = max(minimumDecibels, 20 * log10(max(rms, levelFloor)))
        return (decibels - minimumDecibels) / abs(minimumDecibels)
    }

    private func rootMeanSquare(
        channelData: UnsafePointer<UnsafeMutablePointer<Float>>?,
        channelCount: Int,
        frameLength: Int
    ) -> Float {
        guard let channelData, channelCount > 0, frameLength > 0 else {
            return 0
        }

        var total: Float = 0
        for channel in 0..<channelCount {
            let samples = channelData[channel]
            var sum: Float = 0
            for frame in 0..<frameLength {
                let sample = samples[frame]
                sum += sample * sample
            }
            total += sqrt(sum / Float(frameLength))
        }
        return total / Float(channelCount)
    }

    private func rootMeanSquare(
        channelData: UnsafePointer<UnsafeMutablePointer<Int16>>?,
        channelCount: Int,
        frameLength: Int,
        scale: Float
    ) -> Float {
        guard let channelData, channelCount > 0, frameLength > 0 else {
            return 0
        }

        var total: Float = 0
        for channel in 0..<channelCount {
            let samples = channelData[channel]
            var sum: Float = 0
            for frame in 0..<frameLength {
                let sample = Float(samples[frame]) / scale
                sum += sample * sample
            }
            total += sqrt(sum / Float(frameLength))
        }
        return total / Float(channelCount)
    }

    private func rootMeanSquare(
        channelData: UnsafePointer<UnsafeMutablePointer<Int32>>?,
        channelCount: Int,
        frameLength: Int,
        scale: Float
    ) -> Float {
        guard let channelData, channelCount > 0, frameLength > 0 else {
            return 0
        }

        var total: Float = 0
        for channel in 0..<channelCount {
            let samples = channelData[channel]
            var sum: Float = 0
            for frame in 0..<frameLength {
                let sample = Float(samples[frame]) / scale
                sum += sample * sample
            }
            total += sqrt(sum / Float(frameLength))
        }
        return total / Float(channelCount)
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
