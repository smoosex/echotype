import Foundation

struct StabilitySelfTestResult: Sendable {
    let iterations: Int
    let failures: Int
    let durationSeconds: Double

    var summary: String {
        String(
            format: "self-test %d runs, failures=%d, time=%.2fs",
            iterations,
            failures,
            durationSeconds
        )
    }
}

final class StabilitySelfTestService: @unchecked Sendable {
    func run(
        iterations: Int,
        stateStore: AppStateStore,
        textInjectionService: TextInjectionService
    ) async -> StabilitySelfTestResult {
        let start = Date()
        var failures = 0

        for index in 0..<iterations {
            await MainActor.run {
                stateStore.reset()
                stateStore.startRecording()
                stateStore.startProcessing()
            }

            do {
                _ = try textInjectionService.inject(text: "self-test-\(index)", mode: .clipboardOnly)
            } catch {
                failures += 1
            }

            await MainActor.run {
                stateStore.reset()
            }

            if index.isMultiple(of: 20) {
                await Task.yield()
            }
        }

        let duration = Date().timeIntervalSince(start)
        return StabilitySelfTestResult(
            iterations: iterations,
            failures: failures,
            durationSeconds: duration
        )
    }
}
