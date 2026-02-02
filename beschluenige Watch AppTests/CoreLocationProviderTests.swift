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
        try await Task.sleep(for: .milliseconds(200))

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
        try await Task.sleep(for: .milliseconds(200))

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
        try await Task.sleep(for: .milliseconds(200))

        let task = Task<Void, Error> {
            try await withCheckedThrowingContinuation { continuation in
                provider.storeAuthorizationContinuation(continuation)
            }
        }

        try await Task.sleep(for: .milliseconds(100))

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
        try await Task.sleep(for: .milliseconds(200))

        let task = Task<Void, Error> {
            try await withCheckedThrowingContinuation { continuation in
                provider.storeAuthorizationContinuation(continuation)
            }
        }

        try await Task.sleep(for: .milliseconds(100))

        // notDetermined means still waiting -- continuation is re-stored
        provider.handleAuthorizationChange(.notDetermined)

        // Now resolve it
        provider.handleAuthorizationChange(.authorizedWhenInUse)

        // Should complete without error
        try await task.value
    }

    @Test func handleAuthorizationChangeAuthorizedSucceeds() async throws {
        let provider = CoreLocationProvider()
        try await Task.sleep(for: .milliseconds(200))

        let task = Task<Void, Error> {
            try await withCheckedThrowingContinuation { continuation in
                provider.storeAuthorizationContinuation(continuation)
            }
        }

        try await Task.sleep(for: .milliseconds(100))

        provider.handleAuthorizationChange(.authorizedWhenInUse)

        try await task.value
    }

    @Test func handleAuthorizationChangeAuthorizedAlwaysSucceeds() async throws {
        let provider = CoreLocationProvider()
        try await Task.sleep(for: .milliseconds(200))

        let task = Task<Void, Error> {
            try await withCheckedThrowingContinuation { continuation in
                provider.storeAuthorizationContinuation(continuation)
            }
        }

        try await Task.sleep(for: .milliseconds(100))

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
}
