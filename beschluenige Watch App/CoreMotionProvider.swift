import CoreMotion
import Foundation
import os

final class CoreMotionProvider: MotionProvider, @unchecked Sendable {
    private let motionManager = CMMotionManager()
    private let operationQueue = OperationQueue()
    private var sampleHandler: (@Sendable ([AccelerometerSample]) -> Void)?
    private var batch: [AccelerometerSample] = []
    private var bootTimeDelta: TimeInterval = 0
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
        guard motionManager.isAccelerometerAvailable else {
            logger.error("Accelerometer not available")
            throw MotionError.accelerometerUnavailable
        }

        sampleHandler = handler
        batch = []
        bootTimeDelta = Date().timeIntervalSinceReferenceDate
            - ProcessInfo.processInfo.systemUptime

        motionManager.accelerometerUpdateInterval = 0.01  // 100 Hz
        motionManager.startAccelerometerUpdates(to: operationQueue) { [weak self] data, error in
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

        logger.info("Started accelerometer updates at 100 Hz")
    }

    private func addToBatch(_ sample: AccelerometerSample) {
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
        logger.info("Stopped accelerometer updates")
    }
}

enum MotionError: Error {
    case accelerometerUnavailable
}
