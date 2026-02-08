import CryptoKit
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
            .appendingPathComponent("test_chunk_\(UUID().uuidString).cbor")
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
            .appendingPathComponent("chunk_0_\(UUID().uuidString).cbor")
        let url2 = FileManager.default.temporaryDirectory
            .appendingPathComponent("chunk_1_\(UUID().uuidString).cbor")
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
        // 1 manifest + 2 chunks = 3
        #expect(result?.totalUnitCount == 3)
        #expect(stub.sentFiles.count == 3)

        // First sent file is the manifest
        let manifestMeta = stub.sentFiles[0].1
        #expect(manifestMeta["isManifest"] as? Bool == true)
        #expect(manifestMeta["workoutId"] as? String == "2024-02-01_120000")

        // Verify metadata on first chunk (index 1 in sentFiles)
        let meta0 = stub.sentFiles[1].1
        #expect(meta0["chunkIndex"] as? Int == 0)
        #expect(meta0["totalChunks"] as? Int == 2)
        #expect(meta0["workoutId"] as? String == "2024-02-01_120000")
        #expect(meta0["totalSampleCount"] as? Int == 42)
        #expect(meta0["startDate"] as? TimeInterval == startDate.timeIntervalSince1970)
        #expect((meta0["chunkSizeBytes"] as? Int64 ?? 0) > 0)

        // Verify metadata on second chunk (index 2 in sentFiles)
        let meta1 = stub.sentFiles[2].1
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
            .appendingPathComponent("test_single_\(UUID().uuidString).cbor")
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

    @Test func sendChunksLogsErrorForMissingFile() {
        let stub = StubConnectivitySession()
        stub.activationState = .activated
        let manager = PhoneConnectivityManager(session: stub)

        let bogusURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("nonexistent_\(UUID().uuidString).cbor")

        let result = manager.sendChunks(
            chunkURLs: [bogusURL],
            workoutId: "2024-02-01_120000",
            startDate: Date(),
            totalSampleCount: 10
        )

        // manifest + chunk still fire (fileSize/md5 fall back to 0/"")
        #expect(result != nil)
        #expect(stub.sentFiles.count == 2)
        // First is manifest, second is the chunk
        let meta = stub.sentFiles[1].1
        #expect(meta["chunkSizeBytes"] as? Int64 == 0)
    }

    @Test func delegateHandlesFileTransferWithError() {
        let stub = StubConnectivitySession()
        let manager = PhoneConnectivityManager(session: stub)

        let transfer = WCSessionFileTransfer()
        manager.session(
            WCSession.default,
            didFinish: transfer,
            error: NSError(domain: "test", code: 7)
        )
    }

    @Test func delegateHandlesFileTransferWithoutError() {
        let stub = StubConnectivitySession()
        let manager = PhoneConnectivityManager(session: stub)

        let transfer = WCSessionFileTransfer()
        manager.session(
            WCSession.default,
            didFinish: transfer,
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

    @Test func sendChunksSendsManifestWithCorrectChecksums() throws {
        let stub = StubConnectivitySession()
        stub.activationState = .activated
        let manager = PhoneConnectivityManager(session: stub)

        let url1 = FileManager.default.temporaryDirectory
            .appendingPathComponent("chunk_0_\(UUID().uuidString).cbor")
        let data1 = Data("hello".utf8)
        try data1.write(to: url1)

        let expectedMD5 = Insecure.MD5.hash(data: data1)
            .map { String(format: "%02x", $0) }.joined()

        let result = manager.sendChunks(
            chunkURLs: [url1],
            workoutId: "test_md5",
            startDate: Date(timeIntervalSince1970: 1000),
            totalSampleCount: 5
        )

        #expect(result != nil)
        // First file is the manifest
        let manifestURL = stub.sentFiles[0].0
        let manifestData = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(TransferManifest.self, from: manifestData)

        #expect(manifest.workoutId == "test_md5")
        #expect(manifest.totalChunks == 1)
        #expect(manifest.totalSampleCount == 5)
        #expect(manifest.chunks.count == 1)
        #expect(manifest.chunks[0].fileName == url1.lastPathComponent)
        #expect(manifest.chunks[0].sizeBytes == Int64(data1.count))
        #expect(manifest.chunks[0].md5 == expectedMD5)

        try? FileManager.default.removeItem(at: url1)
    }

    @Test func sendChunksManifestSentBeforeChunks() throws {
        let stub = StubConnectivitySession()
        stub.activationState = .activated
        let manager = PhoneConnectivityManager(session: stub)

        let url1 = FileManager.default.temporaryDirectory
            .appendingPathComponent("chunk_0_\(UUID().uuidString).cbor")
        try "data".write(to: url1, atomically: true, encoding: .utf8)

        _ = manager.sendChunks(
            chunkURLs: [url1],
            workoutId: "order_test",
            startDate: Date(),
            totalSampleCount: 1
        )

        #expect(stub.sentFiles.count == 2)
        // Manifest is first
        #expect(stub.sentFiles[0].1["isManifest"] as? Bool == true)
        // Chunk is second
        #expect(stub.sentFiles[1].1["chunkIndex"] as? Int == 0)

        try? FileManager.default.removeItem(at: url1)
    }

    @Test func sendChunksReturnsNilWhenManifestWriteFails() throws {
        let stub = StubConnectivitySession()
        stub.activationState = .activated
        let manager = PhoneConnectivityManager(session: stub)

        let workoutId = "write_fail_\(UUID().uuidString)"
        // Create a directory at the manifest path so Data.write fails
        let manifestPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("manifest_\(workoutId).json")
        try FileManager.default.createDirectory(
            at: manifestPath, withIntermediateDirectories: true
        )

        let url1 = FileManager.default.temporaryDirectory
            .appendingPathComponent("chunk_0_\(UUID().uuidString).cbor")
        try "data".write(to: url1, atomically: true, encoding: .utf8)

        let result = manager.sendChunks(
            chunkURLs: [url1],
            workoutId: workoutId,
            startDate: Date(),
            totalSampleCount: 1
        )

        #expect(result == nil)

        try? FileManager.default.removeItem(at: manifestPath)
        try? FileManager.default.removeItem(at: url1)
    }

    @Test func sendChunksReturnsNilWhenManifestSendFails() throws {
        let stub = StubConnectivitySession()
        stub.activationState = .activated
        stub.sendFileReturnsNil = true
        let manager = PhoneConnectivityManager(session: stub)

        let url1 = FileManager.default.temporaryDirectory
            .appendingPathComponent("chunk_0_\(UUID().uuidString).cbor")
        try "data".write(to: url1, atomically: true, encoding: .utf8)

        let result = manager.sendChunks(
            chunkURLs: [url1],
            workoutId: "fail_test",
            startDate: Date(),
            totalSampleCount: 1
        )

        // Manifest send returned nil, so sendChunks returns nil
        #expect(result == nil)

        try? FileManager.default.removeItem(at: url1)
    }
}
