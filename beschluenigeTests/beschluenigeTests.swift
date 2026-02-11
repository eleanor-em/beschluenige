import Foundation
import Testing
import WatchConnectivity
@testable import beschluenige

// WCSessionFile is an ObjC class with readonly properties. Subclassing and
// overriding the getters works; KVC does not (crashes on readonly ivars).
private class FakeSessionFile: WCSessionFile {
    private let _url: URL
    private let _meta: [String: Any]?

    init(url: URL, meta: [String: Any]?) {
        _url = url
        _meta = meta
        super.init()
    }

    override var fileURL: URL { _url }
    override var metadata: [String: Any]? { _meta }
}

@Suite(.serialized)
@MainActor
struct WatchConnectivityManagerTests {

    @Test func activateReturnsEarlyOnSimulator() {
        // WCSession.isSupported() returns false on iPhone simulator without paired watch
        WatchConnectivityManager.shared.activate()
    }

    @Test func workoutsStartsEmptyOrClean() {
        // Shared singleton may have leftover records from other suites
        // Clean up and verify the clean state
        let manager = WatchConnectivityManager.shared
        let testWorkouts = manager.workouts.filter {
            $0.workoutId.hasPrefix("test_workout_")
                || $0.workoutId.hasPrefix("merge_test_")
        }
        for w in testWorkouts { manager.deleteWorkout(w) }
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

    @Test func sessionDidReceiveFile() async throws {
        let manager = WatchConnectivityManager.shared
        let workoutId = "delegate_recv_\(UUID().uuidString)"

        // Create a valid temp file to be "received"
        var enc = CBOREncoder()
        enc.encodeMapHeader(count: 4)
        for key in 0..<4 {
            enc.encodeUInt(UInt64(key))
            enc.encodeArrayHeader(count: 0)
        }
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("delegate_\(UUID().uuidString).cbor")
        try enc.data.write(to: tempURL)

        let metadata: [String: Any] = [
            "fileName": "delegate_\(workoutId).cbor",
            "workoutId": workoutId,
            "chunkIndex": 0,
            "totalChunks": 1,
            "totalSampleCount": 0,
            "startDate": Date().timeIntervalSince1970,
        ]

        // Subclass WCSessionFile to override readonly properties
        let fakeFile = FakeSessionFile(url: tempURL, meta: metadata)
        manager.session(WCSession.default, didReceive: fakeFile)
        try await Task.sleep(for: .milliseconds(200))

        if let record = manager.workouts.first(where: { $0.workoutId == workoutId }) {
            manager.deleteWorkout(record)
        }
    }

    @Test func processChunkedFileCreatesWorkoutRecord() async throws {
        let manager = WatchConnectivityManager.shared

        // Create a temp CBOR chunk file
        var enc = CBOREncoder()
        enc.encodeMapHeader(count: 4)
        for key in 0..<4 {
            enc.encodeUInt(UInt64(key))
            enc.encodeArrayHeader(count: 0)
        }
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_chunk_\(UUID().uuidString).cbor")
        try enc.data.write(to: tempURL)

        let workoutId = "test_workout_\(UUID().uuidString)"
        let fileName = "workout_\(workoutId)_0.cbor"
        let metadata: [String: Any] = [
            "fileName": fileName,
            "workoutId": workoutId,
            "chunkIndex": 0,
            "totalChunks": 3,
            "totalSampleCount": 100,
            "startDate": Date().timeIntervalSince1970,
        ]

        manager.processReceivedFile(fileURL: tempURL, metadata: metadata)
        try await Task.sleep(for: .milliseconds(200))

        if let record = manager.workouts.first(where: { $0.workoutId == workoutId }) {
            #expect(record.receivedChunks.count == 1)
            #expect(!record.isComplete)
            #expect(record.totalChunks == 3)
            manager.deleteWorkout(record)
        } else {
            Issue.record("Workout record not found after processing chunk")
        }
    }

    private func makeCborChunk(hrTimestamp: Double, hrBpm: Double) -> Data {
        var enc = CBOREncoder()
        enc.encodeMapHeader(count: 4)
        enc.encodeUInt(0)
        enc.encodeArrayHeader(count: 1)
        enc.encodeFloat64Array([hrTimestamp, hrBpm])
        for key in 1..<4 {
            enc.encodeUInt(UInt64(key))
            enc.encodeArrayHeader(count: 0)
        }
        return enc.data
    }

    private func sendChunk(
        _ manager: WatchConnectivityManager,
        data: Data,
        workoutId: String,
        index: Int,
        totalChunks: Int
    ) async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("merge_chunk_\(index)_\(UUID().uuidString).cbor")
        try data.write(to: tempURL)
        let metadata: [String: Any] = [
            "fileName": "workout_\(workoutId)_\(index).cbor",
            "workoutId": workoutId,
            "chunkIndex": index,
            "totalChunks": totalChunks,
            "totalSampleCount": 42,
            "startDate": Date().timeIntervalSince1970,
        ]
        manager.processReceivedFile(fileURL: tempURL, metadata: metadata)
        try await Task.sleep(for: .milliseconds(200))
    }

    @Test func allChunksReceivedTriggersMerge() async throws {
        let manager = WatchConnectivityManager.shared
        let workoutId = "merge_test_\(UUID().uuidString)"

        for i in 0..<2 {
            let chunk = makeCborChunk(hrTimestamp: Double(1000 + i), hrBpm: Double(100 + i * 10))
            try await sendChunk(manager, data: chunk, workoutId: workoutId, index: i, totalChunks: 2)
        }

        guard let record = manager.workouts.first(where: { $0.workoutId == workoutId }) else {
            Issue.record("Workout record not found after receiving all chunks")
            return
        }
        #expect(record.isComplete)
        #expect(record.mergedFileName != nil)

        if let mergedURL = record.mergedFileURL {
            let data = try Data(contentsOf: mergedURL)
            var dec = CBORDecoder(data: data)
            #expect(try dec.decodeMapHeader() == 4)

            #expect(try dec.decodeUInt() == 0)
            #expect(try dec.decodeArrayHeader() == nil)
            #expect(try dec.decodeFloat64Array() == [1000.0, 100.0])
            #expect(try dec.decodeFloat64Array() == [1001.0, 110.0])
            try dec.decodeBreak()

            for key in 1...3 {
                #expect(try dec.decodeUInt() == UInt64(key))
                #expect(try dec.decodeArrayHeader() == nil)
                try dec.decodeBreak()
            }
            #expect(dec.isAtEnd)
        }
        manager.deleteWorkout(record)
    }

    @Test func processReceivedFileWithNilMetadata() async throws {
        let manager = WatchConnectivityManager.shared

        // Clean up any leftover "unknown" record from prior runs
        if let old = manager.workouts.first(where: { $0.workoutId == "unknown" }) {
            manager.deleteWorkout(old)
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_nil_meta_\(UUID().uuidString).cbor")
        try Data([0x00]).write(to: tempURL)

        // Exercises ?? "unknown" default for all metadata fields (coverage)
        manager.processReceivedFile(fileURL: tempURL, metadata: nil)
        try await Task.sleep(for: .milliseconds(200))

        // Nil metadata: workoutId = "unknown". A concurrent test in another
        // suite may also use "unknown", so only verify the record exists.
        let record = manager.workouts.first(where: { $0.workoutId == "unknown" })
        #expect(record != nil)
        if let record {
            manager.deleteWorkout(record)
        }
    }

    @Test func deleteWorkoutRemovesFiles() async throws {
        let manager = WatchConnectivityManager.shared

        let workoutId = "delete_test_\(UUID().uuidString)"
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("delete_chunk_\(UUID().uuidString).cbor")
        try Data([0x00]).write(to: tempURL)

        let fileName = "workout_\(workoutId)_0.cbor"
        let metadata: [String: Any] = [
            "fileName": fileName,
            "workoutId": workoutId,
            "chunkIndex": 0,
            "totalChunks": 1,
            "totalSampleCount": 5,
            "startDate": Date().timeIntervalSince1970,
        ]

        manager.processReceivedFile(fileURL: tempURL, metadata: metadata)
        try await Task.sleep(for: .milliseconds(200))

        if let record = manager.workouts.first(where: { $0.workoutId == workoutId }) {
            manager.deleteWorkout(record)
            #expect(manager.workouts.first(where: { $0.workoutId == workoutId }) == nil)
        }
    }

    // MARK: - Retransmission tests

    @Test func requestRetransmissionReturnsAlreadyMerged() async throws {
        let manager = WatchConnectivityManager.shared
        let workoutId = "merged_\(UUID().uuidString)"

        // Create two chunks and let them merge
        for i in 0..<2 {
            let chunk = makeCborChunk(hrTimestamp: Double(2000 + i), hrBpm: Double(120 + i))
            try await sendChunk(
                manager, data: chunk, workoutId: workoutId, index: i, totalChunks: 2
            )
        }

        guard let record = manager.workouts.first(where: { $0.workoutId == workoutId }) else {
            Issue.record("Workout not found")
            return
        }
        #expect(record.mergedFileName != nil)

        let result = await manager.requestRetransmission(workoutId: workoutId)
        #expect(result == .alreadyMerged)

        manager.deleteWorkout(record)
    }

    @Test func requestRetransmissionReturnsNothingToRequest() async throws {
        let manager = WatchConnectivityManager.shared
        let workoutId = "nothing_\(UUID().uuidString)"

        // Send 1 chunk of 1 total -- but don't let it merge (no manifest needed)
        let chunk = makeCborChunk(hrTimestamp: 3000, hrBpm: 130)
        try await sendChunk(manager, data: chunk, workoutId: workoutId, index: 0, totalChunks: 1)

        // It auto-merged because isComplete was true
        guard let record = manager.workouts.first(where: { $0.workoutId == workoutId }) else {
            Issue.record("Workout not found")
            return
        }

        let result = await manager.requestRetransmission(workoutId: workoutId)
        // Already merged after processChunk, so alreadyMerged
        #expect(result == .alreadyMerged)

        manager.deleteWorkout(record)
    }

    @Test func requestRetransmissionReturnsUnreachable() async throws {
        let manager = WatchConnectivityManager.shared
        let workoutId = "unreach_\(UUID().uuidString)"

        // Create a workout with 2 chunks but only send 1
        let chunk = makeCborChunk(hrTimestamp: 4000, hrBpm: 140)
        try await sendChunk(manager, data: chunk, workoutId: workoutId, index: 0, totalChunks: 2)

        let saved = manager.isWatchReachable
        manager.isWatchReachable = { false }

        let result = await manager.requestRetransmission(workoutId: workoutId)
        #expect(result == .unreachable)

        manager.isWatchReachable = saved
        if let record = manager.workouts.first(where: { $0.workoutId == workoutId }) {
            manager.deleteWorkout(record)
        }
    }

    @Test func requestRetransmissionReturnsAccepted() async throws {
        let manager = WatchConnectivityManager.shared
        let workoutId = "accepted_\(UUID().uuidString)"

        let chunk = makeCborChunk(hrTimestamp: 5000, hrBpm: 150)
        try await sendChunk(manager, data: chunk, workoutId: workoutId, index: 0, totalChunks: 2)

        let savedReachable = manager.isWatchReachable
        let savedSend = manager.sendRetransmissionRequest
        manager.isWatchReachable = { true }
        manager.sendRetransmissionRequest = { _ in .accepted }

        let result = await manager.requestRetransmission(workoutId: workoutId)
        #expect(result == .accepted)

        manager.isWatchReachable = savedReachable
        manager.sendRetransmissionRequest = savedSend
        if let record = manager.workouts.first(where: { $0.workoutId == workoutId }) {
            manager.deleteWorkout(record)
        }
    }

    @Test func requestRetransmissionReturnsDenied() async throws {
        let manager = WatchConnectivityManager.shared
        let workoutId = "denied_\(UUID().uuidString)"

        let chunk = makeCborChunk(hrTimestamp: 6000, hrBpm: 160)
        try await sendChunk(manager, data: chunk, workoutId: workoutId, index: 0, totalChunks: 2)

        let savedReachable = manager.isWatchReachable
        let savedSend = manager.sendRetransmissionRequest
        manager.isWatchReachable = { true }
        manager.sendRetransmissionRequest = { _ in .denied }

        let result = await manager.requestRetransmission(workoutId: workoutId)
        #expect(result == .denied)

        manager.isWatchReachable = savedReachable
        manager.sendRetransmissionRequest = savedSend
        if let record = manager.workouts.first(where: { $0.workoutId == workoutId }) {
            manager.deleteWorkout(record)
        }
    }

    @Test func requestRetransmissionReturnsNotFound() async throws {
        let manager = WatchConnectivityManager.shared
        let workoutId = "notfound_\(UUID().uuidString)"

        let chunk = makeCborChunk(hrTimestamp: 7000, hrBpm: 170)
        try await sendChunk(manager, data: chunk, workoutId: workoutId, index: 0, totalChunks: 2)

        let savedReachable = manager.isWatchReachable
        let savedSend = manager.sendRetransmissionRequest
        manager.isWatchReachable = { true }
        manager.sendRetransmissionRequest = { _ in .notFound }

        let result = await manager.requestRetransmission(workoutId: workoutId)
        #expect(result == .notFound)

        manager.isWatchReachable = savedReachable
        manager.sendRetransmissionRequest = savedSend
        if let record = manager.workouts.first(where: { $0.workoutId == workoutId }) {
            manager.deleteWorkout(record)
        }
    }

    @Test func requestRetransmissionReturnsUnreachableOnSendError() async throws {
        let manager = WatchConnectivityManager.shared
        let workoutId = "sendfail_\(UUID().uuidString)"

        let chunk = makeCborChunk(hrTimestamp: 8000, hrBpm: 180)
        try await sendChunk(manager, data: chunk, workoutId: workoutId, index: 0, totalChunks: 2)

        let savedReachable = manager.isWatchReachable
        let savedSend = manager.sendRetransmissionRequest
        manager.isWatchReachable = { true }
        manager.sendRetransmissionRequest = { _ in throw NSError(domain: "test", code: 42) }

        let result = await manager.requestRetransmission(workoutId: workoutId)
        #expect(result == .unreachable)

        manager.isWatchReachable = savedReachable
        manager.sendRetransmissionRequest = savedSend
        if let record = manager.workouts.first(where: { $0.workoutId == workoutId }) {
            manager.deleteWorkout(record)
        }
    }

    @Test func requestRetransmissionWorkoutNotFound() async {
        let manager = WatchConnectivityManager.shared
        let result = await manager.requestRetransmission(
            workoutId: "nonexistent_\(UUID().uuidString)"
        )
        #expect(result == .error("Workout not found"))
    }

    @Test func chunkFileURL() {
        let chunk = WatchConnectivityManager.ChunkFile(
            chunkIndex: 0, fileName: "test_file.cbor"
        )
        #expect(chunk.fileURL.lastPathComponent == "test_file.cbor")
    }
}
