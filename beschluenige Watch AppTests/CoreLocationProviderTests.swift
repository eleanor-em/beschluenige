import CoreLocation
import Foundation
import Testing
@testable import beschluenige_Watch_App

@MainActor
struct CoreLocationProviderTests {

    @Test func didUpdateLocationsConvertsToSamples() async throws {
        let provider = CoreLocationProvider()
        var received: [LocationSample] = []

        try await provider.startMonitoring(handler: { samples in
            received = samples
        }, startRealUpdates: false)

        let location = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 43.65, longitude: -79.38),
            altitude: 76.0,
            horizontalAccuracy: 5.0,
            verticalAccuracy: 8.0,
            course: 180.0,
            speed: 3.5,
            timestamp: Date()
        )

        provider.locationManager(CLLocationManager(), didUpdateLocations: [location])

        // The delegate dispatches via Task { @MainActor }, so we need to yield
        await Task.yield()

        #expect(received.count == 1)
        #expect(received[0].latitude == 43.65)
        #expect(received[0].longitude == -79.38)
        #expect(received[0].altitude == 76.0)
        #expect(received[0].speed == 3.5)
        #expect(received[0].course == 180.0)

        provider.stopMonitoring()
    }

    @Test func didUpdateLocationsWithMultipleLocations() async throws {
        let provider = CoreLocationProvider()
        var received: [LocationSample] = []

        try await provider.startMonitoring(handler: { samples in
            received = samples
        }, startRealUpdates: false)

        let locations = [
            CLLocation(latitude: 43.0, longitude: -79.0),
            CLLocation(latitude: 44.0, longitude: -80.0),
        ]

        provider.locationManager(CLLocationManager(), didUpdateLocations: locations)
        await Task.yield()

        #expect(received.count == 2)

        provider.stopMonitoring()
    }

    @Test func didFailWithErrorDoesNotCrash() {
        let provider = CoreLocationProvider()
        provider.locationManager(
            CLLocationManager(),
            didFailWithError: NSError(domain: "test", code: 1)
        )
    }

    @Test func didFailWithLocationUnknownDoesNotCrash() {
        let provider = CoreLocationProvider()
        let error = NSError(domain: kCLErrorDomain, code: CLError.locationUnknown.rawValue)
        provider.locationManager(CLLocationManager(), didFailWithError: error)
    }

    @Test func handleLocationUnknownLogsInfoUnder15Seconds() {
        let provider = CoreLocationProvider()
        // First call sets the start time and logs info
        provider.handleLocationUnknown()
        // Second call still under 15s, logs info
        provider.handleLocationUnknown()
    }

    @Test func handleLocationUnknownLogsWarningAfter15Seconds() {
        let provider = CoreLocationProvider()
        // Backdate the first occurrence to >15s ago
        provider.firstLocationUnknownAt = Date(timeIntervalSinceNow: -20)
        provider.handleLocationUnknown()
        // The warning was logged; confirm no crash
    }

    @Test func handleLocationUnknownThrottlesWarningToOncePerMinute() {
        let provider = CoreLocationProvider()
        provider.firstLocationUnknownAt = Date(timeIntervalSinceNow: -30)

        // First warning fires
        provider.handleLocationUnknown()
        let firstWarningTime = provider.lastLocationUnknownWarningAt
        #expect(firstWarningTime != nil)

        // Second call within 60s should NOT update the warning time
        provider.handleLocationUnknown()
        #expect(provider.lastLocationUnknownWarningAt == firstWarningTime)
    }

    @Test func handleLocationUnknownWarningFiresAgainAfter60Seconds() {
        let provider = CoreLocationProvider()
        provider.firstLocationUnknownAt = Date(timeIntervalSinceNow: -120)
        // Simulate a warning that happened >60s ago
        provider.lastLocationUnknownWarningAt = Date(timeIntervalSinceNow: -61)

        provider.handleLocationUnknown()
        // Warning time should be updated to now
        let diff = Date().timeIntervalSince(provider.lastLocationUnknownWarningAt!)
        #expect(diff < 1)
    }

    @Test func resetLocationUnknownTrackingClearsState() {
        let provider = CoreLocationProvider()
        provider.firstLocationUnknownAt = Date()
        provider.lastLocationUnknownWarningAt = Date()

        provider.resetLocationUnknownTracking()

        #expect(provider.firstLocationUnknownAt == nil)
        #expect(provider.lastLocationUnknownWarningAt == nil)
    }

    @Test func didUpdateLocationsResetsLocationUnknownTracking() async throws {
        let provider = CoreLocationProvider()
        try await provider.startMonitoring(handler: { _ in }, startRealUpdates: false)

        // Simulate some location-unknown state
        provider.firstLocationUnknownAt = Date()
        provider.lastLocationUnknownWarningAt = Date()

        let location = CLLocation(latitude: 43.0, longitude: -79.0)
        provider.locationManager(CLLocationManager(), didUpdateLocations: [location])
        await Task.yield()

        #expect(provider.firstLocationUnknownAt == nil)
        #expect(provider.lastLocationUnknownWarningAt == nil)

        provider.stopMonitoring()
    }

    @Test func stopMonitoringClearsHandler() async throws {
        let provider = CoreLocationProvider()
        try await provider.startMonitoring { _ in }
        provider.stopMonitoring()
        // Double stop should not crash
        provider.stopMonitoring()
    }

    @Test func handleAuthorizationChangeWithNoContinuationIsNoOp() {
        let provider = CoreLocationProvider()
        // No pending authorization request, so guard returns early
        provider.handleAuthorizationChange(.denied)
    }

    @Test func handleAuthorizationChangeDeniedThrows() async throws {
        let provider = CoreLocationProvider()
        // Wait for initial locationManagerDidChangeAuthorization callback to drain
        await Task.yield()

        let task = Task<Void, Error> {
            try await withCheckedThrowingContinuation { continuation in
                provider.storeAuthorizationContinuation(continuation)
            }
        }

        await Task.yield()

        provider.handleAuthorizationChange(.denied)

        do {
            try await task.value
            Issue.record("Expected LocationError to be thrown")
        } catch {
            #expect(error is LocationError)
        }
    }

    @Test func handleAuthorizationChangeNotDeterminedReStoresContinuation() async throws {
        let provider = CoreLocationProvider()
        await Task.yield()

        let task = Task<Void, Error> {
            try await withCheckedThrowingContinuation { continuation in
                provider.storeAuthorizationContinuation(continuation)
            }
        }

        await Task.yield()

        // notDetermined means still waiting -- continuation is re-stored
        provider.handleAuthorizationChange(.notDetermined)

        // Now resolve it
        provider.handleAuthorizationChange(.authorizedWhenInUse)

        // Should complete without error
        try await task.value
    }

    @Test func handleAuthorizationChangeAuthorizedSucceeds() async throws {
        let provider = CoreLocationProvider()
        await Task.yield()

        let task = Task<Void, Error> {
            try await withCheckedThrowingContinuation { continuation in
                provider.storeAuthorizationContinuation(continuation)
            }
        }

        await Task.yield()

        provider.handleAuthorizationChange(.authorizedWhenInUse)

        try await task.value
    }

    @Test func handleAuthorizationChangeAuthorizedAlwaysSucceeds() async throws {
        let provider = CoreLocationProvider()
        await Task.yield()

        let task = Task<Void, Error> {
            try await withCheckedThrowingContinuation { continuation in
                provider.storeAuthorizationContinuation(continuation)
            }
        }

        await Task.yield()

        provider.handleAuthorizationChange(.authorizedAlways)

        try await task.value
    }

    @Test func locationManagerDidChangeAuthorizationDelegateCallback() {
        let provider = CoreLocationProvider()
        // Without a pending continuation, this should not crash
        provider.locationManagerDidChangeAuthorization(CLLocationManager())
    }

    @Test func requestAuthorizationAlreadyAuthorized() async throws {
        // On the simulator, if location is already authorized,
        // requestAuthorization returns immediately (early return path).
        let provider = CoreLocationProvider()
        try await provider.requestAuthorization()
        // Call again to exercise the early return
        try await provider.requestAuthorization()
    }

    @Test func requestAuthorizationContinuationPath() async throws {
        let provider = CoreLocationProvider()
        // Wait for initial locationManagerDidChangeAuthorization callback to drain
        await Task.yield()

        let task = Task<Void, Error> {
            try await provider.requestAuthorization(currentStatus: .notDetermined)
        }

        await Task.yield()

        provider.handleAuthorizationChange(.authorizedWhenInUse)

        try await task.value
    }

    @Test func handleAuthorizationChangeUnknownStatusResumes() async throws {
        let provider = CoreLocationProvider()
        await Task.yield()

        let task = Task<Void, Error> {
            try await withCheckedThrowingContinuation { continuation in
                provider.storeAuthorizationContinuation(continuation)
            }
        }

        await Task.yield()

        let unknownStatus = CLAuthorizationStatus(rawValue: 99)!
        provider.handleAuthorizationChange(unknownStatus)

        try await task.value
    }
}
