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

@MainActor
struct CoreMotionProviderTests {

    @Test func startMonitoringThrowsWhenAccelerometerUnavailable() {
        let provider = CoreMotionProvider()
        provider.setAccelerometerAvailableOverride(false)
        #expect(throws: MotionError.accelerometerUnavailable) {
            try provider.startMonitoring { _ in }
        }
    }

    @Test func startMonitoringWithoutOverrideUsesRealAvailability() throws {
        let provider = CoreMotionProvider()
        // No override set -- the ?? falls through to
        // motionManager.isAccelerometerAvailable
        if CMMotionManager().isAccelerometerAvailable {
            // Real hardware: accelerometer is available, should succeed
            try provider.startMonitoring { _ in }
            provider.stopMonitoring()
        } else {
            // Simulator: accelerometer is unavailable, should throw
            #expect(throws: MotionError.accelerometerUnavailable) {
                try provider.startMonitoring { _ in }
            }
        }
    }

    @Test func startMonitoringWithAvailabilityOverrideStartsUpdates() throws {
        let provider = CoreMotionProvider()
        provider.setAccelerometerAvailableOverride(true)

        try provider.startMonitoring { _ in }

        // The real-updates path was taken; handler should be set
        #expect(provider.getAccelerometerHandler() != nil)

        provider.stopMonitoring()
    }

    @Test func stopMonitoringWhenNotStartedIsHarmless() {
        let provider = CoreMotionProvider()
        provider.stopMonitoring()
    }

    // MARK: - startMonitoring without real updates

    @Test func startMonitoringWithoutRealUpdatesSetsHandler() throws {
        let provider = CoreMotionProvider()

        try provider.startMonitoring(handler: { _ in
        }, startRealUpdates: false)

        // Verify accelerometer handler was created
        let handler = provider.getAccelerometerHandler()
        #expect(handler != nil)

        // Verify batch is empty
        #expect(provider.getBatch().isEmpty)

        provider.stopMonitoring()
    }

    // MARK: - Accelerometer handler closure paths

    @Test func accelerometerHandlerWithData() async throws {
        let provider = CoreMotionProvider()

        try provider.startMonitoring(handler: { _ in
        }, startRealUpdates: false)

        let handler = provider.getAccelerometerHandler()!

        let data = FakeAccelerometerData(
            timestamp: ProcessInfo.processInfo.systemUptime,
            acceleration: CMAcceleration(x: 0.1, y: 0.2, z: 0.3)
        )
        handler(data, nil)

        // The handler dispatches to MainActor via Task, so we need to yield
        try await Task.sleep(for: .milliseconds(200))

        // Should have added one sample to the batch
        #expect(provider.getBatch().count == 1)

        provider.stopMonitoring()
    }

    @Test func accelerometerHandlerWithError() throws {
        let provider = CoreMotionProvider()

        try provider.startMonitoring(handler: { _ in }, startRealUpdates: false)

        let handler = provider.getAccelerometerHandler()!

        // Invoke with nil data and an error -- covers the error logging path
        handler(nil, NSError(domain: "TestDomain", code: 99))

        provider.stopMonitoring()
    }

    @Test func accelerometerHandlerWithNilDataNilError() throws {
        let provider = CoreMotionProvider()

        try provider.startMonitoring(handler: { _ in }, startRealUpdates: false)

        let handler = provider.getAccelerometerHandler()!

        // Invoke with nil data and nil error -- covers the guard-else-return path
        handler(nil, nil)

        provider.stopMonitoring()
    }

    // MARK: - addToBatch

    @Test func addToBatchAccumulatesSamples() throws {
        let provider = CoreMotionProvider()

        try provider.startMonitoring(handler: { _ in }, startRealUpdates: false)

        let sample = AccelerometerSample(
            timestamp: Date(),
            x: 0.1,
            y: 0.2,
            z: 0.3
        )

        provider.addToBatch(sample)
        provider.addToBatch(sample)
        provider.addToBatch(sample)

        #expect(provider.getBatch().count == 3)

        provider.stopMonitoring()
    }

    @Test func addToBatchFlushesAt100() throws {
        let provider = CoreMotionProvider()
        var received: [AccelerometerSample] = []

        try provider.startMonitoring(handler: { samples in
            received = samples
        }, startRealUpdates: false)

        let sample = AccelerometerSample(
            timestamp: Date(),
            x: 1.0,
            y: 2.0,
            z: 3.0
        )

        for _ in 0..<100 {
            provider.addToBatch(sample)
        }

        // Handler should have been called with 100 samples
        #expect(received.count == 100)
        // Batch should be reset
        #expect(provider.getBatch().isEmpty)

        provider.stopMonitoring()
    }

    @Test func addToBatchDoesNotFlushBelow100() throws {
        let provider = CoreMotionProvider()
        var handlerCalled = false

        try provider.startMonitoring(handler: { _ in
            handlerCalled = true
        }, startRealUpdates: false)

        let sample = AccelerometerSample(
            timestamp: Date(),
            x: 0.0,
            y: 0.0,
            z: 0.0
        )

        for _ in 0..<99 {
            provider.addToBatch(sample)
        }

        #expect(!handlerCalled)
        #expect(provider.getBatch().count == 99)

        provider.stopMonitoring()
    }

    // MARK: - stopMonitoring flush

    @Test func stopMonitoringFlushesRemainingBatch() {
        let provider = CoreMotionProvider()
        var received: [AccelerometerSample] = []

        provider.setSampleHandler { samples in
            received = samples
        }

        let samples = (0..<5).map { i in
            AccelerometerSample(
                timestamp: Date(),
                x: Double(i),
                y: 0.0,
                z: 0.0
            )
        }
        provider.setBatch(samples)

        provider.stopMonitoring()

        #expect(received.count == 5)
        #expect(received[0].x == 0.0)
        #expect(received[4].x == 4.0)
    }

    @Test func stopMonitoringWithEmptyBatchDoesNotCallHandler() {
        let provider = CoreMotionProvider()
        var handlerCalled = false

        provider.setSampleHandler { _ in
            handlerCalled = true
        }
        provider.setBatch([])

        provider.stopMonitoring()

        #expect(!handlerCalled)
    }
}
