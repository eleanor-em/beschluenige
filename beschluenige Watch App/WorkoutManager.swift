import Foundation
import os

@Observable
final class WorkoutManager {
    var isRecording = false
    var currentHeartRate: Double = 0
    var lastHeartRateSampleDate: Date?
    var lastLocationSampleDate: Date?
    var currentWorkout: Workout?
    var heartRateSampleCount: Int = 0
    var locationSampleCount: Int = 0
    var accelerometerSampleCount: Int = 0
    var deviceMotionSampleCount: Int = 0
    var chunkCount: Int = 0
    var flushInterval: TimeInterval = 120

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
        currentWorkout = Workout(startDate: Date())
        currentHeartRate = 0
        lastHeartRateSampleDate = nil
        lastLocationSampleDate = nil
        heartRateSampleCount = 0
        locationSampleCount = 0
        accelerometerSampleCount = 0
        deviceMotionSampleCount = 0
        cumulativeHeartRateCount = 0
        cumulativeLocationCount = 0
        cumulativeAccelerometerCount = 0
        cumulativeDeviceMotionCount = 0
        chunkCount = 0

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

        currentWorkout?.cumulativeSampleCount =
            cumulativeHeartRateCount + cumulativeLocationCount
            + cumulativeAccelerometerCount + cumulativeDeviceMotionCount

        currentWorkout?.endDate = Date()
        isRecording = false
    }

    func flushCurrentChunk() {
        guard isRecording || currentWorkout != nil else { return }
        guard currentWorkout != nil else { return }

        cumulativeHeartRateCount += currentWorkout!.heartRateSamples.count
        cumulativeLocationCount += currentWorkout!.locationSamples.count
        cumulativeAccelerometerCount += currentWorkout!.accelerometerSamples.count
        cumulativeDeviceMotionCount += currentWorkout!.deviceMotionSamples.count

        do {
            if let url = try currentWorkout!.flushChunk() {
                logger.info("Flushed chunk to \(url.lastPathComponent)")
            }
        } catch {
            logger.error("Failed to flush chunk: \(error.localizedDescription)")
        }

        heartRateSampleCount = cumulativeHeartRateCount + currentWorkout!.heartRateSamples.count
        locationSampleCount = cumulativeLocationCount + currentWorkout!.locationSamples.count
        accelerometerSampleCount =
            cumulativeAccelerometerCount + currentWorkout!.accelerometerSamples.count
        deviceMotionSampleCount =
            cumulativeDeviceMotionCount + currentWorkout!.deviceMotionSamples.count
        chunkCount += 1
    }

    private func processHeartRateSamples(_ samples: [HeartRateSample]) {
        guard isRecording else {
            logger.error("processSamples(): not currently recording")
            return
        }
        assertExcludeCoverage(currentWorkout != nil, "isRecording implies currentWorkout != nil")
        currentWorkout!.heartRateSamples.append(contentsOf: samples)
        heartRateSampleCount = cumulativeHeartRateCount + currentWorkout!.heartRateSamples.count
        if let last = samples.last {
            currentHeartRate = last.beatsPerMinute
            lastHeartRateSampleDate = last.timestamp
        }
    }

    private func processLocationSamples(_ samples: [LocationSample]) {
        guard isRecording else {
            logger.error("processLocationSamples(): not currently recording")
            return
        }
        assertExcludeCoverage(currentWorkout != nil, "isRecording implies currentWorkout != nil")
        currentWorkout!.locationSamples.append(contentsOf: samples)
        locationSampleCount = cumulativeLocationCount + currentWorkout!.locationSamples.count
        if let last = samples.last {
            lastLocationSampleDate = last.timestamp
        }
    }

    private func processAccelerometerSamples(_ samples: [AccelerometerSample]) {
        guard isRecording else {
            logger.error("processAccelerometerSamples(): not currently recording")
            return
        }
        assertExcludeCoverage(currentWorkout != nil, "isRecording implies currentWorkout != nil")
        currentWorkout!.accelerometerSamples.append(contentsOf: samples)
        accelerometerSampleCount =
            cumulativeAccelerometerCount + currentWorkout!.accelerometerSamples.count
    }

    private func processDeviceMotionSamples(_ samples: [DeviceMotionSample]) {
        guard isRecording else {
            logger.error("processDeviceMotionSamples(): not currently recording")
            return
        }
        assertExcludeCoverage(currentWorkout != nil, "isRecording implies currentWorkout != nil")
        currentWorkout!.deviceMotionSamples.append(contentsOf: samples)
        deviceMotionSampleCount =
            cumulativeDeviceMotionCount + currentWorkout!.deviceMotionSamples.count
    }

    func lastSampleDate() -> Date? {
        guard let lastHeartRateSampleDate = lastHeartRateSampleDate else { return nil }
        guard let lastLocationSampleDate = lastLocationSampleDate else { return nil }
        return min(lastHeartRateSampleDate, lastLocationSampleDate)
    }
}
