import Foundation

final class PerformanceReportService {
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private let decoder = JSONDecoder()

    func appendRun(_ run: TranscriptionRunRecord) {
        do {
            let lineData = try encoder.encode(run)
            let fileURL = try runsFileURL()
            try ensureDirectoryExists(for: fileURL)

            if !FileManager.default.fileExists(atPath: fileURL.path) {
                FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            }

            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }

            try handle.seekToEnd()
            handle.write(lineData)
            handle.write("\n".data(using: .utf8)!)
        } catch {
            AppLogger.app.error("Failed to append run metrics: \(error.localizedDescription)")
        }
    }

    func generateAndPersistBaselineReport(minSamples: Int = 20) -> PerformanceBaselineReport {
        let runs = loadRuns(limit: nil)
        let report = makeReport(from: runs, minSamples: minSamples)

        do {
            let data = try encoder.encode(report)
            let fileURL = try baselineReportFileURL()
            try ensureDirectoryExists(for: fileURL)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            AppLogger.app.error("Failed to persist baseline report: \(error.localizedDescription)")
        }

        return report
    }

    func metricsDirectoryPath() -> String {
        (try? metricsDirectoryURL().path) ?? "N/A"
    }

    private func makeReport(from runs: [TranscriptionRunRecord], minSamples: Int) -> PerformanceBaselineReport {
        let successfulRuns = runs.filter { $0.success }
        let successfulDurations = successfulRuns.map(\.endToEndDurationSeconds).sorted()
        let cpuValues = successfulRuns.compactMap { $0.processMetrics?.cpuPercentEstimate }
        let memoryValues = successfulRuns.compactMap { $0.processMetrics?.peakResidentMemoryMB }

        let successRate = runs.isEmpty ? 0.0 : Double(successfulRuns.count) / Double(runs.count)

        return PerformanceBaselineReport(
            generatedAtISO8601: ISO8601DateFormatter().string(from: Date()),
            sampleCount: runs.count,
            successfulRuns: successfulRuns.count,
            successRate: successRate,
            p50EndToEndSeconds: percentile(0.50, fromSorted: successfulDurations),
            p95EndToEndSeconds: percentile(0.95, fromSorted: successfulDurations),
            averageCpuPercent: cpuValues.isEmpty ? nil : cpuValues.reduce(0, +) / Double(cpuValues.count),
            averagePeakMemoryMB: memoryValues.isEmpty ? nil : memoryValues.reduce(0, +) / Double(memoryValues.count),
            readiness: runs.count >= minSamples ? "ready" : "collecting"
        )
    }

    private func loadRuns(limit: Int?) -> [TranscriptionRunRecord] {
        guard let fileURL = try? runsFileURL(), FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        guard let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8) else {
            return []
        }

        let lines = text.split(separator: "\n").map(String.init)
        let relevantLines: [String]

        if let limit {
            relevantLines = Array(lines.suffix(limit))
        } else {
            relevantLines = lines
        }

        return relevantLines.compactMap { line in
            guard let lineData = line.data(using: .utf8) else { return nil }
            return try? decoder.decode(TranscriptionRunRecord.self, from: lineData)
        }
    }

    private func runsFileURL() throws -> URL {
        try metricsDirectoryURL().appendingPathComponent("transcription_runs.jsonl")
    }

    private func baselineReportFileURL() throws -> URL {
        try metricsDirectoryURL().appendingPathComponent("performance_baseline.json")
    }

    private func metricsDirectoryURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        return base
            .appendingPathComponent("echotype", isDirectory: true)
            .appendingPathComponent("metrics", isDirectory: true)
    }

    private func ensureDirectoryExists(for fileURL: URL) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func percentile(_ p: Double, fromSorted values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let clamped = min(max(p, 0), 1)
        let index = Int(round(clamped * Double(values.count - 1)))
        return values[index]
    }
}
