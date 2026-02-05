import CoreMotion
import Foundation
import Testing
@testable import beschluenige_Watch_App

private class FakeAccelerometerData: CMAccelerometerData {
    private let _timestamp: TimeInterval
    private let _acceleration: CMAcceleration

    init(timestamp: TimeInterval, acceleration: CMAcceleration) {
        _timestamp = timestamp
        _acceleration = acceleration
        super.init()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Not supported")
    }

    override var timestamp: TimeInterval { _timestamp }
    override var acceleration: CMAcceleration { _acceleration }
}

private class FakeAttitude: CMAttitude {
    private let _roll: Double
    private let _pitch: Double
    private let _yaw: Double

    init(roll: Double, pitch: Double, yaw: Double) {
        _roll = roll
        _pitch = pitch
        _yaw = yaw
        super.init()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Not supported")
    }

    override var roll: Double { _roll }
    override var pitch: Double { _pitch }
    override var yaw: Double { _yaw }
}

private class FakeDeviceMotion: CMDeviceMotion {
    private let _timestamp: TimeInterval
    private let _attitude: CMAttitude
    private let _rotationRate: CMRotationRate
    private let _userAcceleration: CMAcceleration
    private let _heading: Double

    init(
        timestamp: TimeInterval,
        attitude: CMAttitude,
        rotationRate: CMRotationRate,
        userAcceleration: CMAcceleration,
        heading: Double
    ) {
        _timestamp = timestamp
        _attitude = attitude
        _rotationRate = rotationRate
        _userAcceleration = userAcceleration
        _heading = heading
        super.init()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Not supported")
    }

    override var timestamp: TimeInterval { _timestamp }
    override var attitude: CMAttitude { _attitude }
    override var rotationRate: CMRotationRate { _rotationRate }
    override var userAcceleration: CMAcceleration { _userAcceleration }
    override var heading: Double { _heading }
}

private func makeFakeDeviceMotion(timestamp: TimeInterval) -> FakeDeviceMotion {
    FakeDeviceMotion(
        timestamp: timestamp,
        attitude: FakeAttitude(roll: 0.1, pitch: 0.2, yaw: 0.3),
        rotationRate: CMRotationRate(x: 1.0, y: 2.0, z: 3.0),
        userAcceleration: CMAcceleration(x: 0.01, y: 0.02, z: 0.03),
        heading: 90.0
    )
}

@MainActor
struct CoreMotionProviderTests {

    // MARK: - Availability

    @Test func startMonitoringThrowsWhenAccelerometerUnavailable() {
        let provider = CoreMotionProvider()
        provider.setAccelerometerAvailableOverride(false)
        provider.setDeviceMotionAvailableOverride(true)
        #expect(throws: MotionError.accelerometerUnavailable) {
            try provider.startMonitoring(
                accelerometerHandler: { _ in },
                deviceMotionHandler: { _ in }
            )
        }
    }

    @Test func startMonitoringThrowsWhenDeviceMotionUnavailable() {
        let provider = CoreMotionProvider()
        provider.setAccelerometerAvailableOverride(true)
        provider.setDeviceMotionAvailableOverride(false)
        #expect(throws: MotionError.deviceMotionUnavailable) {
            try provider.startMonitoring(
                accelerometerHandler: { _ in },
                deviceMotionHandler: { _ in }
            )
        }
    }

    @Test func startMonitoringWithoutOverrideUsesRealAvailability() throws {
        let provider = CoreMotionProvider()
        if CMBatchedSensorManager.isAccelerometerSupported
            && CMBatchedSensorManager.isDeviceMotionSupported {
            try provider.startMonitoring(
                accelerometerHandler: { _ in },
                deviceMotionHandler: { _ in }
            )
            provider.stopMonitoring()
        } else if !CMBatchedSensorManager.isAccelerometerSupported {
            #expect(throws: MotionError.accelerometerUnavailable) {
                try provider.startMonitoring(
                    accelerometerHandler: { _ in },
                    deviceMotionHandler: { _ in }
                )
            }
        } else {
            #expect(throws: MotionError.deviceMotionUnavailable) {
                try provider.startMonitoring(
                    accelerometerHandler: { _ in },
                    deviceMotionHandler: { _ in }
                )
            }
        }
    }

    @Test func startMonitoringFallsBackToRealDeviceMotionAvailability() throws {
        let provider = CoreMotionProvider()
        provider.setAccelerometerAvailableOverride(true)
        // deviceMotionAvailableOverride is nil, so it falls through to
        // CMBatchedSensorManager.isDeviceMotionSupported
        if CMBatchedSensorManager.isDeviceMotionSupported {
            try provider.startMonitoring(
                accelerometerHandler: { _ in },
                deviceMotionHandler: { _ in }
            )
            provider.stopMonitoring()
        } else {
            #expect(throws: MotionError.deviceMotionUnavailable) {
                try provider.startMonitoring(
                    accelerometerHandler: { _ in },
                    deviceMotionHandler: { _ in }
                )
            }
        }
    }

    @Test func startMonitoringWithDefaultFactoryUsesBuiltInStream() async throws {
        let provider = CoreMotionProvider()
        provider.setAccelerometerAvailableOverride(true)
        provider.setDeviceMotionAvailableOverride(true)
        // Do not set stream factories -- exercises the default (simulator: empty stream)
        try provider.startMonitoring(
            accelerometerHandler: { _ in },
            deviceMotionHandler: { _ in }
        )
        // Give detached tasks time to consume the empty streams
        try await Task.sleep(for: .milliseconds(100))
        provider.stopMonitoring()
    }

    @Test func stopMonitoringWhenNotStartedIsHarmless() {
        let provider = CoreMotionProvider()
        provider.stopMonitoring()
    }

    // MARK: - Accelerometer batch conversion

    @Test func convertAccelerometerBatchSingleSample() {
        let delta: TimeInterval = 100.0
        let bootTimestamp: TimeInterval = 50.0
        let data = FakeAccelerometerData(
            timestamp: bootTimestamp,
            acceleration: CMAcceleration(x: 0.1, y: 0.2, z: 0.3)
        )

        let result = CoreMotionProvider.convertAccelerometerBatch([data], delta: delta)

        #expect(result.count == 1)
        let expected = Date(timeIntervalSinceReferenceDate: bootTimestamp + delta)
        #expect(result[0].timestamp == expected)
        #expect(result[0].x == 0.1)
        #expect(result[0].y == 0.2)
        #expect(result[0].z == 0.3)
    }

    @Test func convertAccelerometerBatchMultipleSamples() {
        let delta: TimeInterval = 200.0
        let batch: [CMAccelerometerData] = [
            FakeAccelerometerData(
                timestamp: 10.0,
                acceleration: CMAcceleration(x: 1.0, y: 2.0, z: 3.0)
            ),
            FakeAccelerometerData(
                timestamp: 10.01,
                acceleration: CMAcceleration(x: 4.0, y: 5.0, z: 6.0)
            ),
            FakeAccelerometerData(
                timestamp: 10.02,
                acceleration: CMAcceleration(x: 7.0, y: 8.0, z: 9.0)
            ),
        ]

        let result = CoreMotionProvider.convertAccelerometerBatch(batch, delta: delta)

        #expect(result.count == 3)
        #expect(result[0].x == 1.0)
        #expect(result[1].x == 4.0)
        #expect(result[2].x == 7.0)
        #expect(result[2].timestamp == Date(timeIntervalSinceReferenceDate: 210.02))
    }

    @Test func convertAccelerometerBatchEmpty() {
        let result = CoreMotionProvider.convertAccelerometerBatch([], delta: 0)
        #expect(result.isEmpty)
    }

    // MARK: - Device motion batch conversion

    @Test func convertDeviceMotionBatchSingleSample() {
        let delta: TimeInterval = 100.0
        let bootTimestamp: TimeInterval = 50.0
        let motion = makeFakeDeviceMotion(timestamp: bootTimestamp)

        let result = CoreMotionProvider.convertDeviceMotionBatch([motion], delta: delta)

        #expect(result.count == 1)
        let s = result[0]
        let expected = Date(timeIntervalSinceReferenceDate: bootTimestamp + delta)
        #expect(s.timestamp == expected)
        #expect(s.roll == 0.1)
        #expect(s.pitch == 0.2)
        #expect(s.yaw == 0.3)
        #expect(s.rotationRateX == 1.0)
        #expect(s.rotationRateY == 2.0)
        #expect(s.rotationRateZ == 3.0)
        #expect(s.userAccelerationX == 0.01)
        #expect(s.userAccelerationY == 0.02)
        #expect(s.userAccelerationZ == 0.03)
        #expect(s.heading == 90.0)
    }

    @Test func convertDeviceMotionBatchMultipleSamples() {
        let delta: TimeInterval = 200.0
        let batch: [CMDeviceMotion] = [
            makeFakeDeviceMotion(timestamp: 10.0),
            makeFakeDeviceMotion(timestamp: 10.005),
            makeFakeDeviceMotion(timestamp: 10.01),
        ]

        let result = CoreMotionProvider.convertDeviceMotionBatch(batch, delta: delta)

        #expect(result.count == 3)
        #expect(result[0].roll == 0.1)
        #expect(result[1].heading == 90.0)
        #expect(result[2].timestamp == Date(timeIntervalSinceReferenceDate: 210.01))
    }

    @Test func convertDeviceMotionBatchEmpty() {
        let result = CoreMotionProvider.convertDeviceMotionBatch([], delta: 0)
        #expect(result.isEmpty)
    }

    // MARK: - Stream integration via factories

    @Test func startMonitoringDeliversAccelSamplesFromStream() async throws {
        let provider = CoreMotionProvider()
        provider.setAccelerometerAvailableOverride(true)
        provider.setDeviceMotionAvailableOverride(true)

        provider.setAccelStreamFactory {
            AsyncThrowingStream { cont in
                let batch: [CMAccelerometerData] = [
                    FakeAccelerometerData(
                        timestamp: 50.0,
                        acceleration: CMAcceleration(x: 0.5, y: 0.6, z: 0.7)
                    ),
                ]
                cont.yield(batch)
                cont.finish()
            }
        }
        provider.setDMStreamFactory {
            AsyncThrowingStream { cont in cont.finish() }
        }

        var received: [AccelerometerSample] = []
        let expectation = AsyncStream<Void>.makeStream()

        try provider.startMonitoring(
            accelerometerHandler: { samples in
                received = samples
                expectation.continuation.yield()
                expectation.continuation.finish()
            },
            deviceMotionHandler: { _ in }
        )

        for await _ in expectation.stream { break }

        #expect(received.count == 1)
        #expect(received[0].x == 0.5)
        #expect(received[0].y == 0.6)
        #expect(received[0].z == 0.7)

        provider.stopMonitoring()
    }

    @Test func startMonitoringDeliversDMSamplesFromStream() async throws {
        let provider = CoreMotionProvider()
        provider.setAccelerometerAvailableOverride(true)
        provider.setDeviceMotionAvailableOverride(true)

        provider.setAccelStreamFactory {
            AsyncThrowingStream { cont in cont.finish() }
        }
        provider.setDMStreamFactory {
            AsyncThrowingStream { cont in
                let batch: [CMDeviceMotion] = [makeFakeDeviceMotion(timestamp: 50.0)]
                cont.yield(batch)
                cont.finish()
            }
        }

        var received: [DeviceMotionSample] = []
        let expectation = AsyncStream<Void>.makeStream()

        try provider.startMonitoring(
            accelerometerHandler: { _ in },
            deviceMotionHandler: { samples in
                received = samples
                expectation.continuation.yield()
                expectation.continuation.finish()
            }
        )

        for await _ in expectation.stream { break }

        #expect(received.count == 1)
        #expect(received[0].roll == 0.1)
        #expect(received[0].heading == 90.0)

        provider.stopMonitoring()
    }

    // MARK: - Error handling via iterateAccelStream / iterateDMStream

    @Test func iterateAccelStreamHandlesError() async {
        let stream = AsyncThrowingStream<[CMAccelerometerData], any Error> { cont in
            cont.finish(throwing: NSError(domain: "TestDomain", code: 42))
        }

        await CoreMotionProvider.iterateAccelStream(
            stream, delta: 0, handler: { _ in })
    }

    @Test func iterateDMStreamHandlesError() async {
        let stream = AsyncThrowingStream<[CMDeviceMotion], any Error> { cont in
            cont.finish(throwing: NSError(domain: "TestDomain", code: 42))
        }

        await CoreMotionProvider.iterateDMStream(
            stream, delta: 0, handler: { _ in })
    }

    @Test func iterateAccelStreamDeliversMultipleBatches() async {
        var allSamples: [[AccelerometerSample]] = []

        let stream = AsyncThrowingStream<[CMAccelerometerData], any Error> { cont in
            cont.yield([
                FakeAccelerometerData(
                    timestamp: 1.0,
                    acceleration: CMAcceleration(x: 1.0, y: 0.0, z: 0.0)
                ),
            ])
            cont.yield([
                FakeAccelerometerData(
                    timestamp: 2.0,
                    acceleration: CMAcceleration(x: 2.0, y: 0.0, z: 0.0)
                ),
            ])
            cont.finish()
        }

        await CoreMotionProvider.iterateAccelStream(
            stream, delta: 100.0, handler: { samples in allSamples.append(samples) })

        #expect(allSamples.count == 2)
        #expect(allSamples[0][0].x == 1.0)
        #expect(allSamples[1][0].x == 2.0)
    }

    @Test func iterateDMStreamDeliversMultipleBatches() async {
        var allSamples: [[DeviceMotionSample]] = []

        let stream = AsyncThrowingStream<[CMDeviceMotion], any Error> { cont in
            cont.yield([makeFakeDeviceMotion(timestamp: 1.0)])
            cont.yield([makeFakeDeviceMotion(timestamp: 2.0)])
            cont.finish()
        }

        await CoreMotionProvider.iterateDMStream(
            stream, delta: 100.0, handler: { samples in allSamples.append(samples) })

        #expect(allSamples.count == 2)
        #expect(allSamples[0][0].roll == 0.1)
        #expect(allSamples[1][0].heading == 90.0)
    }
}
