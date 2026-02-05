import Foundation
import os

@Observable
final class WorkoutManager {
    var isRecording = false
    var currentHeartRate: Double = 0
    var lastSampleDate: Date?
    var currentSession: RecordingSession?
    var heartRateSampleCount: Int = 0
    var locationSampleCount: Int = 0
    var accelerometerSampleCount: Int = 0
    var deviceMotionSampleCount: Int = 0

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
        heartRateSampleCount = 0
        locationSampleCount = 0
        accelerometerSampleCount = 0
        deviceMotionSampleCount = 0

        try await provider.startMonitoring { [weak self] samples in
            Task { @MainActor [weak self] in
                self?.processHeartRateSamples(samples)
            }
        }

        try await locationProvider.startMonitoring { [weak self] samples in
            Task { @MainActor [weak self] in
                self?.processLocationSamples(samples)
            }
        }

        try motionProvider.startMonitoring(
            accelerometerHandler: { [weak self] samples in
                Task { @MainActor [weak self] in
                    self?.processAccelerometerSamples(samples)
                }
            },
            deviceMotionHandler: { [weak self] samples in
                Task { @MainActor [weak self] in
                    self?.processDeviceMotionSamples(samples)
                }
            }
        )

        isRecording = true
    }

    func stopRecording() {
        provider.stopMonitoring()
        locationProvider.stopMonitoring()
        motionProvider.stopMonitoring()
        currentSession?.endDate = Date()
        isRecording = false
    }

    private func processHeartRateSamples(_ samples: [HeartRateSample]) {
        guard isRecording else {
            logger.error("processSamples(): not currently recording")
            return
        }
        assertExcludeCoverage(currentSession != nil, "isRecording implies currentSession != nil")
        currentSession!.heartRateSamples.append(contentsOf: samples)
        heartRateSampleCount = currentSession!.heartRateSamples.count
        if let last = samples.last {
            currentHeartRate = last.beatsPerMinute
            lastSampleDate = last.timestamp
        }
    }

    private func processLocationSamples(_ samples: [LocationSample]) {
        guard isRecording else {
            logger.error("processLocationSamples(): not currently recording")
            return
        }
        assertExcludeCoverage(currentSession != nil, "isRecording implies currentSession != nil")
        currentSession!.locationSamples.append(contentsOf: samples)
        locationSampleCount = currentSession!.locationSamples.count
    }

    private func processAccelerometerSamples(_ samples: [AccelerometerSample]) {
        guard isRecording else {
            logger.error("processAccelerometerSamples(): not currently recording")
            return
        }
        assertExcludeCoverage(currentSession != nil, "isRecording implies currentSession != nil")
        currentSession!.accelerometerSamples.append(contentsOf: samples)
        accelerometerSampleCount = currentSession!.accelerometerSamples.count
    }

    private func processDeviceMotionSamples(_ samples: [DeviceMotionSample]) {
        guard isRecording else {
            logger.error("processDeviceMotionSamples(): not currently recording")
            return
        }
        assertExcludeCoverage(currentSession != nil, "isRecording implies currentSession != nil")
        currentSession!.deviceMotionSamples.append(contentsOf: samples)
        deviceMotionSampleCount = currentSession!.deviceMotionSamples.count
    }
}
