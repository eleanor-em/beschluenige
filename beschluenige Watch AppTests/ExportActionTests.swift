import Foundation
import Testing
@testable import beschluenige_Watch_App

struct ExportActionTests {

    @Test func executeReturnsSentOnSuccess() {
        var action = ExportAction()
        action.sendViaPhone = { _ in true }

        let result = action.execute(session: RecordingSession(startDate: Date()))
        if case .sent = result {
            // pass
        } else {
            Issue.record("Expected .sent, got \(result)")
        }
    }

    @Test func executeReturnsSavedLocallyOnTransferFailure() throws {
        var action = ExportAction()
        action.sendViaPhone = { _ in false }

        let session = RecordingSession(startDate: Date())
        let result = action.execute(session: session)

        if case .savedLocally(let url) = result {
            #expect(FileManager.default.fileExists(atPath: url.path))
            try FileManager.default.removeItem(at: url)
        } else {
            Issue.record("Expected .savedLocally, got \(result)")
        }
    }

    @Test func executeReturnsFailedWhenSaveThrows() {
        var action = ExportAction()
        action.sendViaPhone = { _ in false }
        action.saveLocally = { _ in
            throw NSError(domain: "test", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "disk full",
            ])
        }

        let result = action.execute(session: RecordingSession(startDate: Date()))
        if case .failed(let message) = result {
            #expect(message == "disk full")
        } else {
            Issue.record("Expected .failed, got \(result)")
        }
    }

    @Test func executeUsesDefaultPhoneConnectivityOnSimulator() {
        // Default sendViaPhone uses PhoneConnectivityManager.shared
        // On simulator, WCSession is not activated, so this falls back to local save
        let action = ExportAction()
        let session = RecordingSession(startDate: Date())
        let result = action.execute(session: session)

        // Should not be .sent (WCSession not activated on simulator)
        if case .sent = result {
            Issue.record("Expected fallback, not .sent on simulator")
        }
    }
}
