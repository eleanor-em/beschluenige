import Foundation
import Testing
@testable import beschluenige_Watch_App

private final class Flag: @unchecked Sendable {
    var value = false
}

private final class Collector<T: Sendable>: @unchecked Sendable {
    var items: [T] = []
    func append(_ item: T) { items.append(item) }
    func append(contentsOf newItems: [T]) { items.append(contentsOf: newItems) }
    func replace(with newItems: [T]) { items = newItems }
}

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
        let received = Collector<HeartRateSample>()
        try await mock.startMonitoring { samples in
            received.replace(with: samples)
        }
        mock.sendSamples([
            HeartRateSample(timestamp: Date(), beatsPerMinute: 150),
        ])
        #expect(received.items.count == 1)
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
        let callbackFired = Flag()
        mock.onFallbackActivated = { callbackFired.value = true }

        let received = Collector<HeartRateSample>()
        try await mock.startMonitoring { samples in
            received.append(contentsOf: samples)
        }

        // Timeout fires at 0.1s, then fallback timer fires every 1s
        try await Task.sleep(for: .milliseconds(3000))

        #expect(callbackFired.value)
        #expect(!received.items.isEmpty)
    }

    @Test func fallbackSuppressedWhenRealSamplesReceived() async throws {
        let stub = StubHeartRateProvider()
        let mock = MockHeartRateProvider(realProvider: stub, timeoutInterval: 0.2)
        let callbackFired = Flag()
        mock.onFallbackActivated = { callbackFired.value = true }

        try await mock.startMonitoring { _ in }

        // Real sample arrives before timeout
        stub.sendSamples([
            HeartRateSample(timestamp: Date(), beatsPerMinute: 120),
        ])

        try await Task.sleep(for: .milliseconds(500))

        #expect(!callbackFired.value)
    }

    @Test func stopInvalidatesFallbackTimer() async throws {
        let stub = StubHeartRateProvider()
        let mock = MockHeartRateProvider(realProvider: stub, timeoutInterval: 0.2)
        let callbackFired = Flag()
        mock.onFallbackActivated = { callbackFired.value = true }

        try await mock.startMonitoring { _ in }
        mock.stopMonitoring()

        try await Task.sleep(for: .milliseconds(500))

        #expect(!callbackFired.value)
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
        let received = Collector<LocationSample>()
        try await mock.startMonitoring { samples in
            received.replace(with: samples)
        }
        mock.sendSamples([
            LocationSample(
                timestamp: Date(), latitude: 43.0, longitude: -79.0,
                altitude: 76.0, horizontalAccuracy: 5.0, verticalAccuracy: 8.0,
                speed: 3.0, course: 90.0
            ),
        ])
        #expect(received.items.count == 1)
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
        let callbackFired = Flag()
        mock.onFallbackActivated = { callbackFired.value = true }

        let received = Collector<LocationSample>()
        try await mock.startMonitoring { samples in
            received.append(contentsOf: samples)
        }

        try await Task.sleep(for: .milliseconds(3000))

        #expect(callbackFired.value)
        #expect(!received.items.isEmpty)
    }

    @Test func fallbackSuppressedWhenRealSamplesReceived() async throws {
        let stub = StubLocationProvider()
        let mock = MockLocationProvider(
            realProviderFactory: { stub },
            timeoutInterval: 0.2
        )
        let callbackFired = Flag()
        mock.onFallbackActivated = { callbackFired.value = true }

        try await mock.startMonitoring { _ in }

        stub.sendSamples([
            LocationSample(
                timestamp: Date(), latitude: 43.0, longitude: -79.0,
                altitude: 76.0, horizontalAccuracy: 5.0, verticalAccuracy: 8.0,
                speed: 3.0, course: 90.0
            ),
        ])

        try await Task.sleep(for: .milliseconds(500))

        #expect(!callbackFired.value)
    }

    @Test func startMonitoringCreatesProviderIfNeeded() async throws {
        let created = Flag()
        let stub = StubLocationProvider()
        let mock = MockLocationProvider(
            realProviderFactory: {
                created.value = true
                return stub
            },
            timeoutInterval: 60
        )
        try await mock.startMonitoring { _ in }
        #expect(created.value)
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
        try mock.startMonitoring(
            accelerometerHandler: { _ in },
            deviceMotionHandler: { _ in }
        )
        #expect(stub.monitoringStarted)
    }

    @Test func sendAccelSamplesDeliversToHandler() throws {
        let stub = StubMotionProvider()
        let mock = MockMotionProvider(
            realProviderFactory: { stub },
            timeoutInterval: 60
        )
        let received = Collector<AccelerometerSample>()
        try mock.startMonitoring(
            accelerometerHandler: { samples in
                received.replace(with: samples)
            },
            deviceMotionHandler: { _ in }
        )
        mock.sendAccelSamples([
            AccelerometerSample(timestamp: Date(), x: 0.1, y: -0.2, z: 0.98),
        ])
        #expect(received.items.count == 1)
    }

    @Test func sendDMSamplesDeliversToHandler() throws {
        let stub = StubMotionProvider()
        let mock = MockMotionProvider(
            realProviderFactory: { stub },
            timeoutInterval: 60
        )
        let received = Collector<DeviceMotionSample>()
        try mock.startMonitoring(
            accelerometerHandler: { _ in },
            deviceMotionHandler: { samples in
                received.replace(with: samples)
            }
        )
        mock.sendDMSamples([
            DeviceMotionSample(
                timestamp: Date(), roll: 0.1, pitch: 0.2, yaw: 0.3,
                rotationRateX: 1.0, rotationRateY: 2.0, rotationRateZ: 3.0,
                userAccelerationX: 0.01, userAccelerationY: 0.02, userAccelerationZ: 0.03,
                heading: 90.0
            ),
        ])
        #expect(received.items.count == 1)
    }

    @Test func stopMonitoringDelegatesToRealProvider() throws {
        let stub = StubMotionProvider()
        let mock = MockMotionProvider(
            realProviderFactory: { stub },
            timeoutInterval: 60
        )
        try mock.startMonitoring(
            accelerometerHandler: { _ in },
            deviceMotionHandler: { _ in }
        )
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
        let callbackFired = Flag()
        mock.onFallbackActivated = { callbackFired.value = true }

        let received = Collector<AccelerometerSample>()
        try mock.startMonitoring(
            accelerometerHandler: { samples in
                received.append(contentsOf: samples)
            },
            deviceMotionHandler: { _ in }
        )

        try await Task.sleep(for: .milliseconds(3000))

        #expect(callbackFired.value)
        #expect(!received.items.isEmpty)
    }

    @Test func fallbackActivatesWhenNoRealSamples() async throws {
        let stub = StubMotionProvider()
        let mock = MockMotionProvider(
            realProviderFactory: { stub },
            timeoutInterval: 0.1
        )
        let callbackFired = Flag()
        mock.onFallbackActivated = { callbackFired.value = true }

        let accelReceived = Collector<AccelerometerSample>()
        let dmReceived = Collector<DeviceMotionSample>()
        try mock.startMonitoring(
            accelerometerHandler: { samples in
                accelReceived.append(contentsOf: samples)
            },
            deviceMotionHandler: { samples in
                dmReceived.append(contentsOf: samples)
            }
        )

        try await Task.sleep(for: .milliseconds(3000))

        #expect(callbackFired.value)
        #expect(!accelReceived.items.isEmpty)
        #expect(!dmReceived.items.isEmpty)
    }

    @Test func fallbackSuppressedWhenRealAccelSamplesReceived() async throws {
        let stub = StubMotionProvider()
        let mock = MockMotionProvider(
            realProviderFactory: { stub },
            timeoutInterval: 0.2
        )
        let callbackFired = Flag()
        mock.onFallbackActivated = { callbackFired.value = true }

        try mock.startMonitoring(
            accelerometerHandler: { _ in },
            deviceMotionHandler: { _ in }
        )

        stub.sendAccelSamples([
            AccelerometerSample(timestamp: Date(), x: 0.1, y: 0.0, z: 1.0),
        ])

        try await Task.sleep(for: .milliseconds(500))

        #expect(!callbackFired.value)
    }

    @Test func fallbackSuppressedWhenRealDMSamplesReceived() async throws {
        let stub = StubMotionProvider()
        let mock = MockMotionProvider(
            realProviderFactory: { stub },
            timeoutInterval: 0.2
        )
        let callbackFired = Flag()
        mock.onFallbackActivated = { callbackFired.value = true }

        try mock.startMonitoring(
            accelerometerHandler: { _ in },
            deviceMotionHandler: { _ in }
        )

        stub.sendDMSamples([
            DeviceMotionSample(
                timestamp: Date(), roll: 0.1, pitch: 0.2, yaw: 0.3,
                rotationRateX: 1.0, rotationRateY: 2.0, rotationRateZ: 3.0,
                userAccelerationX: 0.01, userAccelerationY: 0.02, userAccelerationZ: 0.03,
                heading: 90.0
            ),
        ])

        try await Task.sleep(for: .milliseconds(500))

        #expect(!callbackFired.value)
    }

    @Test func fallbackGenerates100SamplesPerBatch() async throws {
        let stub = StubMotionProvider()
        let mock = MockMotionProvider(
            realProviderFactory: { stub },
            timeoutInterval: 0.1
        )

        let accelBatches = Collector<[AccelerometerSample]>()
        let dmBatches = Collector<[DeviceMotionSample]>()
        try mock.startMonitoring(
            accelerometerHandler: { samples in
                accelBatches.append(samples)
            },
            deviceMotionHandler: { samples in
                dmBatches.append(samples)
            }
        )

        try await Task.sleep(for: .milliseconds(3000))

        #expect(!accelBatches.items.isEmpty)
        if let first = accelBatches.items.first {
            #expect(first.count == 100)
        }
        #expect(!dmBatches.items.isEmpty)
        if let first = dmBatches.items.first {
            #expect(first.count == 100)
        }
    }
}
