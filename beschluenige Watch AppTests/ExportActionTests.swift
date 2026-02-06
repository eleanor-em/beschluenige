import Foundation
import Testing
@testable import beschluenige_Watch_App

struct ExportActionTests {

    @Test func executeReturnsSentOnSuccess() {
        var action = ExportAction()
        action.sendChunksViaPhone = { _, _, _, _ in true }
        action.finalizeSession = { session in
            session.heartRateSamples = [
                HeartRateSample(timestamp: Date(), beatsPerMinute: 100),
            ]
            return try session.finalizeChunks()
        }

        var session = RecordingSession(startDate: Date(timeIntervalSince1970: 2000000000))
        let result = action.execute(session: &session)
        if case .sent = result {
            // pass
        } else {
            Issue.record("Expected .sent, got \(result)")
        }

        // Clean up
        for url in session.chunkURLs {
            try? FileManager.default.removeItem(at: url)
        }
    }

    @Test func executeReturnsSavedLocallyOnTransferFailure() throws {
        var action = ExportAction()
        action.sendChunksViaPhone = { _, _, _, _ in false }
        action.finalizeSession = { session in
            session.heartRateSamples = [
                HeartRateSample(timestamp: Date(), beatsPerMinute: 100),
            ]
            return try session.finalizeChunks()
        }

        var session = RecordingSession(startDate: Date(timeIntervalSince1970: 2000000001))
        let result = action.execute(session: &session)

        if case .savedLocally(let urls) = result {
            #expect(!urls.isEmpty)
            for url in urls {
                #expect(FileManager.default.fileExists(atPath: url.path))
                try FileManager.default.removeItem(at: url)
            }
        } else {
            Issue.record("Expected .savedLocally, got \(result)")
        }
    }

    @Test func executeReturnsFailedWhenFinalizeThrows() {
        var action = ExportAction()
        action.finalizeSession = { _ in
            throw NSError(domain: "test", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "disk full",
            ])
        }

        var session = RecordingSession(startDate: Date())
        let result = action.execute(session: &session)
        if case .failed(let message) = result {
            #expect(message == "disk full")
        } else {
            Issue.record("Expected .failed, got \(result)")
        }
    }

    @Test func executeReturnsFailedWhenNoChunks() {
        var action = ExportAction()
        action.finalizeSession = { _ in [] }

        var session = RecordingSession(startDate: Date())
        let result = action.execute(session: &session)
        if case .failed(let message) = result {
            #expect(message == "No data to export")
        } else {
            Issue.record("Expected .failed, got \(result)")
        }
    }

    @Test func executeCallsRegisterSessionAfterFinalize() {
        var registered = false
        var action = ExportAction()
        action.sendChunksViaPhone = { _, _, _, _ in true }
        action.finalizeSession = { session in
            session.heartRateSamples = [
                HeartRateSample(timestamp: Date(), beatsPerMinute: 100),
            ]
            return try session.finalizeChunks()
        }
        action.registerSession = { _, _, _, _ in registered = true }

        var session = RecordingSession(startDate: Date(timeIntervalSince1970: 2000000010))
        _ = action.execute(session: &session)

        #expect(registered)

        for url in session.chunkURLs {
            try? FileManager.default.removeItem(at: url)
        }
    }

    @Test func executeCallsMarkTransferredOnSuccess() {
        var marked = false
        var action = ExportAction()
        action.sendChunksViaPhone = { _, _, _, _ in true }
        action.finalizeSession = { session in
            session.heartRateSamples = [
                HeartRateSample(timestamp: Date(), beatsPerMinute: 100),
            ]
            return try session.finalizeChunks()
        }
        action.markTransferred = { _ in marked = true }

        var session = RecordingSession(startDate: Date(timeIntervalSince1970: 2000000011))
        _ = action.execute(session: &session)

        #expect(marked)

        for url in session.chunkURLs {
            try? FileManager.default.removeItem(at: url)
        }
    }

    @Test func executeDoesNotCallMarkTransferredOnFailure() {
        var marked = false
        var action = ExportAction()
        action.sendChunksViaPhone = { _, _, _, _ in false }
        action.finalizeSession = { session in
            session.heartRateSamples = [
                HeartRateSample(timestamp: Date(), beatsPerMinute: 100),
            ]
            return try session.finalizeChunks()
        }
        action.markTransferred = { _ in marked = true }

        var session = RecordingSession(startDate: Date(timeIntervalSince1970: 2000000012))
        _ = action.execute(session: &session)

        #expect(!marked)

        for url in session.chunkURLs {
            try? FileManager.default.removeItem(at: url)
        }
    }

    @Test func executeDoesNotCallRegisterWhenFinalizeThrows() {
        var registered = false
        var action = ExportAction()
        action.finalizeSession = { _ in
            throw NSError(domain: "test", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "disk full",
            ])
        }
        action.registerSession = { _, _, _, _ in registered = true }

        var session = RecordingSession(startDate: Date())
        _ = action.execute(session: &session)

        #expect(!registered)
    }

    @Test func executeUsesDefaultPhoneConnectivityOnSimulator() throws {
        // Default sendChunksViaPhone uses PhoneConnectivityManager.shared
        // On simulator, WCSession is not activated, so this falls back to local save
        #if !targetEnvironment(simulator)
        // On a real watch WCSession may be activated, so .sent is valid
        return
        #else
        var action = ExportAction()
        action.finalizeSession = { session in
            session.heartRateSamples = [
                HeartRateSample(timestamp: Date(), beatsPerMinute: 100),
            ]
            return try session.finalizeChunks()
        }
        var session = RecordingSession(startDate: Date(timeIntervalSince1970: 2000000002))
        let result = action.execute(session: &session)

        // Should not be .sent (WCSession not activated on simulator)
        if case .sent = result {
            Issue.record("Expected fallback, not .sent on simulator")
        }

        // Clean up
        for url in session.chunkURLs {
            try? FileManager.default.removeItem(at: url)
        }
        #endif
    }
}
