import CoreLocation
import Foundation
import os

final class CoreLocationProvider: NSObject, LocationProvider, CLLocationManagerDelegate,
    @unchecked Sendable {
    private let locationManager = CLLocationManager()
    private var sampleHandler: (@Sendable ([LocationSample]) -> Void)?
    private var authorizationContinuation: CheckedContinuation<Void, Error>?
    private let logger = Logger(
        subsystem: "net.lnor.beschluenige.watchkitapp",
        category: "CoreLocationGPS"
    )

    override init() {
        super.init()
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.delegate = self
    }

    func requestAuthorization() async throws {
        let status = locationManager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            return
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            authorizationContinuation = continuation
            locationManager.requestWhenInUseAuthorization()
        }
    }

    func startMonitoring(
        handler: @escaping @Sendable ([LocationSample]) -> Void
    ) async throws {
        try await startMonitoring(handler: handler, startRealUpdates: true)
    }

    func startMonitoring(
        handler: @escaping @Sendable ([LocationSample]) -> Void,
        startRealUpdates: Bool
    ) async throws {
        if !startRealUpdates {
            precondition(
                ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil,
                "startRealUpdates: false is only allowed in test cases"
            )
        }
        sampleHandler = handler
        if startRealUpdates {
            locationManager.startUpdatingLocation()
            logger.info("Started GPS location updates")
        }
    }

    func stopMonitoring() {
        locationManager.stopUpdatingLocation()
        sampleHandler = nil
        logger.info("Stopped GPS location updates")
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        let samples = locations.map { location in
            LocationSample(
                timestamp: location.timestamp,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                altitude: location.altitude,
                horizontalAccuracy: location.horizontalAccuracy,
                verticalAccuracy: location.verticalAccuracy,
                speed: location.speed,
                course: location.course
            )
        }
        Task { @MainActor [weak self] in
            self?.sampleHandler?(samples)
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        logger.error("Location error: \(error.localizedDescription)")
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        logger.info("Location authorization changed: \(status.rawValue)")
        Task { @MainActor [weak self] in
            self?.handleAuthorizationChange(status)
        }
    }

    func storeAuthorizationContinuation(_ continuation: CheckedContinuation<Void, Error>) {
        precondition(
            ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil,
            "storeAuthorizationContinuation is only allowed in test cases"
        )
        authorizationContinuation = continuation
    }

    func handleAuthorizationChange(_ status: CLAuthorizationStatus) {
        guard let continuation = authorizationContinuation else { return }
        authorizationContinuation = nil

        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            continuation.resume()
        case .denied, .restricted:
            continuation.resume(throwing: LocationError.authorizationDenied)
        case .notDetermined:
            // Still waiting for user to respond to the permission dialog
            authorizationContinuation = continuation
        @unknown default:
            continuation.resume()
        }
    }
}

enum LocationError: Error {
    case authorizationDenied
}
