import Foundation
@testable import beschluenige_Watch_App

final class StubHeartRateProvider: HeartRateProvider, @unchecked Sendable {
    var authorizationRequested = false
    var monitoringStarted = false
    var monitoringStopped = false
    private var handler: (@Sendable ([HeartRateSample]) -> Void)?

    func requestAuthorization() async throws {
        authorizationRequested = true
    }

    func startMonitoring(
        handler: @escaping @Sendable ([HeartRateSample]) -> Void
    ) async throws {
        self.handler = handler
        monitoringStarted = true
    }

    func stopMonitoring() {
        monitoringStopped = true
        handler = nil
    }

    func sendSamples(_ samples: [HeartRateSample]) {
        handler?(samples)
    }
}

final class StubLocationProvider: LocationProvider, @unchecked Sendable {
    var authorizationRequested = false
    var monitoringStarted = false
    var monitoringStopped = false
    private var handler: (@Sendable ([LocationSample]) -> Void)?

    func requestAuthorization() async throws {
        authorizationRequested = true
    }

    func startMonitoring(
        handler: @escaping @Sendable ([LocationSample]) -> Void
    ) async throws {
        self.handler = handler
        monitoringStarted = true
    }

    func stopMonitoring() {
        monitoringStopped = true
        handler = nil
    }

    func sendSamples(_ samples: [LocationSample]) {
        handler?(samples)
    }
}

final class StubMotionProvider: MotionProvider, @unchecked Sendable {
    var shouldThrow = false
    var monitoringStarted = false
    var monitoringStopped = false
    private var handler: (@Sendable ([AccelerometerSample]) -> Void)?

    func startMonitoring(
        handler: @escaping @Sendable ([AccelerometerSample]) -> Void
    ) throws {
        if shouldThrow {
            throw MotionError.accelerometerUnavailable
        }
        self.handler = handler
        monitoringStarted = true
    }

    func stopMonitoring() {
        monitoringStopped = true
        handler = nil
    }

    func sendSamples(_ samples: [AccelerometerSample]) {
        handler?(samples)
    }
}
