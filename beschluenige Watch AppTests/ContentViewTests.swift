import Foundation
import Testing
@testable import beschluenige_Watch_App

@MainActor
struct ContentViewTests {

    private func makeManager(
        shouldThrowOnAuthorization: Bool = false
    ) -> WorkoutManager {
        let stub = StubHeartRateProvider()
        stub.shouldThrowOnAuthorization = shouldThrowOnAuthorization
        return WorkoutManager(
            provider: stub,
            locationProvider: StubLocationProvider(),
            motionProvider: StubMotionProvider()
        )
    }

    @Test func bodyShowsStartViewByDefault() {
        _ = ContentView(workoutManager: makeManager())
    }

    @Test func bodyShowsWorkoutViewWhenRecording() async throws {
        let manager = makeManager()
        try await manager.startRecording()
        _ = ContentView(workoutManager: manager)
        manager.stopRecording()
    }

    @Test func workoutViewRendersWithHeartRate() async throws {
        let hrStub = StubHeartRateProvider()
        let manager = WorkoutManager(
            provider: hrStub,
            locationProvider: StubLocationProvider(),
            motionProvider: StubMotionProvider()
        )
        try await manager.startRecording()
        hrStub.sendSamples([HeartRateSample(timestamp: Date(), beatsPerMinute: 120)])
        await Task.yield()

        _ = WorkoutView(workoutManager: manager)
        manager.stopRecording()
    }

    @Test func authorizeProvidersSucceeds() async {
        let view = ContentView(workoutManager: makeManager())
        await view.authorizeProviders()
    }

    @Test func authorizeProvidersHandlesError() async {
        let view = ContentView(
            workoutManager: makeManager(shouldThrowOnAuthorization: true)
        )
        await view.authorizeProviders()
    }
}
