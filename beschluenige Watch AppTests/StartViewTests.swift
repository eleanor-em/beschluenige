import Foundation
import SwiftUI
import Testing
@testable import beschluenige_Watch_App

@MainActor
struct StartViewTests {

    private func makeManager(
        motionShouldThrow: Bool = false
    ) -> WorkoutManager {
        let stub = StubMotionProvider()
        stub.shouldThrow = motionShouldThrow
        return WorkoutManager(
            provider: StubHeartRateProvider(),
            locationProvider: StubLocationProvider(),
            motionProvider: stub
        )
    }

    @Test func bodyRendersWithoutWorkout() {
        let view = StartView(
            workoutManager: makeManager()
        )
        _ = view.body
    }

    @Test func bodyRendersWithWorkout() async throws {
        let manager = makeManager()
        try await manager.startRecording()
        let view = StartView(
            workoutManager: manager
        )
        _ = view.body
        manager.stopRecording()
    }

    @Test func bodyRendersWithErrorMessage() {
        let view = StartView(
            workoutManager: makeManager(),
            initialErrorMessage: "Something went wrong"
        )
        _ = view.body
    }

    @Test func handleStartTappedSetsErrorOnFailure() async {
        let manager = makeManager(motionShouldThrow: true)
        let view = StartView(
            workoutManager: manager
        )
        await view.handleStartTapped()
    }
}
