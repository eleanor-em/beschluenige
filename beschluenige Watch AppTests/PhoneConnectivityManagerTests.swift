import Foundation
import Testing
import WatchConnectivity
@testable import beschluenige_Watch_App

@MainActor
struct PhoneConnectivityManagerTests {

    @Test func sendSessionReturnsFalseWhenNotActivated() {
        let stub = StubConnectivitySession()
        stub.activationState = .notActivated
        let manager = PhoneConnectivityManager(session: stub)

        let session = RecordingSession(startDate: Date())
        let result = manager.sendSession(session)
        #expect(!result)
    }

    @Test func sendSessionReturnsTrueWhenActivated() throws {
        let stub = StubConnectivitySession()
        stub.activationState = .activated
        let manager = PhoneConnectivityManager(session: stub)

        let session = RecordingSession(startDate: Date())
        let result = manager.sendSession(session)

        #expect(result)
        #expect(stub.sentFiles.count == 1)

        // Clean up the temp file so it does not interfere with other tests
        let (url, _) = try manager.prepareFileForTransfer(session)
        try? FileManager.default.removeItem(at: url)
    }

    @Test func sendSessionReturnsFalseWhenPrepareThrows() {
        let stub = StubConnectivitySession()
        stub.activationState = .activated
        let manager = PhoneConnectivityManager(session: stub)

        // Use a fixed date so the filename is unique and not shared with other tests
        let fixedDate = Date(timeIntervalSince1970: 1000000000)
        let session = RecordingSession(startDate: fixedDate)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let fileName = "TEST_hr_\(formatter.string(from: session.startDate)).csv"

        let tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName)
        // Remove any leftover file at this path
        try? FileManager.default.removeItem(at: tempPath)

        let blockingDir = tempPath

        // Create a directory where the file would go, causing .write to fail
        try? FileManager.default.createDirectory(
            at: blockingDir,
            withIntermediateDirectories: false
        )

        let result = manager.sendSession(session)

        try? FileManager.default.removeItem(at: blockingDir)
        #expect(!result)
    }

    @Test func activateCallsSessionActivate() {
        let stub = StubConnectivitySession()
        stub.isDeviceSupported = true
        let manager = PhoneConnectivityManager(session: stub)

        manager.activate()

        #expect(stub.activateCalled)
        #expect(stub.delegateSet)
    }

    @Test func activateReturnsEarlyWhenNotSupported() {
        let stub = StubConnectivitySession()
        stub.isDeviceSupported = false
        let manager = PhoneConnectivityManager(session: stub)

        manager.activate()

        #expect(!stub.activateCalled)
        #expect(!stub.delegateSet)
    }

    @Test func prepareFileForTransferWritesCsv() throws {
        let stub = StubConnectivitySession()
        let manager = PhoneConnectivityManager(session: stub)

        let t = Date(timeIntervalSince1970: 1706812345)
        var session = RecordingSession(startDate: t)
        session.heartRateSamples = [
            HeartRateSample(timestamp: t, beatsPerMinute: 100),
        ]

        let (url, metadata) = try manager
            .prepareFileForTransfer(session)

        let content = try String(contentsOf: url, encoding: .utf8)
        #expect(content.contains("H,"))
        #expect((metadata["fileName"] as? String)?.hasPrefix("TEST_hr_") == true)
        #expect(metadata["sampleCount"] as? Int == 1)
        #expect(metadata["startDate"] as? TimeInterval == t.timeIntervalSince1970)

        try FileManager.default.removeItem(at: url)
    }

    @Test func prepareFileForTransferEmptySession() throws {
        let stub = StubConnectivitySession()
        let manager = PhoneConnectivityManager(session: stub)

        let session = RecordingSession(startDate: Date())

        let (url, metadata) = try manager
            .prepareFileForTransfer(session)

        let content = try String(contentsOf: url, encoding: .utf8)
        #expect(content.hasPrefix("type,timestamp,"))
        #expect(metadata["sampleCount"] as? Int == 0)

        try FileManager.default.removeItem(at: url)
    }

    @Test func delegateHandlesActivationWithoutError() {
        let stub = StubConnectivitySession()
        let manager = PhoneConnectivityManager(session: stub)

        manager.session(
            WCSession.default,
            activationDidCompleteWith: .activated,
            error: nil
        )
    }

    @Test func delegateHandlesActivationWithError() {
        let stub = StubConnectivitySession()
        let manager = PhoneConnectivityManager(session: stub)

        manager.session(
            WCSession.default,
            activationDidCompleteWith: .notActivated,
            error: NSError(domain: "test", code: 1)
        )
    }
}
