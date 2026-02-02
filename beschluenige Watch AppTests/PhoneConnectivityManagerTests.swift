import Foundation
import Testing
import WatchConnectivity
@testable import beschluenige_Watch_App

@MainActor
struct PhoneConnectivityManagerTests {

    @Test func sendSessionReturnsFalseWhenNotActivated() {
        let session = RecordingSession(startDate: Date())
        let result = PhoneConnectivityManager.shared.sendSession(session)
        #expect(!result)
    }

    @Test func prepareFileForTransferWritesCsv() throws {
        let t = Date(timeIntervalSince1970: 1706812345)
        var session = RecordingSession(startDate: t)
        session.samples = [
            HeartRateSample(timestamp: t, beatsPerMinute: 100),
        ]

        let (url, metadata) = try PhoneConnectivityManager.shared
            .prepareFileForTransfer(session)

        let content = try String(contentsOf: url, encoding: .utf8)
        #expect(content.contains("H,"))
        #expect((metadata["fileName"] as? String)?.hasPrefix("hr_") == true)
        #expect(metadata["sampleCount"] as? Int == 1)
        #expect(metadata["startDate"] as? TimeInterval == t.timeIntervalSince1970)

        try FileManager.default.removeItem(at: url)
    }

    @Test func prepareFileForTransferEmptySession() throws {
        let session = RecordingSession(startDate: Date())

        let (url, metadata) = try PhoneConnectivityManager.shared
            .prepareFileForTransfer(session)

        let content = try String(contentsOf: url, encoding: .utf8)
        #expect(content.hasPrefix("type,timestamp,"))
        #expect(metadata["sampleCount"] as? Int == 0)

        try FileManager.default.removeItem(at: url)
    }

    @Test func activateReturnsEarlyOnSimulator() {
        // WCSession.isSupported() returns false on simulator
        PhoneConnectivityManager.shared.activate()
    }

    @Test func delegateHandlesActivationWithoutError() {
        PhoneConnectivityManager.shared.session(
            WCSession.default,
            activationDidCompleteWith: .activated,
            error: nil
        )
    }

    @Test func delegateHandlesActivationWithError() {
        PhoneConnectivityManager.shared.session(
            WCSession.default,
            activationDidCompleteWith: .notActivated,
            error: NSError(domain: "test", code: 1)
        )
    }
}
