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

    // MARK: - Retransmission tests

    private func makeStoreWithWorkout(
        workoutId: String = "test-workout",
        chunkFileNames: [String] = ["chunk_0.cbor", "chunk_1.cbor"]
    ) throws -> (WorkoutStore, [URL]) {
        let persistURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_store_\(UUID().uuidString).json")
        let store = WorkoutStore(persistenceURL: persistURL)

        let documentsDir = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!
        var chunkURLs: [URL] = []
        for name in chunkFileNames {
            let url = documentsDir.appendingPathComponent(name)
            try "chunk data".write(to: url, atomically: true, encoding: .utf8)
            chunkURLs.append(url)
        }

        store.registerWorkout(
            workoutId: workoutId,
            startDate: Date(timeIntervalSince1970: 1000),
            chunkURLs: chunkURLs,
            totalSampleCount: 100
        )
        return (store, chunkURLs)
    }

    private func cleanupFiles(_ urls: [URL]) {
        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
    }

    @Test func handleRetransmissionReturnsNotFoundWhenStoreNil() {
        let stub = StubConnectivitySession()
        stub.activationState = .activated
        let manager = PhoneConnectivityManager(session: stub)

        let result = manager.handleRetransmissionRequest(
            RetransmissionRequest(workoutId: "missing", chunkIndices: [0], needsManifest: false)
        )
        #expect(result == .notFound)
    }

    @Test func handleRetransmissionReturnsNotFoundWhenWorkoutMissing() throws {
        let stub = StubConnectivitySession()
        stub.activationState = .activated
        let manager = PhoneConnectivityManager(session: stub)

        let persistURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_store_\(UUID().uuidString).json")
        let store = WorkoutStore(persistenceURL: persistURL)
        manager.workoutStore = store

        let result = manager.handleRetransmissionRequest(
            RetransmissionRequest(
                workoutId: "nonexistent", chunkIndices: [0], needsManifest: false
            )
        )
        #expect(result == .notFound)
    }

    @Test func handleRetransmissionReturnsDeniedWhenTransferInFlight() throws {
        let stub = StubConnectivitySession()
        stub.activationState = .activated
        let manager = PhoneConnectivityManager(session: stub)

        let (store, chunkURLs) = try makeStoreWithWorkout()
        manager.workoutStore = store

        let progress = Progress(totalUnitCount: 10)
        progress.completedUnitCount = 5
        store.activeTransfers["test-workout"] = progress

        let result = manager.handleRetransmissionRequest(
            RetransmissionRequest(
                workoutId: "test-workout", chunkIndices: [0], needsManifest: false
            )
        )
        #expect(result == .denied)

        cleanupFiles(chunkURLs)
    }

    @Test func handleRetransmissionReturnsAcceptedAndSendsChunks() throws {
        let stub = StubConnectivitySession()
        stub.activationState = .activated
        let manager = PhoneConnectivityManager(session: stub)

        let (store, chunkURLs) = try makeStoreWithWorkout()
        manager.workoutStore = store

        let result = manager.handleRetransmissionRequest(
            RetransmissionRequest(
                workoutId: "test-workout", chunkIndices: [0, 1], needsManifest: false
            )
        )
        #expect(result == .accepted)
        #expect(stub.sentFiles.count == 2)
        #expect(stub.sentFiles[0].1["chunkIndex"] as? Int == 0)
        #expect(stub.sentFiles[1].1["chunkIndex"] as? Int == 1)

        cleanupFiles(chunkURLs)
    }

    @Test func handleRetransmissionSendsManifestWhenRequested() throws {
        let stub = StubConnectivitySession()
        stub.activationState = .activated
        let manager = PhoneConnectivityManager(session: stub)

        let (store, chunkURLs) = try makeStoreWithWorkout()
        manager.workoutStore = store

        let result = manager.handleRetransmissionRequest(
            RetransmissionRequest(
                workoutId: "test-workout", chunkIndices: [0], needsManifest: true
            )
        )
        #expect(result == .accepted)
        #expect(stub.sentFiles.count == 2)
        #expect(stub.sentFiles[0].1["isManifest"] as? Bool == true)
        #expect(stub.sentFiles[1].1["chunkIndex"] as? Int == 0)

        cleanupFiles(chunkURLs)
    }

    @Test func handleRetransmissionAllowsWhenTransferComplete() throws {
        let stub = StubConnectivitySession()
        stub.activationState = .activated
        let manager = PhoneConnectivityManager(session: stub)

        let (store, chunkURLs) = try makeStoreWithWorkout()
        manager.workoutStore = store

        let progress = Progress(totalUnitCount: 10)
        progress.completedUnitCount = 10
        store.activeTransfers["test-workout"] = progress

        let result = manager.handleRetransmissionRequest(
            RetransmissionRequest(
                workoutId: "test-workout", chunkIndices: [1], needsManifest: false
            )
        )
        #expect(result == .accepted)
        #expect(stub.sentFiles.count == 1)

        cleanupFiles(chunkURLs)
    }

    @Test func delegateDidReceiveMessageCallsHandler() async throws {
        let stub = StubConnectivitySession()
        stub.activationState = .activated
        let manager = PhoneConnectivityManager(session: stub)

        let (store, chunkURLs) = try makeStoreWithWorkout()
        manager.workoutStore = store

        let message: [String: Any] = [
            "type": "requestChunks",
            "workoutId": "test-workout",
            "chunkIndices": [0],
            "needsManifest": false,
        ]

        let reply: [String: Any] = await withCheckedContinuation { continuation in
            manager.session(
                WCSession.default,
                didReceiveMessage: message,
                replyHandler: { reply in
                    continuation.resume(returning: reply)
                }
            )
        }
        #expect(reply["status"] as? String == "accepted")
        #expect(stub.sentFiles.count == 1)

        cleanupFiles(chunkURLs)
    }

    @Test func delegateDidReceiveMessageIgnoresUnknownType() async {
        let stub = StubConnectivitySession()
        let manager = PhoneConnectivityManager(session: stub)

        let message: [String: Any] = ["type": "unknown"]

        // replyHandler should never be called
        manager.session(
            WCSession.default,
            didReceiveMessage: message,
            replyHandler: { _ in
                Issue.record("replyHandler should not be called for unknown message type")
            }
        )

        // Give time for any async dispatch to execute
        try? await Task.sleep(for: .milliseconds(100))
    }

    @Test func handleRetransmissionSendsChunkWithMissingFile() throws {
        let stub = StubConnectivitySession()
        stub.activationState = .activated
        let manager = PhoneConnectivityManager(session: stub)

        // Register with a file name that does not exist on disk
        let (store, _) = try makeStoreWithWorkout(
            chunkFileNames: ["nonexistent_chunk.cbor"]
        )
        // Remove the file so attributesOfItem fails
        let documentsDir = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!
        let chunkURL = documentsDir.appendingPathComponent("nonexistent_chunk.cbor")
        try? FileManager.default.removeItem(at: chunkURL)

        manager.workoutStore = store

        let result = manager.handleRetransmissionRequest(
            RetransmissionRequest(
                workoutId: "test-workout", chunkIndices: [0], needsManifest: false
            )
        )
        #expect(result == .accepted)
        #expect(stub.sentFiles.count == 1)
        // chunkSizeBytes falls back to 0
        #expect(stub.sentFiles[0].1["chunkSizeBytes"] as? Int64 == 0)
    }

    @Test func retransmissionResponseToDictionary() {
        #expect(
            RetransmissionResponse.accepted.toDictionary()["status"] as? String == "accepted"
        )
        #expect(
            RetransmissionResponse.denied.toDictionary()["status"] as? String == "denied"
        )
        #expect(
            RetransmissionResponse.notFound.toDictionary()["status"] as? String == "notFound"
        )
    }

    @Test func retransmissionRequestToDictionary() {
        let request = RetransmissionRequest(
            workoutId: "w1", chunkIndices: [2, 5], needsManifest: true
        )
        let dict = request.toDictionary()
        #expect(dict["type"] as? String == "requestChunks")
        #expect(dict["workoutId"] as? String == "w1")
        #expect(dict["chunkIndices"] as? [Int] == [2, 5])
        #expect(dict["needsManifest"] as? Bool == true)
    }

    @Test func retransmissionRequestFromDictionary() {
        let dict: [String: Any] = [
            "type": "requestChunks",
            "workoutId": "w2",
            "chunkIndices": [0, 3],
            "needsManifest": false,
        ]
        let request = RetransmissionRequest(dictionary: dict)
        #expect(request != nil)
        #expect(request?.workoutId == "w2")
        #expect(request?.chunkIndices == [0, 3])
        #expect(request?.needsManifest == false)
    }

    @Test func retransmissionRequestFromMinimalDictionary() {
        // Only type + workoutId; chunkIndices and needsManifest use defaults
        let dict: [String: Any] = ["type": "requestChunks", "workoutId": "w3"]
        let request = RetransmissionRequest(dictionary: dict)
        #expect(request != nil)
        #expect(request?.workoutId == "w3")
        #expect(request?.chunkIndices == [])
        #expect(request?.needsManifest == false)
    }

    @Test func retransmissionRequestFromInvalidDictionary() {
        let dict: [String: Any] = ["type": "somethingElse"]
        #expect(RetransmissionRequest(dictionary: dict) == nil)

        let empty: [String: Any] = [:]
        #expect(RetransmissionRequest(dictionary: empty) == nil)
    }

    @Test func retransmissionResponseFromDictionary() {
        #expect(
            RetransmissionResponse(dictionary: ["status": "accepted"]) == .accepted
        )
        #expect(
            RetransmissionResponse(dictionary: ["status": "denied"]) == .denied
        )
        #expect(
            RetransmissionResponse(dictionary: ["status": "notFound"]) == .notFound
        )
        #expect(
            RetransmissionResponse(dictionary: ["status": "bogus"]) == nil
        )
        #expect(
            RetransmissionResponse(dictionary: [:]) == nil
        )
    }

    @Test func chunkFileURL() {
        let chunk = ChunkFile(chunkIndex: 0, fileName: "test.cbor")
        let docs = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!
        #expect(chunk.fileURL == docs.appendingPathComponent("test.cbor"))
    }

    @Test func chunkTransferInfoMetadata() {
        let date = Date(timeIntervalSince1970: 1_000_000)
        var info = ChunkTransferInfo(
            workoutId: "w1",
            chunkIndex: 2,
            totalChunks: 5,
            startDate: date,
            totalSampleCount: 42
        )
        info.fileName = "chunk2.cbor"
        info.chunkSizeBytes = 8192

        let meta = info.metadata()
        #expect(meta["fileName"] as? String == "chunk2.cbor")
        #expect(meta["workoutId"] as? String == "w1")
        #expect(meta["chunkIndex"] as? Int == 2)
        #expect(meta["totalChunks"] as? Int == 5)
        #expect(meta["startDate"] as? Double == 1_000_000)
        #expect(meta["totalSampleCount"] as? Int == 42)
        #expect(meta["chunkSizeBytes"] as? Int64 == 8192)
    }
}
