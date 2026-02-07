import Foundation
import Testing
@testable import beschluenige_Watch_App

@MainActor
struct ExportViewTests {

    private func makeManager(
        withWorkout: Bool = true,
        startDate: Date = Date()
    ) -> WorkoutManager {
        let manager = WorkoutManager(
            provider: StubHeartRateProvider(),
            locationProvider: StubLocationProvider(),
            motionProvider: StubMotionProvider()
        )
        if withWorkout {
            manager.currentWorkout = Workout(startDate: startDate)
        }
        return manager
    }

    // MARK: - Body rendering per transfer state

    @Test func bodyRendersIdleWithWorkout() {
        let view = ExportView(workoutManager: makeManager())
        _ = view.body
    }

    @Test func bodyRendersWithoutWorkout() {
        let view = ExportView(workoutManager: makeManager(withWorkout: false))
        _ = view.body
    }

    @Test func bodyRendersSending() {
        let view = ExportView(
            workoutManager: makeManager(),
            initialTransferState: .sending
        )
        _ = view.body
    }

    @Test func bodyRendersQueued() {
        let view = ExportView(
            workoutManager: makeManager(),
            initialTransferState: .queued
        )
        _ = view.body
    }

    @Test func bodyRendersSavedLocally() {
        let urls = [URL(fileURLWithPath: "/tmp/test.cbor")]
        let view = ExportView(
            workoutManager: makeManager(),
            initialTransferState: .savedLocally(urls)
        )
        _ = view.body
    }

    @Test func bodyRendersFailed() {
        let view = ExportView(
            workoutManager: makeManager(),
            initialTransferState: .failed("disk full")
        )
        _ = view.body
    }

    // MARK: - sendToPhone

    @Test func sendToPhoneSetsQueuedOnSuccess() {
        var action = ExportAction()
        action.sendChunksViaPhone = { _, _, _, _ in Progress() }
        action.finalizeWorkout = { workout in
            workout.heartRateSamples = [
                HeartRateSample(timestamp: Date(), beatsPerMinute: 100),
            ]
            return try workout.finalizeChunks()
        }

        let manager = makeManager(startDate: Date(timeIntervalSince1970: 3000000000))
        let view = ExportView(
            workoutManager: manager,
            exportAction: action
        )

        view.sendToPhone()

        // Clean up chunk files
        if let workout = manager.currentWorkout {
            for url in workout.chunkURLs {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    @Test func sendToPhoneSetsLocalFallback() {
        var action = ExportAction()
        action.sendChunksViaPhone = { _, _, _, _ in nil }
        action.finalizeWorkout = { workout in
            workout.heartRateSamples = [
                HeartRateSample(timestamp: Date(), beatsPerMinute: 100),
            ]
            return try workout.finalizeChunks()
        }

        let manager = makeManager(startDate: Date(timeIntervalSince1970: 3000000001))
        let view = ExportView(
            workoutManager: manager,
            exportAction: action
        )

        view.sendToPhone()

        // Clean up chunk files
        if let workout = manager.currentWorkout {
            for url in workout.chunkURLs {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    @Test func sendToPhoneSetsFailed() {
        var action = ExportAction()
        action.finalizeWorkout = { _ in
            throw NSError(domain: "test", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "disk full",
            ])
        }

        let view = ExportView(
            workoutManager: makeManager(),
            exportAction: action
        )

        view.sendToPhone()
    }

    // MARK: - handleSendToPhone

    @Test func handleSendToPhoneWithWorkout() {
        var action = ExportAction()
        action.sendChunksViaPhone = { _, _, _, _ in Progress() }
        action.finalizeWorkout = { workout in
            workout.heartRateSamples = [
                HeartRateSample(timestamp: Date(), beatsPerMinute: 100),
            ]
            return try workout.finalizeChunks()
        }

        let manager = makeManager(startDate: Date(timeIntervalSince1970: 3000000002))
        let view = ExportView(
            workoutManager: manager,
            exportAction: action
        )
        view.handleSendToPhone()

        // Clean up chunk files
        if let workout = manager.currentWorkout {
            for url in workout.chunkURLs {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    @Test func handleSendToPhoneWithoutWorkout() {
        let view = ExportView(
            workoutManager: makeManager(withWorkout: false)
        )
        view.handleSendToPhone()
    }

}
