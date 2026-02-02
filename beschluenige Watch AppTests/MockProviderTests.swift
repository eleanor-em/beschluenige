import Foundation
import Testing
@testable import beschluenige_Watch_App

// MARK: - MockHeartRateProvider

@MainActor
struct MockHeartRateProviderTests {

    @Test func startMonitoringDelegatesToRealProvider() async throws {
        let stub = StubHeartRateProvider()
        let mock = MockHeartRateProvider(realProvider: stub, timeoutInterval: 60)
        try await mock.startMonitoring { _ in }
        #expect(stub.monitoringStarted)
    }

    @Test func requestAuthorizationDelegates() async throws {
        let stub = StubHeartRateProvider()
        let mock = MockHeartRateProvider(realProvider: stub)
        try await mock.requestAuthorization()
        #expect(stub.authorizationRequested)
    }

    @Test func sendSamplesDeliversToHandler() async throws {
        let stub = StubHeartRateProvider()
        let mock = MockHeartRateProvider(realProvider: stub, timeoutInterval: 60)
        var received: [HeartRateSample] = []
        try await mock.startMonitoring { samples in
            received = samples
        }
        mock.sendSamples([
            HeartRateSample(timestamp: Date(), beatsPerMinute: 150),
        ])
        #expect(received.count == 1)
    }

    @Test func stopMonitoringDelegatesToRealProvider() async throws {
        let stub = StubHeartRateProvider()
        let mock = MockHeartRateProvider(realProvider: stub, timeoutInterval: 60)
        try await mock.startMonitoring { _ in }
        mock.stopMonitoring()
        #expect(stub.monitoringStopped)
    }

    @Test func stopBeforeStartIsHarmless() {
        let stub = StubHeartRateProvider()
        let mock = MockHeartRateProvider(realProvider: stub, timeoutInterval: 60)
        mock.stopMonitoring()
    }

    @Test func fallbackActivatesWhenNoRealSamples() async throws {
        let stub = StubHeartRateProvider()
        let mock = MockHeartRateProvider(realProvider: stub, timeoutInterval: 0.1)
        var callbackFired = false
        mock.onFallbackActivated = { callbackFired = true }

        var received: [HeartRateSample] = []
        try await mock.startMonitoring { samples in
            received.append(contentsOf: samples)
        }

        // Timeout fires at 0.1s, then fallback timer fires every 1s
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))

        #expect(callbackFired)
        #expect(!received.isEmpty)
    }

    @Test func fallbackSuppressedWhenRealSamplesReceived() async throws {
        let stub = StubHeartRateProvider()
        let mock = MockHeartRateProvider(realProvider: stub, timeoutInterval: 0.2)
        var callbackFired = false
        mock.onFallbackActivated = { callbackFired = true }

        try await mock.startMonitoring { _ in }

        // Real sample arrives before timeout
        stub.sendSamples([
            HeartRateSample(timestamp: Date(), beatsPerMinute: 120),
        ])

        RunLoop.main.run(until: Date().addingTimeInterval(0.5))

        #expect(!callbackFired)
    }

    @Test func stopInvalidatesFallbackTimer() async throws {
        let stub = StubHeartRateProvider()
        let mock = MockHeartRateProvider(realProvider: stub, timeoutInterval: 0.2)
        var callbackFired = false
        mock.onFallbackActivated = { callbackFired = true }

        try await mock.startMonitoring { _ in }
        mock.stopMonitoring()

        RunLoop.main.run(until: Date().addingTimeInterval(0.5))

        #expect(!callbackFired)
    }
}

// MARK: - MockLocationProvider

@MainActor
struct MockLocationProviderTests {

    @Test func startMonitoringDelegatesToRealProvider() async throws {
        let stub = StubLocationProvider()
        let mock = MockLocationProvider(
            realProviderFactory: { stub },
            timeoutInterval: 60
        )
        try await mock.startMonitoring { _ in }
        #expect(stub.monitoringStarted)
    }

    @Test func requestAuthorizationDelegates() async throws {
        let stub = StubLocationProvider()
        let mock = MockLocationProvider(
            realProviderFactory: { stub },
            timeoutInterval: 60
        )
        try await mock.requestAuthorization()
        #expect(stub.authorizationRequested)
    }

    @Test func sendSamplesDeliversToHandler() async throws {
        let stub = StubLocationProvider()
        let mock = MockLocationProvider(
            realProviderFactory: { stub },
            timeoutInterval: 60
        )
        var received: [LocationSample] = []
        try await mock.startMonitoring { samples in
            received = samples
        }
        mock.sendSamples([
            LocationSample(
                timestamp: Date(), latitude: 43.0, longitude: -79.0,
                altitude: 76.0, horizontalAccuracy: 5.0, verticalAccuracy: 8.0,
                speed: 3.0, course: 90.0
            ),
        ])
        #expect(received.count == 1)
    }

    @Test func stopMonitoringDelegatesToRealProvider() async throws {
        let stub = StubLocationProvider()
        let mock = MockLocationProvider(
            realProviderFactory: { stub },
            timeoutInterval: 60
        )
        try await mock.startMonitoring { _ in }
        mock.stopMonitoring()
        #expect(stub.monitoringStopped)
    }

    @Test func stopBeforeStartIsHarmless() {
        let stub = StubLocationProvider()
        let mock = MockLocationProvider(
            realProviderFactory: { stub },
            timeoutInterval: 60
        )
        mock.stopMonitoring()
    }

    @Test func fallbackActivatesWhenNoRealSamples() async throws {
        let stub = StubLocationProvider()
        let mock = MockLocationProvider(
            realProviderFactory: { stub },
            timeoutInterval: 0.1
        )
        var callbackFired = false
        mock.onFallbackActivated = { callbackFired = true }

        var received: [LocationSample] = []
        try await mock.startMonitoring { samples in
            received.append(contentsOf: samples)
        }

        RunLoop.main.run(until: Date().addingTimeInterval(1.5))

        #expect(callbackFired)
        #expect(!received.isEmpty)
    }

    @Test func fallbackSuppressedWhenRealSamplesReceived() async throws {
        let stub = StubLocationProvider()
        let mock = MockLocationProvider(
            realProviderFactory: { stub },
            timeoutInterval: 0.2
        )
        var callbackFired = false
        mock.onFallbackActivated = { callbackFired = true }

        try await mock.startMonitoring { _ in }

        stub.sendSamples([
            LocationSample(
                timestamp: Date(), latitude: 43.0, longitude: -79.0,
                altitude: 76.0, horizontalAccuracy: 5.0, verticalAccuracy: 8.0,
                speed: 3.0, course: 90.0
            ),
        ])

        RunLoop.main.run(until: Date().addingTimeInterval(0.5))

        #expect(!callbackFired)
    }

    @Test func startMonitoringCreatesProviderIfNeeded() async throws {
        var created = false
        let stub = StubLocationProvider()
        let mock = MockLocationProvider(
            realProviderFactory: {
                created = true
                return stub
            },
            timeoutInterval: 60
        )
        try await mock.startMonitoring { _ in }
        #expect(created)
    }
}

// MARK: - MockMotionProvider

@MainActor
struct MockMotionProviderTests {

    @Test func startMonitoringDelegatesToRealProvider() throws {
        let stub = StubMotionProvider()
        let mock = MockMotionProvider(
            realProviderFactory: { stub },
            timeoutInterval: 60
        )
        try mock.startMonitoring { _ in }
        #expect(stub.monitoringStarted)
    }

    @Test func sendSamplesDeliversToHandler() throws {
        let stub = StubMotionProvider()
        let mock = MockMotionProvider(
            realProviderFactory: { stub },
            timeoutInterval: 60
        )
        var received: [AccelerometerSample] = []
        try mock.startMonitoring { samples in
            received = samples
        }
        mock.sendSamples([
            AccelerometerSample(timestamp: Date(), x: 0.1, y: -0.2, z: 0.98),
        ])
        #expect(received.count == 1)
    }

    @Test func stopMonitoringDelegatesToRealProvider() throws {
        let stub = StubMotionProvider()
        let mock = MockMotionProvider(
            realProviderFactory: { stub },
            timeoutInterval: 60
        )
        try mock.startMonitoring { _ in }
        mock.stopMonitoring()
        #expect(stub.monitoringStopped)
    }

    @Test func stopBeforeStartIsHarmless() {
        let stub = StubMotionProvider()
        let mock = MockMotionProvider(
            realProviderFactory: { stub },
            timeoutInterval: 60
        )
        mock.stopMonitoring()
    }

    @Test func realProviderThrowingContinuesWithFallback() async throws {
        let stub = StubMotionProvider()
        stub.shouldThrow = true
        let mock = MockMotionProvider(
            realProviderFactory: { stub },
            timeoutInterval: 0.1
        )
        var callbackFired = false
        mock.onFallbackActivated = { callbackFired = true }

        var received: [AccelerometerSample] = []
        try mock.startMonitoring { samples in
            received.append(contentsOf: samples)
        }

        RunLoop.main.run(until: Date().addingTimeInterval(1.5))

        #expect(callbackFired)
        #expect(!received.isEmpty)
    }

    @Test func fallbackActivatesWhenNoRealSamples() async throws {
        let stub = StubMotionProvider()
        let mock = MockMotionProvider(
            realProviderFactory: { stub },
            timeoutInterval: 0.1
        )
        var callbackFired = false
        mock.onFallbackActivated = { callbackFired = true }

        var received: [AccelerometerSample] = []
        try mock.startMonitoring { samples in
            received.append(contentsOf: samples)
        }

        RunLoop.main.run(until: Date().addingTimeInterval(1.5))

        #expect(callbackFired)
        #expect(!received.isEmpty)
    }

    @Test func fallbackSuppressedWhenRealSamplesReceived() async throws {
        let stub = StubMotionProvider()
        let mock = MockMotionProvider(
            realProviderFactory: { stub },
            timeoutInterval: 0.2
        )
        var callbackFired = false
        mock.onFallbackActivated = { callbackFired = true }

        try mock.startMonitoring { _ in }

        stub.sendSamples([
            AccelerometerSample(timestamp: Date(), x: 0.1, y: 0.0, z: 1.0),
        ])

        RunLoop.main.run(until: Date().addingTimeInterval(0.5))

        #expect(!callbackFired)
    }

    @Test func fallbackGenerates100SamplesPerBatch() async throws {
        let stub = StubMotionProvider()
        let mock = MockMotionProvider(
            realProviderFactory: { stub },
            timeoutInterval: 0.1
        )

        var batches: [[AccelerometerSample]] = []
        try mock.startMonitoring { samples in
            batches.append(samples)
        }

        RunLoop.main.run(until: Date().addingTimeInterval(1.5))

        #expect(!batches.isEmpty)
        if let first = batches.first {
            #expect(first.count == 100)
        }
    }
}
