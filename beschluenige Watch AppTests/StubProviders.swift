import Foundation
@testable import beschluenige_Watch_App

final class StubHeartRateProvider: HeartRateProvider, @unchecked Sendable {
    var authorizationRequested = false
    var monitoringStarted = false
    var monitoringStopped = false
    var shouldThrowOnAuthorization = false
    private var handler: (@Sendable ([HeartRateSample]) -> Void)?

    func requestAuthorization() async throws {
        if shouldThrowOnAuthorization {
            throw StubProviderError.authorizationFailed
        }
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

enum StubProviderError: Error {
    case authorizationFailed
}

final class StubMotionProvider: MotionProvider, @unchecked Sendable {
    var shouldThrow = false
    var monitoringStarted = false
    var monitoringStopped = false
    private var accelHandler: (@Sendable ([AccelerometerSample]) -> Void)?
    private var dmHandler: (@Sendable ([DeviceMotionSample]) -> Void)?

    func startMonitoring(
        accelerometerHandler: @escaping @Sendable ([AccelerometerSample]) -> Void,
        deviceMotionHandler: @escaping @Sendable ([DeviceMotionSample]) -> Void
    ) throws {
        if shouldThrow {
            throw MotionError.accelerometerUnavailable
        }
        self.accelHandler = accelerometerHandler
        self.dmHandler = deviceMotionHandler
        monitoringStarted = true
    }

    func stopMonitoring() {
        monitoringStopped = true
        accelHandler = nil
        dmHandler = nil
    }

    func sendAccelSamples(_ samples: [AccelerometerSample]) {
        accelHandler?(samples)
    }

    func sendDMSamples(_ samples: [DeviceMotionSample]) {
        dmHandler?(samples)
    }
}
