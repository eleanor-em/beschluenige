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
    var flushInterval: TimeInterval = 600

    private var cumulativeHeartRateCount: Int = 0
    private var cumulativeLocationCount: Int = 0
    private var cumulativeAccelerometerCount: Int = 0
    private var cumulativeDeviceMotionCount: Int = 0
    private var flushTimer: Timer?

    private let provider: any HeartRateProvider
    private let locationProvider: any LocationProvider
    private let motionProvider: any DeviceMotionProvider
    private let logger = Logger(
        subsystem: "net.lnor.beschluenige.watchkitapp",
        category: "WorkoutManager"
    )

    init(
        provider: any HeartRateProvider,
        locationProvider: any LocationProvider,
        motionProvider: any DeviceMotionProvider
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
        cumulativeHeartRateCount = 0
        cumulativeLocationCount = 0
        cumulativeAccelerometerCount = 0
        cumulativeDeviceMotionCount = 0

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

        flushTimer = Timer.scheduledTimer(
            withTimeInterval: flushInterval, repeats: true,
            block: { [weak self] _ in self?.handleFlushTimer() }
        )
    }

    func handleFlushTimer() {
        Task { @MainActor in
            self.flushCurrentChunk()
        }
    }

    func stopRecording() {
        flushTimer?.invalidate()
        flushTimer = nil

        provider.stopMonitoring()
        locationProvider.stopMonitoring()
        motionProvider.stopMonitoring()

        flushCurrentChunk()

        currentSession?.cumulativeSampleCount =
            cumulativeHeartRateCount + cumulativeLocationCount
            + cumulativeAccelerometerCount + cumulativeDeviceMotionCount

        currentSession?.endDate = Date()
        isRecording = false
    }

    func flushCurrentChunk() {
        guard isRecording || currentSession != nil else { return }
        guard currentSession != nil else { return }

        cumulativeHeartRateCount += currentSession!.heartRateSamples.count
        cumulativeLocationCount += currentSession!.locationSamples.count
        cumulativeAccelerometerCount += currentSession!.accelerometerSamples.count
        cumulativeDeviceMotionCount += currentSession!.deviceMotionSamples.count

        do {
            if let url = try currentSession!.flushChunk() {
                logger.info("Flushed chunk to \(url.lastPathComponent)")
            }
        } catch {
            logger.error("Failed to flush chunk: \(error.localizedDescription)")
        }

        heartRateSampleCount = cumulativeHeartRateCount + currentSession!.heartRateSamples.count
        locationSampleCount = cumulativeLocationCount + currentSession!.locationSamples.count
        accelerometerSampleCount =
            cumulativeAccelerometerCount + currentSession!.accelerometerSamples.count
        deviceMotionSampleCount =
            cumulativeDeviceMotionCount + currentSession!.deviceMotionSamples.count
    }

    private func processHeartRateSamples(_ samples: [HeartRateSample]) {
        guard isRecording else {
            logger.error("processSamples(): not currently recording")
            return
        }
        assertExcludeCoverage(currentSession != nil, "isRecording implies currentSession != nil")
        currentSession!.heartRateSamples.append(contentsOf: samples)
        heartRateSampleCount = cumulativeHeartRateCount + currentSession!.heartRateSamples.count
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
        locationSampleCount = cumulativeLocationCount + currentSession!.locationSamples.count
    }

    private func processAccelerometerSamples(_ samples: [AccelerometerSample]) {
        guard isRecording else {
            logger.error("processAccelerometerSamples(): not currently recording")
            return
        }
        assertExcludeCoverage(currentSession != nil, "isRecording implies currentSession != nil")
        currentSession!.accelerometerSamples.append(contentsOf: samples)
        accelerometerSampleCount =
            cumulativeAccelerometerCount + currentSession!.accelerometerSamples.count
    }

    private func processDeviceMotionSamples(_ samples: [DeviceMotionSample]) {
        guard isRecording else {
            logger.error("processDeviceMotionSamples(): not currently recording")
            return
        }
        assertExcludeCoverage(currentSession != nil, "isRecording implies currentSession != nil")
        currentSession!.deviceMotionSamples.append(contentsOf: samples)
        deviceMotionSampleCount =
            cumulativeDeviceMotionCount + currentSession!.deviceMotionSamples.count
    }
}
