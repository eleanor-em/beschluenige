import CoreLocation
import Foundation

final class CoreLocationProvider: NSObject, LocationProvider, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private var sampleHandler: (@Sendable ([LocationSample]) -> Void)?
    private var authorizationContinuation: CheckedContinuation<Void, Error>?
    private let logger = AppLogger(category: "CoreLocationGPS")
    var firstLocationUnknownAt: Date?
    var lastLocationUnknownWarningAt: Date?

    override init() {
        super.init()
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.delegate = self
    }

    func requestAuthorization() async throws {
        let status = locationManager.authorizationStatus
        try await requestAuthorization(currentStatus: status)
    }

    func requestAuthorization(currentStatus: CLAuthorizationStatus) async throws {
        if currentStatus == .authorizedWhenInUse || currentStatus == .authorizedAlways {
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
            preconditionExcludeCoverage(
                isRunningTests,
                "startRealUpdates: false is only allowed in test cases"
            )
        }
        sampleHandler = handler
        if startRealUpdates {
            locationManager.startUpdatingLocation()
        }
    }

    func stopMonitoring() {
        locationManager.stopUpdatingLocation()
        sampleHandler = nil
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
            self?.resetLocationUnknownTracking()
            self?.sampleHandler?(samples)
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        // kCLErrorLocationUnknown is transient -- GPS hasn't acquired a fix yet.
        // It resolves on its own once the hardware warms up.
        if (error as? CLError)?.code == .locationUnknown {
            Task { @MainActor [weak self] in
                self?.handleLocationUnknown()
            }
            return
        }
        logger.error("Location error: \(error.localizedDescription)")
    }

    func handleLocationUnknown() {
        let now = Date()
        if firstLocationUnknownAt == nil {
            firstLocationUnknownAt = now
        }
        let elapsed = now.timeIntervalSince(firstLocationUnknownAt!)
        if elapsed > 15,
           lastLocationUnknownWarningAt.map({ now.timeIntervalSince($0) > 60 }) ?? true {
            lastLocationUnknownWarningAt = now
            logger.warning(
                "Location still unavailable after \(Int(elapsed))s"
            )
        } else {
            logger.info("Location not yet available (transient)")
        }
    }

    func resetLocationUnknownTracking() {
        firstLocationUnknownAt = nil
        lastLocationUnknownWarningAt = nil
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        logger.info("Location authorization changed: \(status.description)")
        Task { @MainActor [weak self] in
            self?.handleAuthorizationChange(status)
        }
    }

    func storeAuthorizationContinuation(_ continuation: CheckedContinuation<Void, Error>) {
        preconditionExcludeCoverage(
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
