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

    @Test func bodyRendersWithoutSession() {
        let view = StartView(
            workoutManager: makeManager(),
            showExport: .constant(false)
        )
        _ = view.body
    }

    @Test func bodyRendersWithSession() async throws {
        let manager = makeManager()
        try await manager.startRecording()
        let view = StartView(
            workoutManager: manager,
            showExport: .constant(false)
        )
        _ = view.body
        manager.stopRecording()
    }

    @Test func bodyRendersWithErrorMessage() {
        let view = StartView(
            workoutManager: makeManager(),
            showExport: .constant(false),
            initialErrorMessage: "Something went wrong"
        )
        _ = view.body
    }

    @Test func handleStartTappedSetsErrorOnFailure() async {
        let manager = makeManager(motionShouldThrow: true)
        let view = StartView(
            workoutManager: manager,
            showExport: .constant(false)
        )
        await view.handleStartTapped()
    }
}
