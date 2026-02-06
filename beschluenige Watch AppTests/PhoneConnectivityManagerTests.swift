import Foundation
import Testing
import WatchConnectivity
@testable import beschluenige_Watch_App

@MainActor
struct PhoneConnectivityManagerTests {

    @Test func sendChunksReturnsNilWhenNotActivated() throws {
        let stub = StubConnectivitySession()
        stub.activationState = .notActivated
        let manager = PhoneConnectivityManager(session: stub)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_chunk_\(UUID().uuidString).csv")
        try "test".write(to: tempURL, atomically: true, encoding: .utf8)

        let result = manager.sendChunks(
            chunkURLs: [tempURL],
            workoutId: "2024-02-01_120000",
            startDate: Date(),
            totalSampleCount: 10
        )
        #expect(result == nil)

        try? FileManager.default.removeItem(at: tempURL)
    }

    @Test func sendChunksReturnsNilWhenEmpty() {
        let stub = StubConnectivitySession()
        stub.activationState = .activated
        let manager = PhoneConnectivityManager(session: stub)

        let result = manager.sendChunks(
            chunkURLs: [],
            workoutId: "2024-02-01_120000",
            startDate: Date(),
            totalSampleCount: 0
        )
        #expect(result == nil)
    }

    @Test func sendChunksSendsAllFiles() throws {
        let stub = StubConnectivitySession()
        stub.activationState = .activated
        let manager = PhoneConnectivityManager(session: stub)

        let url1 = FileManager.default.temporaryDirectory
            .appendingPathComponent("chunk_0_\(UUID().uuidString).csv")
        let url2 = FileManager.default.temporaryDirectory
            .appendingPathComponent("chunk_1_\(UUID().uuidString).csv")
        try "data1".write(to: url1, atomically: true, encoding: .utf8)
        try "data2".write(to: url2, atomically: true, encoding: .utf8)

        let startDate = Date(timeIntervalSince1970: 1706812345)
        let result = manager.sendChunks(
            chunkURLs: [url1, url2],
            workoutId: "2024-02-01_120000",
            startDate: startDate,
            totalSampleCount: 42
        )

        #expect(result != nil)
        #expect(result?.totalUnitCount == 2)
        #expect(stub.sentFiles.count == 2)

        // Verify metadata on first chunk
        let meta0 = stub.sentFiles[0].1
        #expect(meta0["chunkIndex"] as? Int == 0)
        #expect(meta0["totalChunks"] as? Int == 2)
        #expect(meta0["workoutId"] as? String == "2024-02-01_120000")
        #expect(meta0["totalSampleCount"] as? Int == 42)
        #expect(meta0["startDate"] as? TimeInterval == startDate.timeIntervalSince1970)
        #expect((meta0["chunkSizeBytes"] as? Int64 ?? 0) > 0)

        // Verify metadata on second chunk
        let meta1 = stub.sentFiles[1].1
        #expect(meta1["chunkIndex"] as? Int == 1)
        #expect(meta1["totalChunks"] as? Int == 2)
        #expect((meta1["chunkSizeBytes"] as? Int64 ?? 0) > 0)

        try? FileManager.default.removeItem(at: url1)
        try? FileManager.default.removeItem(at: url2)
    }

    @Test func sendChunkReturnsNilWhenNotActivated() throws {
        let stub = StubConnectivitySession()
        stub.activationState = .notActivated
        let manager = PhoneConnectivityManager(session: stub)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_single_\(UUID().uuidString).csv")
        try "data".write(to: tempURL, atomically: true, encoding: .utf8)

        let result = manager.sendChunk(
            fileURL: tempURL,
            info: ChunkTransferInfo(
                workoutId: "test",
                chunkIndex: 0,
                totalChunks: 1,
                startDate: Date(),
                totalSampleCount: 5
            )
        )
        #expect(result == nil)

        try? FileManager.default.removeItem(at: tempURL)
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
