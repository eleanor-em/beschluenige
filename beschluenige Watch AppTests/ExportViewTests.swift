import Foundation
import Testing
@testable import beschluenige_Watch_App

@MainActor
struct ExportViewTests {

    private func makeManager(withSession: Bool = true) -> WorkoutManager {
        let manager = WorkoutManager(
            provider: StubHeartRateProvider(),
            locationProvider: StubLocationProvider(),
            motionProvider: StubMotionProvider()
        )
        if withSession {
            manager.currentSession = RecordingSession(startDate: Date())
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
        let url = URL(fileURLWithPath: "/tmp/test.csv")
        let view = ExportView(
            workoutManager: makeManager(),
            initialTransferState: .savedLocally(url)
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
        action.sendViaPhone = { _ in true }

        let view = ExportView(
            workoutManager: makeManager(),
            exportAction: action
        )

        let session = RecordingSession(startDate: Date())
        view.sendToPhone(session: session)
    }

    @Test func sendToPhoneSetsLocalFallback() throws {
        var action = ExportAction()
        action.sendViaPhone = { _ in false }

        let view = ExportView(
            workoutManager: makeManager(),
            exportAction: action
        )

        let session = RecordingSession(startDate: Date())
        view.sendToPhone(session: session)
    }

    @Test func sendToPhoneSetsFailed() {
        var action = ExportAction()
        action.sendViaPhone = { _ in false }
        action.saveLocally = { _ in
            throw NSError(domain: "test", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "disk full",
            ])
        }

        let view = ExportView(
            workoutManager: makeManager(),
            exportAction: action
        )

        let session = RecordingSession(startDate: Date())
        view.sendToPhone(session: session)
    }

    // MARK: - handleSendToPhone

    @Test func handleSendToPhoneWithSession() {
        var action = ExportAction()
        action.sendViaPhone = { _ in true }

        let view = ExportView(
            workoutManager: makeManager(),
            exportAction: action
        )
        view.handleSendToPhone()
    }

    @Test func handleSendToPhoneWithoutSession() {
        let view = ExportView(
            workoutManager: makeManager(withSession: false)
        )
        view.handleSendToPhone()
    }

}
