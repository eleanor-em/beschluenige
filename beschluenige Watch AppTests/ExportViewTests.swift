import Foundation
import Testing
@testable import beschluenige_Watch_App

@MainActor
struct ExportViewTests {

    private func makeManager(
        withSession: Bool = true,
        startDate: Date = Date()
    ) -> WorkoutManager {
        let manager = WorkoutManager(
            provider: StubHeartRateProvider(),
            locationProvider: StubLocationProvider(),
            motionProvider: StubMotionProvider()
        )
        if withSession {
            manager.currentSession = RecordingSession(startDate: startDate)
        }
        return manager
    }

    // MARK: - Body rendering per transfer state

    @Test func bodyRendersIdleWithSession() {
        let view = ExportView(workoutManager: makeManager())
        _ = view.body
    }

    @Test func bodyRendersWithoutSession() {
        let view = ExportView(workoutManager: makeManager(withSession: false))
        _ = view.body
    }

    @Test func bodyRendersSending() {
        let view = ExportView(
            workoutManager: makeManager(),
            initialTransferState: .sending
        )
        _ = view.body
    }

    @Test func bodyRendersSent() {
        let view = ExportView(
            workoutManager: makeManager(),
            initialTransferState: .sent
        )
        _ = view.body
    }

    @Test func bodyRendersSavedLocally() {
        let urls = [URL(fileURLWithPath: "/tmp/test.csv")]
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

    @Test func sendToPhoneSetsSentOnSuccess() {
        var action = ExportAction()
        action.sendChunksViaPhone = { _, _, _, _ in true }
        action.finalizeSession = { session in
            session.heartRateSamples = [
                HeartRateSample(timestamp: Date(), beatsPerMinute: 100),
            ]
            return try session.finalizeChunks()
        }

        let manager = makeManager(startDate: Date(timeIntervalSince1970: 3000000000))
        let view = ExportView(
            workoutManager: manager,
            exportAction: action
        )

        view.sendToPhone()

        // Clean up chunk files
        if let session = manager.currentSession {
            for url in session.chunkURLs {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    @Test func sendToPhoneSetsLocalFallback() {
        var action = ExportAction()
        action.sendChunksViaPhone = { _, _, _, _ in false }
        action.finalizeSession = { session in
            session.heartRateSamples = [
                HeartRateSample(timestamp: Date(), beatsPerMinute: 100),
            ]
            return try session.finalizeChunks()
        }

        let manager = makeManager(startDate: Date(timeIntervalSince1970: 3000000001))
        let view = ExportView(
            workoutManager: manager,
            exportAction: action
        )

        view.sendToPhone()

        // Clean up chunk files
        if let session = manager.currentSession {
            for url in session.chunkURLs {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    @Test func sendToPhoneSetsFailed() {
        var action = ExportAction()
        action.finalizeSession = { _ in
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

    @Test func handleSendToPhoneWithSession() {
        var action = ExportAction()
        action.sendChunksViaPhone = { _, _, _, _ in true }
        action.finalizeSession = { session in
            session.heartRateSamples = [
                HeartRateSample(timestamp: Date(), beatsPerMinute: 100),
            ]
            return try session.finalizeChunks()
        }

        let manager = makeManager(startDate: Date(timeIntervalSince1970: 3000000002))
        let view = ExportView(
            workoutManager: manager,
            exportAction: action
        )
        view.handleSendToPhone()

        // Clean up chunk files
        if let session = manager.currentSession {
            for url in session.chunkURLs {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    @Test func handleSendToPhoneWithoutSession() {
        let view = ExportView(
            workoutManager: makeManager(withSession: false)
        )
        view.handleSendToPhone()
    }

}
