import CoreMotion
import Foundation
import os

final class CoreDeviceMotionProvider: DeviceMotionProvider, @unchecked Sendable {
    private let manager = CMBatchedSensorManager()
    private var accelTask: Task<Void, Never>?
    private var dmTask: Task<Void, Never>?
    private var bootTimeDelta: TimeInterval = 0
    private var accelerometerAvailableOverride: Bool?
    private var deviceMotionAvailableOverride: Bool?
    nonisolated(unsafe) private var accelStreamFactory:
        @Sendable () -> AsyncThrowingStream<[CMAccelerometerData], any Error>
    nonisolated(unsafe) private var dmStreamFactory:
        @Sendable () -> AsyncThrowingStream<[CMDeviceMotion], any Error>
    private let logger = Logger(
        subsystem: "net.lnor.beschluenige.watchkitapp",
        category: "CoreMotion"
    )

    init() {
        let mgr = manager
        #if targetEnvironment(simulator)
        // On simulator, CMBatchedSensorManager streams are not available.
        // Tests must inject stream factories via setAccelStreamFactory/setDMStreamFactory.
        // The availability check in startMonitoring will throw before these are called
        // unless the test also sets stream factories.
        accelStreamFactory = { AsyncThrowingStream { $0.finish() } }
        dmStreamFactory = { AsyncThrowingStream { $0.finish() } }
        #else
        accelStreamFactory = {
            AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        for try await batch in mgr.accelerometerUpdates() {
                            continuation.yield(batch)
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }
        dmStreamFactory = {
            AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        for try await batch in mgr.deviceMotionUpdates() {
                            continuation.yield(batch)
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }
        #endif
    }

    func startMonitoring(
        accelerometerHandler: @escaping @Sendable ([AccelerometerSample]) -> Void,
        deviceMotionHandler: @escaping @Sendable ([DeviceMotionSample]) -> Void
    ) throws {
        let accelAvailable = accelerometerAvailableOverride
            ?? CMBatchedSensorManager.isAccelerometerSupported
        guard accelAvailable else {
            logger.error("Accelerometer not available")
            throw MotionError.accelerometerUnavailable
        }
        let dmAvailable = deviceMotionAvailableOverride
            ?? CMBatchedSensorManager.isDeviceMotionSupported
        guard dmAvailable else {
            logger.error("Device motion not available")
            throw MotionError.deviceMotionUnavailable
        }

        bootTimeDelta = Date().timeIntervalSinceReferenceDate
            - ProcessInfo.processInfo.systemUptime

        let delta = bootTimeDelta
        let makeAccelStream = accelStreamFactory
        let makeDMStream = dmStreamFactory

        accelTask = Task.detached {
            let stream = makeAccelStream()
            await Self.iterateAccelStream(stream, delta: delta, handler: accelerometerHandler)
        }

        dmTask = Task.detached {
            let stream = makeDMStream()
            await Self.iterateDMStream(stream, delta: delta, handler: deviceMotionHandler)
        }

        logger.info("Started batched accelerometer (800 Hz) and device motion (200 Hz) updates")
    }

    static func iterateAccelStream(
        _ stream: AsyncThrowingStream<[CMAccelerometerData], any Error>,
        delta: TimeInterval,
        handler: @escaping @Sendable ([AccelerometerSample]) -> Void
    ) async {
        do {
            for try await batch in stream {
                let samples = convertAccelerometerBatch(batch, delta: delta)
                handler(samples)
            }
        } catch is CancellationError {
            // Expected during stopMonitoring -- no log needed
        } catch {
            Logger(
                subsystem: "net.lnor.beschluenige.watchkitapp",
                category: "CoreMotion"
            ).error("Accelerometer stream error: \(error.localizedDescription)")
        }
    }

    static func iterateDMStream(
        _ stream: AsyncThrowingStream<[CMDeviceMotion], any Error>,
        delta: TimeInterval,
        handler: @escaping @Sendable ([DeviceMotionSample]) -> Void
    ) async {
        do {
            for try await batch in stream {
                let samples = convertDeviceMotionBatch(batch, delta: delta)
                handler(samples)
            }
        } catch is CancellationError {
            // Expected during stopMonitoring -- no log needed
        } catch {
            Logger(
                subsystem: "net.lnor.beschluenige.watchkitapp",
                category: "CoreMotion"
            ).error("Device motion stream error: \(error.localizedDescription)")
        }
    }

    func stopMonitoring() {
        accelTask?.cancel()
        accelTask = nil
        dmTask?.cancel()
        dmTask = nil
        logger.info("Stopped accelerometer and device motion updates")
    }

    // MARK: - Conversion

    static func convertAccelerometerBatch(
        _ batch: [CMAccelerometerData],
        delta: TimeInterval
    ) -> [AccelerometerSample] {
        batch.map { data in
            AccelerometerSample(
                timestamp: Date(
                    timeIntervalSinceReferenceDate: data.timestamp + delta),
                x: data.acceleration.x,
                y: data.acceleration.y,
                z: data.acceleration.z
            )
        }
    }

    static func convertDeviceMotionBatch(
        _ batch: [CMDeviceMotion],
        delta: TimeInterval
    ) -> [DeviceMotionSample] {
        batch.map { motion in
            DeviceMotionSample(
                timestamp: Date(
                    timeIntervalSinceReferenceDate: motion.timestamp + delta),
                roll: motion.attitude.roll,
                pitch: motion.attitude.pitch,
                yaw: motion.attitude.yaw,
                rotationRateX: motion.rotationRate.x,
                rotationRateY: motion.rotationRate.y,
                rotationRateZ: motion.rotationRate.z,
                userAccelerationX: motion.userAcceleration.x,
                userAccelerationY: motion.userAcceleration.y,
                userAccelerationZ: motion.userAcceleration.z,
                heading: motion.heading
            )
        }
    }

    // MARK: - Test Seams

    func setAccelerometerAvailableOverride(_ value: Bool?) {
        preconditionExcludeCoverage(
            isRunningTests,
            "setAccelerometerAvailableOverride is only allowed in test cases"
        )
        accelerometerAvailableOverride = value
    }

    func setDeviceMotionAvailableOverride(_ value: Bool?) {
        preconditionExcludeCoverage(
            isRunningTests,
            "setDeviceMotionAvailableOverride is only allowed in test cases"
        )
        deviceMotionAvailableOverride = value
    }

    func setAccelStreamFactory(
        _ factory: @escaping @Sendable () -> AsyncThrowingStream<[CMAccelerometerData], any Error>
    ) {
        preconditionExcludeCoverage(
            isRunningTests,
            "setAccelStreamFactory is only allowed in test cases"
        )
        accelStreamFactory = factory
    }

    func setDMStreamFactory(
        _ factory: @escaping @Sendable () -> AsyncThrowingStream<[CMDeviceMotion], any Error>
    ) {
        preconditionExcludeCoverage(
            isRunningTests,
            "setDMStreamFactory is only allowed in test cases"
        )
        dmStreamFactory = factory
    }
}

enum MotionError: Error {
    case accelerometerUnavailable
    case deviceMotionUnavailable
}
