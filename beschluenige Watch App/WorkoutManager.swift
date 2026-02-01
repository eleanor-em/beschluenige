import Foundation
import os

@Observable
final class WorkoutManager {
    var isRecording = false
    var currentHeartRate: Double = 0
    var lastSampleDate: Date?
    var currentSession: RecordingSession?

    private let provider: any HeartRateProvider
    private let logger = Logger(
        subsystem: "net.lnor.beschluenige.watchkitapp",
        category: "WorkoutManager"
    )

    init(provider: any HeartRateProvider) {
        self.provider = provider
    }

    func requestAuthorization() async throws {
        try await provider.requestAuthorization()
    }

    func startRecording() async throws {
        currentSession = RecordingSession(startDate: Date())
        currentHeartRate = 0
        lastSampleDate = nil

        try await provider.startMonitoring { [weak self] samples in
            Task { @MainActor [weak self] in
                self?.processSamples(samples)
            }
        }

        isRecording = true
    }

    func stopRecording() {
        provider.stopMonitoring()
        currentSession?.endDate = Date()
        isRecording = false
    }

    private func processSamples(_ samples: [HeartRateSample]) {
        currentSession?.samples.append(contentsOf: samples)
        if let last = samples.last {
            currentHeartRate = last.beatsPerMinute
            lastSampleDate = last.timestamp
        }
    }
}
