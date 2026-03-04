import Foundation
@preconcurrency import Darwin

private struct ProcessResourceSnapshot {
    let timestamp: TimeInterval
    let cpuSeconds: Double
    let residentBytes: UInt64
}

final class ProcessMetricsSampler {
    private let lock = NSLock()
    private let samplingQueue = DispatchQueue(label: "ProcessMetricsSampler.queue")

    private var startSnapshot: ProcessResourceSnapshot?
    private var peakResidentBytes: UInt64 = 0
    private var timer: DispatchSourceTimer?

    func start() {
        lock.lock()
        defer { lock.unlock() }

        guard let start = Self.captureSnapshot() else { return }
        startSnapshot = start
        peakResidentBytes = start.residentBytes

        let timer = DispatchSource.makeTimerSource(queue: samplingQueue)
        timer.schedule(deadline: .now() + 0.2, repeating: 0.2)
        timer.setEventHandler { [weak self] in
            self?.samplePeakMemory()
        }
        timer.resume()
        self.timer = timer
    }

    func stop() -> ProcessMetricsResult? {
        lock.lock()
        let timer = self.timer
        self.timer = nil
        let start = self.startSnapshot
        self.startSnapshot = nil
        lock.unlock()

        timer?.cancel()

        guard
            let start,
            let end = Self.captureSnapshot()
        else {
            return nil
        }

        let wall = max(end.timestamp - start.timestamp, 0.001)
        let cpu = max(end.cpuSeconds - start.cpuSeconds, 0)
        let cpuPercent = (cpu / wall) * 100

        lock.lock()
        let peakResident = max(peakResidentBytes, end.residentBytes)
        peakResidentBytes = 0
        lock.unlock()

        return ProcessMetricsResult(
            wallTimeSeconds: wall,
            cpuPercentEstimate: cpuPercent,
            peakResidentMemoryMB: Double(peakResident) / (1024 * 1024)
        )
    }

    private func samplePeakMemory() {
        guard let snapshot = Self.captureSnapshot() else { return }

        lock.lock()
        peakResidentBytes = max(peakResidentBytes, snapshot.residentBytes)
        lock.unlock()
    }

    private static func captureSnapshot() -> ProcessResourceSnapshot? {
        guard
            let vm = captureTaskVMInfo(),
            let times = captureTaskTimes()
        else {
            return nil
        }

        let cpuSeconds = timeInterval(from: times.user_time) + timeInterval(from: times.system_time)
        return ProcessResourceSnapshot(
            timestamp: CFAbsoluteTimeGetCurrent(),
            cpuSeconds: cpuSeconds,
            residentBytes: vm.phys_footprint
        )
    }

    private static func captureTaskVMInfo() -> task_vm_info_data_t? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }

        return result == KERN_SUCCESS ? info : nil
    }

    private static func captureTaskTimes() -> task_thread_times_info_data_t? {
        var info = task_thread_times_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_thread_times_info_data_t>.size / MemoryLayout<natural_t>.size)

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_THREAD_TIMES_INFO), $0, &count)
            }
        }

        return result == KERN_SUCCESS ? info : nil
    }

    private static func timeInterval(from time: time_value_t) -> Double {
        Double(time.seconds) + Double(time.microseconds) / 1_000_000.0
    }
}
