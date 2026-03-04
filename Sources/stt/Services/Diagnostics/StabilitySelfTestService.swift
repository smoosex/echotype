import Foundation

struct StabilitySelfTestResult {
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

@MainActor
final class StabilitySelfTestService {
    func run(
        iterations: Int,
        stateStore: AppStateStore,
        textInjectionService: TextInjectionService
    ) -> StabilitySelfTestResult {
        let start = Date()
        var failures = 0

        for index in 0..<iterations {
            stateStore.reset()
            stateStore.startRecording()
            stateStore.startProcessing()

            do {
                _ = try textInjectionService.inject(text: "self-test-\(index)", mode: .clipboardOnly)
            } catch {
                failures += 1
            }

            stateStore.reset()
        }

        let duration = Date().timeIntervalSince(start)
        return StabilitySelfTestResult(
            iterations: iterations,
            failures: failures,
            durationSeconds: duration
        )
    }
}
