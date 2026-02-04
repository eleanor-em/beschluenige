import CoreMotion
import Foundation
import os

final class CoreMotionProvider: MotionProvider, @unchecked Sendable {
    private let motionManager = CMMotionManager()
    private let operationQueue = OperationQueue()
    private var sampleHandler: (@Sendable ([AccelerometerSample]) -> Void)?
    private var batch: [AccelerometerSample] = []
    private var bootTimeDelta: TimeInterval = 0
    private var accelerometerHandler: ((CMAccelerometerData?, (any Error)?) -> Void)?
    private var accelerometerAvailableOverride: Bool?
    private let logger = Logger(
        subsystem: "net.lnor.beschluenige.watchkitapp",
        category: "CoreMotion"
    )

    init() {
        operationQueue.name = "net.lnor.beschluenige.accelerometer"
        operationQueue.maxConcurrentOperationCount = 1
    }

    func startMonitoring(
        handler: @escaping @Sendable ([AccelerometerSample]) -> Void
    ) throws {
        try startMonitoring(handler: handler, startRealUpdates: true)
    }

    func startMonitoring(
        handler: @escaping @Sendable ([AccelerometerSample]) -> Void,
        startRealUpdates: Bool
    ) throws {
        if startRealUpdates {
            let isAvailable = accelerometerAvailableOverride
                ?? motionManager.isAccelerometerAvailable
            guard isAvailable else {
                logger.error("Accelerometer not available")
                throw MotionError.accelerometerUnavailable
            }
        } else {
            preconditionExcludeCoverage(
                isRunningTests,
                "startRealUpdates: false is only allowed in test cases"
            )
        }

        sampleHandler = handler
        batch = []
        bootTimeDelta = Date().timeIntervalSinceReferenceDate
            - ProcessInfo.processInfo.systemUptime

        let handler: (CMAccelerometerData?, (any Error)?) -> Void = { [weak self] data, error in
            guard let self, let data else {
                if let error {
                    self?.logger.error(
                        "Accelerometer error: \(error.localizedDescription)")
                }
                return
            }

            let delta = self.bootTimeDelta
            let wallTimestamp = Date(
                timeIntervalSinceReferenceDate: data.timestamp + delta)
            let sample = AccelerometerSample(
                timestamp: wallTimestamp,
                x: data.acceleration.x,
                y: data.acceleration.y,
                z: data.acceleration.z
            )

            Task { @MainActor [weak self] in
                self?.addToBatch(sample)
            }
        }
        accelerometerHandler = handler

        if startRealUpdates {
            motionManager.accelerometerUpdateInterval = 0.01  // 100 Hz
            motionManager.startAccelerometerUpdates(to: operationQueue, withHandler: handler)
            logger.info("Started accelerometer updates at 100 Hz")
        }
    }

    func addToBatch(_ sample: AccelerometerSample) {
        batch.append(sample)
        if batch.count >= 100 {
            sampleHandler?(batch)
            batch = []
        }
    }

    func stopMonitoring() {
        motionManager.stopAccelerometerUpdates()

        // Flush remaining samples
        if !batch.isEmpty {
            sampleHandler?(batch)
            batch = []
        }

        sampleHandler = nil
        accelerometerHandler = nil
        logger.info("Stopped accelerometer updates")
    }

    // MARK: - Test Seams

    func getAccelerometerHandler() -> ((CMAccelerometerData?, (any Error)?) -> Void)? {
        preconditionExcludeCoverage(
            isRunningTests,
            "getAccelerometerHandler is only allowed in test cases"
        )
        return accelerometerHandler
    }

    func setSampleHandler(_ handler: (@Sendable ([AccelerometerSample]) -> Void)?) {
        preconditionExcludeCoverage(
            isRunningTests,
            "setSampleHandler is only allowed in test cases"
        )
        sampleHandler = handler
    }

    func setBatch(_ newBatch: [AccelerometerSample]) {
        preconditionExcludeCoverage(
            isRunningTests,
            "setBatch is only allowed in test cases"
        )
        batch = newBatch
    }

    func setAccelerometerAvailableOverride(_ value: Bool?) {
        preconditionExcludeCoverage(
            isRunningTests,
            "setAccelerometerAvailableOverride is only allowed in test cases"
        )
        accelerometerAvailableOverride = value
    }

    func getBatch() -> [AccelerometerSample] {
        preconditionExcludeCoverage(
            isRunningTests,
            "getBatch is only allowed in test cases"
        )
        return batch
    }
}

enum MotionError: Error {
    case accelerometerUnavailable
}
