import Foundation
import Testing
import WatchConnectivity
@testable import beschluenige

@Suite(.serialized)
@MainActor
struct WatchConnectivityManagerTests {

    @Test func activateReturnsEarlyOnSimulator() {
        // WCSession.isSupported() returns false on iPhone simulator without paired watch
        WatchConnectivityManager.shared.activate()
    }

    @Test func receivedFilesStartsEmpty() {
        // Must run before processReceivedFile tests (serialized suite ensures this)
        #expect(WatchConnectivityManager.shared.receivedFiles.isEmpty)
    }

    @Test func delegateHandlesActivationWithoutError() {
        WatchConnectivityManager.shared.session(
            WCSession.default,
            activationDidCompleteWith: .activated,
            error: nil
        )
    }

    @Test func delegateHandlesActivationWithError() {
        WatchConnectivityManager.shared.session(
            WCSession.default,
            activationDidCompleteWith: .notActivated,
            error: NSError(domain: "test", code: 1)
        )
    }

    @Test func sessionDidBecomeInactive() {
        WatchConnectivityManager.shared.sessionDidBecomeInactive(WCSession.default)
    }

    @Test func sessionDidDeactivate() {
        WatchConnectivityManager.shared.sessionDidDeactivate(WCSession.default)
    }

    @Test func processReceivedFileMovesAndAppends() async throws {
        let manager = WatchConnectivityManager.shared
        let initialCount = manager.receivedFiles.count

        // Create a temp file to simulate a received file
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_received_\(UUID().uuidString).csv")
        try "test data".write(to: tempURL, atomically: true, encoding: .utf8)

        let fileName = "test_received_\(UUID().uuidString).csv"
        let metadata: [String: Any] = [
            "fileName": fileName,
            "sampleCount": 5,
            "startDate": Date().timeIntervalSince1970,
        ]

        manager.processReceivedFile(fileURL: tempURL, metadata: metadata)
        try await Task.sleep(for: .milliseconds(200))

        #expect(manager.receivedFiles.count == initialCount + 1)
        if let added = manager.receivedFiles.first(where: { $0.fileName == fileName }) {
            #expect(added.sampleCount == 5)
            try? FileManager.default.removeItem(at: added.fileURL)
        }
    }

    @Test func processReceivedFileWithNilMetadata() async throws {
        let manager = WatchConnectivityManager.shared
        let initialCount = manager.receivedFiles.count

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_nil_meta_\(UUID().uuidString).csv")
        try "data".write(to: tempURL, atomically: true, encoding: .utf8)

        manager.processReceivedFile(fileURL: tempURL, metadata: nil)
        try await Task.sleep(for: .milliseconds(200))

        #expect(manager.receivedFiles.count == initialCount + 1)
        // The nil-metadata file should have "unknown.csv" as fileName
        if let added = manager.receivedFiles.last(where: { $0.fileName == "unknown.csv" }) {
            #expect(added.sampleCount == 0)
            try? FileManager.default.removeItem(at: added.fileURL)
        }
    }
}
