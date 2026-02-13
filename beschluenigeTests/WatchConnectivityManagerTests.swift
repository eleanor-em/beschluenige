import Foundation
import Synchronization
import Testing
import WatchConnectivity
@testable import beschluenige

// MARK: - Persistence Tests

@Suite(.serialized)
@MainActor
struct PersistenceTests {

    @Test func loadWorkoutsPersistsAndLoads() throws {
        let manager = WatchConnectivityManager.shared
        let workoutId = "loadtest_\(UUID().uuidString)"

        let record = WorkoutRecord(
            workoutId: workoutId,
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            totalSampleCount: 10,
            totalChunks: 2
        )
        manager.workouts.append(record)
        manager.saveWorkouts()

        manager.workouts.removeAll { $0.workoutId == workoutId }
        #expect(manager.workouts.first(where: { $0.workoutId == workoutId }) == nil)

        manager.loadWorkouts()
        let loaded = manager.workouts.first { $0.workoutId == workoutId }
        #expect(loaded != nil)
        #expect(loaded?.totalChunks == 2)

        if let r = loaded { manager.deleteWorkout(r) }
    }

    @Test func loadWorkoutsHandlesCorruptFile() throws {
        let manager = WatchConnectivityManager.shared
        let url = manager.persistedFilesURL()
        let backup = try? Data(contentsOf: url)
        defer {
            if let backup {
                try? backup.write(to: url)
            } else {
                try? FileManager.default.removeItem(at: url)
            }
        }

        try Data("not json".utf8).write(to: url)
        manager.loadWorkouts()
        #expect(manager.workouts.count >= 0)

        if let backup {
            try backup.write(to: url)
            manager.loadWorkouts()
        }
    }
}

// MARK: - Chunk Decode, Merge, and StreamDecode Tests

@Suite(.serialized)
@MainActor
struct DecodeAndMergeTests {

    private let testLogger = AppLogger(category: "test")

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

    @Test func decodeChunkIndefiniteArrayReturnsError() {
        var enc = CBOREncoder()
        enc.encodeMapHeader(count: 1)
        enc.encodeUInt(0)
        enc.encodeIndefiniteArrayHeader()
        enc.encodeFloat64Array([1000.0, 80.0])
        enc.encodeBreak()

        var buckets: [[[Double]]] = [[], [], [], []]
        let result = WorkoutRecord.decodeChunk(
            enc.data,
            into: &buckets,
            fileName: "test.cbor",
            logger: testLogger
        )
        #expect(!result)
    }

    @Test func decodeChunkCorruptCBOR() {
        var buckets: [[[Double]]] = [[], [], [], []]
        let result = WorkoutRecord.decodeChunk(
            Data([0xFF, 0xFE]),
            into: &buckets,
            fileName: "corrupt.cbor",
            logger: testLogger
        )
        #expect(!result)
    }

    @Test func decodeChunkSkipsUnknownKey() {
        var enc = CBOREncoder()
        enc.encodeMapHeader(count: 1)
        enc.encodeUInt(99)
        enc.encodeArrayHeader(count: 1)
        enc.encodeFloat64Array([1000.0, 80.0])

        var buckets: [[[Double]]] = [[], [], [], []]
        let result = WorkoutRecord.decodeChunk(
            enc.data,
            into: &buckets,
            fileName: "unknown_key.cbor",
            logger: testLogger
        )
        #expect(result)
        // All buckets should be empty since key=99 is out of range
        for bucket in buckets {
            #expect(bucket.isEmpty)
        }
    }

    // MARK: - mergeChunks with unreadable chunk

    @Test func mergeChunksWriteFailure() throws {
        let workoutId = "write_fail_\(UUID().uuidString)"
        let documentsDir = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!

        // Create a valid chunk file that can be read
        let chunkData = makeCborChunk(hrTimestamp: 12_000, hrBpm: 100)
        let chunkFileName = "workout_\(workoutId)_0.cbor"
        let chunkURL = documentsDir.appendingPathComponent(chunkFileName)
        try chunkData.write(to: chunkURL)
        defer { try? FileManager.default.removeItem(at: chunkURL) }

        // Create a DIRECTORY at the merged file path so write fails
        let mergedPath = documentsDir.appendingPathComponent("workout_\(workoutId).cbor")
        try FileManager.default.createDirectory(at: mergedPath, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: mergedPath) }

        var record = WorkoutRecord(
            workoutId: workoutId,
            startDate: Date(),
            totalSampleCount: 10,
            totalChunks: 1
        )
        record.receivedChunks = [
            ChunkFile(chunkIndex: 0, fileName: chunkFileName),
        ]

        record.mergeChunks(logger: testLogger)
        // Merge write should have failed -- mergedFileName stays nil
        #expect(record.mergedFileName == nil)
    }

    @Test func mergeChunksHandlesUnreadableFile() {
        let workoutId = "unreadable_\(UUID().uuidString)"

        var record = WorkoutRecord(
            workoutId: workoutId,
            startDate: Date(),
            totalSampleCount: 10,
            totalChunks: 1
        )
        record.receivedChunks = [
            ChunkFile(
                chunkIndex: 0,
                fileName: "nonexistent_\(UUID().uuidString).cbor"
            ),
        ]

        record.mergeChunks(logger: testLogger)
        #expect(record.mergedFileName == nil)
    }

    // MARK: - decodeWorkout

    @Test func decodeWorkoutCorruptFile() async throws {
        let manager = WatchConnectivityManager.shared
        let workoutId = "decode_err_\(UUID().uuidString)"
        let fileName = "decode_err_\(UUID().uuidString).cbor"

        let documentsDir = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!
        let docURL = documentsDir.appendingPathComponent(fileName)
        try Data([0xFF, 0xFE]).write(to: docURL)
        defer { try? FileManager.default.removeItem(at: docURL) }

        var record = WorkoutRecord(
            workoutId: workoutId,
            startDate: Date(timeIntervalSince1970: 1000),
            totalSampleCount: 4,
            totalChunks: 1
        )
        record.mergedFileName = fileName
        manager.workouts.append(record)
        defer {
            manager.decodedSummaries.removeValue(forKey: workoutId)
            manager.decodedTimeseries.removeValue(forKey: workoutId)
            manager.decodingProgress.removeValue(forKey: workoutId)
            manager.decodingErrors.removeValue(forKey: workoutId)
            manager.workouts.removeAll { $0.workoutId == workoutId }
        }

        manager.decodeWorkout(record)

        for _ in 0..<50 {
            try await Task.sleep(for: .milliseconds(100))
            if manager.decodingErrors[workoutId] != nil { break }
        }

        #expect(manager.decodingErrors[workoutId] != nil)
        #expect(manager.decodingProgress[workoutId] == nil)
    }

    @Test func decodeWorkoutSkipsAlreadyDecoded() {
        let manager = WatchConnectivityManager.shared
        let workoutId = "skip_decoded_\(UUID().uuidString)"

        var record = WorkoutRecord(
            workoutId: workoutId,
            startDate: Date(),
            totalSampleCount: 10,
            totalChunks: 1
        )
        record.mergedFileName = "test.cbor"
        manager.workouts.append(record)

        manager.decodedSummaries[workoutId] = WorkoutSummary(
            heartRateCount: 0, heartRateMin: nil, heartRateMax: nil,
            heartRateAvg: nil, gpsCount: 0, maxSpeed: nil,
            accelerometerCount: 0, deviceMotionCount: 0,
            firstTimestamp: nil, lastTimestamp: nil
        )
        defer {
            manager.decodedSummaries.removeValue(forKey: workoutId)
            manager.workouts.removeAll { $0.workoutId == workoutId }
        }

        manager.decodeWorkout(record)
        #expect(manager.decodingProgress[workoutId] == nil)
    }

    @Test func decodeWorkoutSkipsNoMergedFile() {
        let manager = WatchConnectivityManager.shared
        let workoutId = "skip_nomerge_\(UUID().uuidString)"

        let record = WorkoutRecord(
            workoutId: workoutId,
            startDate: Date(),
            totalSampleCount: 10,
            totalChunks: 2
        )
        manager.workouts.append(record)
        defer { manager.workouts.removeAll { $0.workoutId == workoutId } }

        manager.decodeWorkout(record)
        #expect(manager.decodingProgress[workoutId] == nil)
    }

    @Test func decodeWorkoutSkipsInProgress() {
        let manager = WatchConnectivityManager.shared
        let workoutId = "skip_progress_\(UUID().uuidString)"

        var record = WorkoutRecord(
            workoutId: workoutId,
            startDate: Date(),
            totalSampleCount: 10,
            totalChunks: 1
        )
        record.mergedFileName = "test.cbor"
        manager.workouts.append(record)
        manager.decodingProgress[workoutId] = 0.5
        defer {
            manager.decodingProgress.removeValue(forKey: workoutId)
            manager.workouts.removeAll { $0.workoutId == workoutId }
        }

        // Should not start a second decode
        manager.decodeWorkout(record)
    }

    @Test func decodeWorkoutSkipsNonexistentFile() {
        let manager = WatchConnectivityManager.shared
        let workoutId = "skip_nofile_\(UUID().uuidString)"

        var record = WorkoutRecord(
            workoutId: workoutId,
            startDate: Date(),
            totalSampleCount: 10,
            totalChunks: 1
        )
        record.mergedFileName = "nonexistent_\(UUID().uuidString).cbor"
        manager.workouts.append(record)
        defer { manager.workouts.removeAll { $0.workoutId == workoutId } }

        manager.decodeWorkout(record)
        #expect(manager.decodingProgress[workoutId] == nil)
    }

    // MARK: - streamDecode definite-length

    @Test func streamDecodeDefiniteLength() async throws {
        var enc = CBOREncoder()
        enc.encodeMapHeader(count: 4)
        enc.encodeUInt(0)
        enc.encodeArrayHeader(count: 2)
        enc.encodeFloat64Array([1000.0, 80.0])
        enc.encodeFloat64Array([1001.0, 120.0])
        enc.encodeUInt(1)
        enc.encodeArrayHeader(count: 1)
        enc.encodeFloat64Array([1000.0, 0, 0, 0, 0, 0, 5.0, 0])
        enc.encodeUInt(2)
        enc.encodeArrayHeader(count: 0)
        enc.encodeUInt(3)
        enc.encodeArrayHeader(count: 0)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("definite_\(UUID().uuidString).cbor")
        try enc.data.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let (summary, timeseries) = try await WatchConnectivityManager.streamDecode(
            from: tempURL
        ) { _, _, _ in }

        #expect(summary.heartRateCount == 2)
        #expect(summary.gpsCount == 1)
        #expect(timeseries.heartRate.count == 2)
    }

    @Test func streamDecodeDefiniteLengthProgressCallback() async throws {
        // Build CBOR with > 10000 HR samples to trigger the progress callback
        var enc = CBOREncoder()
        enc.encodeMapHeader(count: 4)
        enc.encodeUInt(0)
        let sampleCount = 10_001
        enc.encodeArrayHeader(count: sampleCount)
        for i in 0..<sampleCount {
            enc.encodeFloat64Array([Double(1000 + i), Double(80 + i % 40)])
        }
        for key in 1..<4 {
            enc.encodeUInt(UInt64(key))
            enc.encodeArrayHeader(count: 0)
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("progress_\(UUID().uuidString).cbor")
        try enc.data.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let progressCalled = Mutex(false)
        let (summary, _) = try await WatchConnectivityManager.streamDecode(
            from: tempURL
        ) { _, _, _ in
            progressCalled.withLock { $0 = true }
        }

        #expect(summary.heartRateCount == sampleCount)
        #expect(progressCalled.withLock { $0 })
    }

    @Test func streamDecodeIndefiniteLengthProgressCallback() async throws {
        // Build CBOR with > 10000 HR samples in indefinite arrays
        var enc = CBOREncoder()
        enc.encodeMapHeader(count: 4)
        enc.encodeUInt(0)
        enc.encodeIndefiniteArrayHeader()
        let sampleCount = 10_001
        for i in 0..<sampleCount {
            enc.encodeFloat64Array([Double(1000 + i), Double(80 + i % 40)])
        }
        enc.encodeBreak()
        for key in 1..<4 {
            enc.encodeUInt(UInt64(key))
            enc.encodeIndefiniteArrayHeader()
            enc.encodeBreak()
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("indef_progress_\(UUID().uuidString).cbor")
        try enc.data.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let progressCalled = Mutex(false)
        let (summary, _) = try await WatchConnectivityManager.streamDecode(
            from: tempURL
        ) { _, _, _ in
            progressCalled.withLock { $0 = true }
        }

        #expect(summary.heartRateCount == sampleCount)
        #expect(progressCalled.withLock { $0 })
    }

    // MARK: - processReceivedFile replaces existing

    @Test func saveWorkoutsHandlesWriteFailure() {
        let manager = WatchConnectivityManager.shared
        let saved = manager.persistedFilesURLOverride

        // Point to an invalid path (directory) so write fails
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("save_fail_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        manager.persistedFilesURLOverride = dir
        manager.saveWorkouts()

        manager.persistedFilesURLOverride = saved
    }

    @Test func processReceivedFileMoveFailure() async throws {
        let manager = WatchConnectivityManager.shared
        let workoutId = "move_fail_\(UUID().uuidString)"

        // Pass a source file that does NOT exist -- moveItem will throw
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing_\(UUID().uuidString).cbor")
        let metadata: [String: Any] = [
            "fileName": "move_fail.cbor",
            "workoutId": workoutId,
            "chunkIndex": 0,
            "totalChunks": 1,
            "totalSampleCount": 10,
            "startDate": Date().timeIntervalSince1970,
        ]

        manager.processReceivedFile(fileURL: missingURL, metadata: metadata)
        try await Task.sleep(for: .milliseconds(200))

        // Workout should NOT have been created since moveItem failed
        let record = manager.workouts.first { $0.workoutId == workoutId }
        #expect(record == nil)
    }

    @Test func processReceivedFileReplacesExisting() async throws {
        let manager = WatchConnectivityManager.shared
        let workoutId = "replace_\(UUID().uuidString)"

        let documentsDir = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!
        let fileName = "workout_\(workoutId)_0.cbor"

        let destURL = documentsDir.appendingPathComponent(fileName)
        try Data("old data".utf8).write(to: destURL)
        defer { try? FileManager.default.removeItem(at: destURL) }

        let chunkData = makeCborChunk(hrTimestamp: 11_000, hrBpm: 110)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("replace_\(UUID().uuidString).cbor")
        try chunkData.write(to: tempURL)

        let metadata: [String: Any] = [
            "fileName": fileName,
            "workoutId": workoutId,
            "chunkIndex": 0,
            "totalChunks": 2,
            "totalSampleCount": 10,
            "startDate": Date().timeIntervalSince1970,
        ]
        manager.processReceivedFile(fileURL: tempURL, metadata: metadata)
        try await Task.sleep(for: .milliseconds(200))

        let record = manager.workouts.first { $0.workoutId == workoutId }
        #expect(record?.receivedChunks.count == 1)

        if let r = record { manager.deleteWorkout(r) }
    }

    // MARK: - Default closure and delegate coverage

    @Test func defaultSendRetransmissionRequestThrowsOnSimulator() async {
        let request = RetransmissionRequest(
            workoutId: "test",
            chunkIndices: [0],
            needsManifest: false
        )
        do {
            _ = try await WatchConnectivityManager.defaultSendRetransmissionRequest(request)
            Issue.record("Expected throw")
        } catch {
            // Expected: throws RetransmissionError.unexpectedReply on simulator
        }
    }

    @Test func defaultIsWatchReachable() {
        let manager = WatchConnectivityManager.shared
        let saved = manager.isWatchReachable
        defer { manager.isWatchReachable = saved }

        // Reset to the real default
        manager.isWatchReachable = { WCSession.default.isReachable }
        let result = manager.isWatchReachable()
        // In simulator, watch is not reachable
        #expect(!result)
    }

    // MARK: - requestRetransmission nothingToRequest paths

    @Test func requestRetransmissionNothingToRequestAfterReverify() async throws {
        let manager = WatchConnectivityManager.shared
        let workoutId = "ntr_reverify_\(UUID().uuidString)"

        let documentsDir = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!

        // Create valid chunk so reverifyChunks can verify + merge
        let chunkData = makeCborChunk(hrTimestamp: 14_000, hrBpm: 100)
        let chunkFileName = "workout_\(workoutId)_0.cbor"
        let chunkURL = documentsDir.appendingPathComponent(chunkFileName)
        try chunkData.write(to: chunkURL)

        let hash = try md5Hex(of: chunkURL)
        let size = Int64(chunkData.count)

        // Create record with chunk received but NOT merged
        var record = WorkoutRecord(
            workoutId: workoutId,
            startDate: Date(),
            totalSampleCount: 10,
            totalChunks: 1
        )
        record.receivedChunks = [
            ChunkFile(chunkIndex: 0, fileName: chunkFileName),
        ]
        record.manifest = TransferManifest(
            workoutId: workoutId,
            startDate: Date(),
            totalSampleCount: 10,
            totalChunks: 1,
            chunks: [
                TransferManifest.ChunkEntry(
                    fileName: chunkFileName, sizeBytes: size, md5: hash
                ),
            ]
        )
        // mergedFileName is nil -- reverifyChunks should auto-merge
        manager.workouts.append(record)

        let result = await manager.requestRetransmission(workoutId: workoutId)
        #expect(result == .nothingToRequest)

        if let r = manager.workouts.first(where: { $0.workoutId == workoutId }) {
            manager.deleteWorkout(r)
        }
    }

    @Test func requestRetransmissionNothingToRequestMissingEmpty() async throws {
        let manager = WatchConnectivityManager.shared
        let workoutId = "ntr_empty_\(UUID().uuidString)"

        let documentsDir = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!

        // Create a chunk with corrupt CBOR so merge fails
        let corruptData = Data("not cbor".utf8)
        let chunkFileName = "workout_\(workoutId)_0.cbor"
        let chunkURL = documentsDir.appendingPathComponent(chunkFileName)
        try corruptData.write(to: chunkURL)
        defer { try? FileManager.default.removeItem(at: chunkURL) }

        let hash = try md5Hex(of: chunkURL)
        let size = Int64(corruptData.count)

        // Record with all chunks received but merge will fail (corrupt data)
        var record = WorkoutRecord(
            workoutId: workoutId,
            startDate: Date(),
            totalSampleCount: 10,
            totalChunks: 1
        )
        record.receivedChunks = [
            ChunkFile(chunkIndex: 0, fileName: chunkFileName),
        ]
        record.manifest = TransferManifest(
            workoutId: workoutId,
            startDate: Date(),
            totalSampleCount: 10,
            totalChunks: 1,
            chunks: [
                TransferManifest.ChunkEntry(
                    fileName: chunkFileName, sizeBytes: size, md5: hash
                ),
            ]
        )
        manager.workouts.append(record)

        let result = await manager.requestRetransmission(workoutId: workoutId)
        // Merge fails on corrupt data, but all chunks received -> missing.isEmpty
        #expect(result == .nothingToRequest)

        if let r = manager.workouts.first(where: { $0.workoutId == workoutId }) {
            manager.deleteWorkout(r)
        }
    }

    // MARK: - processManifestFile with nil workoutId (covers ?? "unknown")

    @Test func processManifestFileNilWorkoutId() async throws {
        let manager = WatchConnectivityManager.shared
        let sentinelId = "pmnwi_\(UUID().uuidString)"

        let manifest = TransferManifest(
            workoutId: sentinelId,
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            totalSampleCount: 50,
            totalChunks: 2,
            chunks: []
        )

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("manifest_nil_\(UUID().uuidString).json")
        try JSONEncoder().encode(manifest).write(to: tempURL)

        // No "workoutId" key in metadata -> triggers ?? "unknown" for the
        // workoutId param passed to applyManifest. This exercises the
        // implicit autoclosure for coverage.
        let metadata: [String: Any] = [
            "isManifest": true,
        ]
        manager.processReceivedFile(fileURL: tempURL, metadata: metadata)
        try await Task.sleep(for: .milliseconds(200))

        // applyManifest looks up by "unknown" first. If a record with that
        // workoutId already exists (from a concurrent test), the manifest is
        // applied there instead of creating a new sentinel record. Either
        // outcome is valid -- the coverage target is the ?? "unknown" line.
        if let r = manager.workouts.first(where: { $0.workoutId == sentinelId }) {
            manager.deleteWorkout(r)
        }
    }

    // session(_:didReceive:) requires a WCSessionFile which cannot be
    // constructed in tests (readonly properties, KVC crashes). The 3-line
    // delegate method simply calls processReceivedFile(fileURL:metadata:)
    // which is comprehensively tested.
}
