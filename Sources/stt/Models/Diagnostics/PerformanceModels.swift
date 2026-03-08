import Foundation

struct ProcessMetricsResult: Codable, Sendable {
    let wallTimeSeconds: Double
    let cpuPercentEstimate: Double
    let peakResidentMemoryMB: Double
}

struct TranscriptionRunRecord: Codable, Sendable {
    let id: String
    let finishedAtISO8601: String
    let audioFileName: String
    let audioDurationSeconds: Double
    let sttDurationSeconds: Double?
    let endToEndDurationSeconds: Double
    let injectionMode: String
    let injectionResult: String
    let success: Bool
    let errorMessage: String?
    let processMetrics: ProcessMetricsResult?
}

struct PerformanceBaselineReport: Codable, Sendable {
    let generatedAtISO8601: String
    let sampleCount: Int
    let successfulRuns: Int
    let successRate: Double
    let p50EndToEndSeconds: Double?
    let p95EndToEndSeconds: Double?
    let averageCpuPercent: Double?
    let averagePeakMemoryMB: Double?
    let readiness: String
}
