import Foundation
import os

@Observable
final class WorkoutManager {
    var isRecording = false
    var currentHeartRate: Double = 0
    var lastSampleDate: Date?
    var currentSession: RecordingSession?
    var locationSampleCount: Int = 0
    var accelerometerSampleCount: Int = 0
    var usingSimulatedData = false

    private let provider: any HeartRateProvider
    private let locationProvider: any LocationProvider
    private let motionProvider: any MotionProvider
    private let logger = Logger(
        subsystem: "net.lnor.beschluenige.watchkitapp",
        category: "WorkoutManager"
    )

    init(
        provider: any HeartRateProvider,
        locationProvider: any LocationProvider,
        motionProvider: any MotionProvider
    ) {
        self.provider = provider
        self.locationProvider = locationProvider
        self.motionProvider = motionProvider
    }

    func requestAuthorization() async throws {
        try await provider.requestAuthorization()
        try await locationProvider.requestAuthorization()
    }

    func startRecording() async throws {
        currentSession = RecordingSession(startDate: Date())
        currentHeartRate = 0
        lastSampleDate = nil
        locationSampleCount = 0
        accelerometerSampleCount = 0
        usingSimulatedData = false

        configureFallbackCallbacks()

        try await provider.startMonitoring { [weak self] samples in
            Task { @MainActor [weak self] in
                self?.processSamples(samples)
            }
        }

        try await locationProvider.startMonitoring { [weak self] samples in
            Task { @MainActor [weak self] in
                self?.processLocationSamples(samples)
            }
        }

        try motionProvider.startMonitoring { [weak self] samples in
            Task { @MainActor [weak self] in
                self?.processAccelerometerSamples(samples)
            }
        }

        isRecording = true
    }

    func stopRecording() {
        provider.stopMonitoring()
        locationProvider.stopMonitoring()
        motionProvider.stopMonitoring()
        currentSession?.endDate = Date()
        isRecording = false
    }

    private func configureFallbackCallbacks() {
        let markSimulated: @Sendable () -> Void = { [weak self] in
            Task { @MainActor [weak self] in
                self?.usingSimulatedData = true
            }
        }
        if let mock = provider as? MockHeartRateProvider {
            mock.onFallbackActivated = markSimulated
        }
        if let mock = locationProvider as? MockLocationProvider {
            mock.onFallbackActivated = markSimulated
        }
        if let mock = motionProvider as? MockMotionProvider {
            mock.onFallbackActivated = markSimulated
        }
    }

    private func processSamples(_ samples: [HeartRateSample]) {
        currentSession?.samples.append(contentsOf: samples)
        if let last = samples.last {
            currentHeartRate = last.beatsPerMinute
            lastSampleDate = last.timestamp
        }
    }

    private func processLocationSamples(_ samples: [LocationSample]) {
        currentSession?.locationSamples.append(contentsOf: samples)
        locationSampleCount = currentSession?.locationSamples.count ?? 0
    }

    private func processAccelerometerSamples(_ samples: [AccelerometerSample]) {
        currentSession?.accelerometerSamples.append(contentsOf: samples)
        accelerometerSampleCount = currentSession?.accelerometerSamples.count ?? 0
    }
}
