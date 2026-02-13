import Foundation
import Testing
import WatchConnectivity
@testable import beschluenige

// MARK: - Verification, Manifest, and Decode Tests

@Suite(.serialized)
@MainActor
struct VerificationTests {

    private let testLogger = AppLogger(category: "test")

    // MARK: - verifyReceivedChunks

    @Test func verifyReceivedChunksMatchingMD5() throws {
        let documentsDir = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!

        let workoutId = "verify_pass_\(UUID().uuidString)"
        let chunkData = Data("test chunk data".utf8)
        let chunkFileName = "chunk_\(workoutId)_0.cbor"
        let chunkURL = documentsDir.appendingPathComponent(chunkFileName)
        try chunkData.write(to: chunkURL)
        defer { try? FileManager.default.removeItem(at: chunkURL) }

        let hash = try md5Hex(of: chunkURL)
        let size = Int64(chunkData.count)

        var record = WorkoutRecord(
            workoutId: workoutId,
            startDate: Date(),
            totalSampleCount: 10,
            totalChunks: 1
        )
        record.receivedChunks = [
            ChunkFile(chunkIndex: 0, fileName: chunkFileName),
        ]

        let manifest = TransferManifest(
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
        record.verifyReceivedChunks(against: manifest, logger: testLogger)

        #expect(record.receivedChunks.count == 1)
        #expect(record.failedChunks.isEmpty)
    }

    @Test func verifyReceivedChunksMismatchingMD5() throws {
        let documentsDir = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!

        let workoutId = "verify_fail_\(UUID().uuidString)"
        let chunkData = Data("test chunk data".utf8)
        let chunkFileName = "chunk_\(workoutId)_0.cbor"
        let chunkURL = documentsDir.appendingPathComponent(chunkFileName)
        try chunkData.write(to: chunkURL)
        defer { try? FileManager.default.removeItem(at: chunkURL) }

        var record = WorkoutRecord(
            workoutId: workoutId,
            startDate: Date(),
            totalSampleCount: 10,
            totalChunks: 1
        )
        record.receivedChunks = [
            ChunkFile(chunkIndex: 0, fileName: chunkFileName),
        ]

        let manifest = TransferManifest(
            workoutId: workoutId,
            startDate: Date(),
            totalSampleCount: 10,
            totalChunks: 1,
            chunks: [
                TransferManifest.ChunkEntry(
                    fileName: chunkFileName, sizeBytes: 999, md5: "wronghash"
                ),
            ]
        )
        record.verifyReceivedChunks(against: manifest, logger: testLogger)

        #expect(record.receivedChunks.isEmpty)
        #expect(record.failedChunks.contains(0))
    }

    @Test func verifyReceivedChunksIndexOutOfRange() {
        let workoutId = "verify_oor_\(UUID().uuidString)"
        var record = WorkoutRecord(
            workoutId: workoutId,
            startDate: Date(),
            totalSampleCount: 10,
            totalChunks: 2
        )
        record.receivedChunks = [
            ChunkFile(chunkIndex: 5, fileName: "missing.cbor"),
        ]

        let manifest = TransferManifest(
            workoutId: workoutId,
            startDate: Date(),
            totalSampleCount: 10,
            totalChunks: 1,
            chunks: [
                TransferManifest.ChunkEntry(
                    fileName: "c0.cbor", sizeBytes: 100, md5: "abc"
                ),
            ]
        )
        record.verifyReceivedChunks(against: manifest, logger: testLogger)

        #expect(record.receivedChunks.isEmpty)
        #expect(record.failedChunks.contains(5))
    }

    @Test func verifyReceivedChunksFileNotFound() {
        let workoutId = "verify_nofile_\(UUID().uuidString)"
        var record = WorkoutRecord(
            workoutId: workoutId,
            startDate: Date(),
            totalSampleCount: 10,
            totalChunks: 1
        )
        record.receivedChunks = [
            ChunkFile(
                chunkIndex: 0, fileName: "nonexistent_\(UUID().uuidString).cbor"
            ),
        ]

        let manifest = TransferManifest(
            workoutId: workoutId,
            startDate: Date(),
            totalSampleCount: 10,
            totalChunks: 1,
            chunks: [
                TransferManifest.ChunkEntry(
                    fileName: "c0.cbor", sizeBytes: 100, md5: "abc"
                ),
            ]
        )
        record.verifyReceivedChunks(against: manifest, logger: testLogger)

        #expect(record.receivedChunks.isEmpty)
        #expect(record.failedChunks.contains(0))
    }

    // MARK: - processChunkWithVerification

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

    @Test func processChunkWithVerificationPasses() throws {
        let manager = WatchConnectivityManager.shared
        let workoutId = "pcwv_pass_\(UUID().uuidString)"

        let documentsDir = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!

        let chunkData = makeCborChunk(hrTimestamp: 9000, hrBpm: 90)
        let chunkFileName = "workout_\(workoutId)_0.cbor"
        let chunkURL = documentsDir.appendingPathComponent(chunkFileName)
        try chunkData.write(to: chunkURL)

        let hash = try md5Hex(of: chunkURL)
        let size = Int64(chunkData.count)

        var record = WorkoutRecord(
            workoutId: workoutId,
            startDate: Date(),
            totalSampleCount: 10,
            totalChunks: 2
        )
        record.manifest = TransferManifest(
            workoutId: workoutId,
            startDate: Date(),
            totalSampleCount: 10,
            totalChunks: 2,
            chunks: [
                TransferManifest.ChunkEntry(
                    fileName: chunkFileName, sizeBytes: size, md5: hash
                ),
                TransferManifest.ChunkEntry(
                    fileName: "chunk_1.cbor", sizeBytes: 100, md5: "abc"
                ),
            ]
        )
        manager.workouts.append(record)

        let info = ChunkTransferInfo(
            workoutId: workoutId,
            chunkIndex: 0,
            totalChunks: 2,
            startDate: Date(),
            totalSampleCount: 10,
            fileName: chunkFileName,
            chunkSizeBytes: size
        )
        manager.processChunkWithVerification(info)

        let updated = manager.workouts.first { $0.workoutId == workoutId }
        #expect(updated?.receivedChunks.count == 1)
        #expect(updated?.failedChunks.isEmpty == true)

        if let r = updated { manager.deleteWorkout(r) }
    }

    @Test func processChunkWithVerificationFails() throws {
        let manager = WatchConnectivityManager.shared
        let workoutId = "pcwv_fail_\(UUID().uuidString)"

        let documentsDir = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!

        let chunkData = makeCborChunk(hrTimestamp: 9100, hrBpm: 91)
        let chunkFileName = "workout_\(workoutId)_0.cbor"
        let chunkURL = documentsDir.appendingPathComponent(chunkFileName)
        try chunkData.write(to: chunkURL)
        defer { try? FileManager.default.removeItem(at: chunkURL) }

        var record = WorkoutRecord(
            workoutId: workoutId,
            startDate: Date(),
            totalSampleCount: 10,
            totalChunks: 2
        )
        record.manifest = TransferManifest(
            workoutId: workoutId,
            startDate: Date(),
            totalSampleCount: 10,
            totalChunks: 2,
            chunks: [
                TransferManifest.ChunkEntry(
                    fileName: chunkFileName, sizeBytes: 999, md5: "wronghash"
                ),
                TransferManifest.ChunkEntry(
                    fileName: "chunk_1.cbor", sizeBytes: 100, md5: "abc"
                ),
            ]
        )
        manager.workouts.append(record)

        let info = ChunkTransferInfo(
            workoutId: workoutId,
            chunkIndex: 0,
            totalChunks: 2,
            startDate: Date(),
            totalSampleCount: 10,
            fileName: chunkFileName,
            chunkSizeBytes: Int64(chunkData.count)
        )
        manager.processChunkWithVerification(info)

        let updated = manager.workouts.first { $0.workoutId == workoutId }
        #expect(updated?.receivedChunks.isEmpty == true)
        #expect(updated?.failedChunks.contains(0) == true)

        if let r = updated { manager.deleteWorkout(r) }
    }

    @Test func processChunkWithVerificationOutOfRange() {
        let manager = WatchConnectivityManager.shared
        let workoutId = "pcwv_oor_\(UUID().uuidString)"

        var record = WorkoutRecord(
            workoutId: workoutId,
            startDate: Date(),
            totalSampleCount: 10,
            totalChunks: 2
        )
        record.manifest = TransferManifest(
            workoutId: workoutId,
            startDate: Date(),
            totalSampleCount: 10,
            totalChunks: 1,
            chunks: [
                TransferManifest.ChunkEntry(
                    fileName: "chunk_0.cbor", sizeBytes: 100, md5: "abc"
                ),
            ]
        )
        manager.workouts.append(record)

        let info = ChunkTransferInfo(
            workoutId: workoutId,
            chunkIndex: 5,
            totalChunks: 2,
            startDate: Date(),
            totalSampleCount: 10,
            fileName: "chunk_5.cbor",
            chunkSizeBytes: 100
        )
        manager.processChunkWithVerification(info)

        let updated = manager.workouts.first { $0.workoutId == workoutId }
        #expect(updated?.receivedChunks.isEmpty == true)

        if let r = updated { manager.deleteWorkout(r) }
    }

    // MARK: - applyManifest

    @Test func applyManifestCreatesNewRecord() {
        let manager = WatchConnectivityManager.shared
        let workoutId = "apply_new_\(UUID().uuidString)"

        let manifest = TransferManifest(
            workoutId: workoutId,
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            totalSampleCount: 50,
            totalChunks: 3,
            chunks: []
        )
        manager.applyManifest(manifest, workoutId: workoutId)

        let record = manager.workouts.first { $0.workoutId == workoutId }
        #expect(record != nil)
        #expect(record?.manifest != nil)
        #expect(record?.totalChunks == 3)

        if let r = record { manager.deleteWorkout(r) }
    }

    @Test func applyManifestToExistingRecord() throws {
        let manager = WatchConnectivityManager.shared
        let workoutId = "apply_exist_\(UUID().uuidString)"

        let documentsDir = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!

        var record = WorkoutRecord(
            workoutId: workoutId,
            startDate: Date(),
            totalSampleCount: 10,
            totalChunks: 2
        )
        let chunkData = Data("chunk data".utf8)
        let chunkFileName = "chunk_\(workoutId)_0.cbor"
        let chunkURL = documentsDir.appendingPathComponent(chunkFileName)
        try chunkData.write(to: chunkURL)
        defer { try? FileManager.default.removeItem(at: chunkURL) }

        record.receivedChunks = [
            ChunkFile(chunkIndex: 0, fileName: chunkFileName),
        ]
        manager.workouts.append(record)

        let hash = try md5Hex(of: chunkURL)
        let size = Int64(chunkData.count)

        let manifest = TransferManifest(
            workoutId: workoutId,
            startDate: Date(),
            totalSampleCount: 10,
            totalChunks: 2,
            chunks: [
                TransferManifest.ChunkEntry(
                    fileName: chunkFileName, sizeBytes: size, md5: hash
                ),
                TransferManifest.ChunkEntry(
                    fileName: "chunk_1.cbor", sizeBytes: 100, md5: "abc"
                ),
            ]
        )
        manager.applyManifest(manifest, workoutId: workoutId)

        let updated = manager.workouts.first { $0.workoutId == workoutId }
        #expect(updated?.manifest != nil)
        #expect(updated?.receivedChunks.count == 1)
        #expect(updated?.failedChunks.isEmpty == true)

        if let r = updated { manager.deleteWorkout(r) }
    }

    // MARK: - reverifyChunks

    @Test func reverifyChunksAutoMerges() throws {
        let manager = WatchConnectivityManager.shared
        let workoutId = "reverify_\(UUID().uuidString)"

        let documentsDir = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!

        let chunkData = makeCborChunk(hrTimestamp: 10_000, hrBpm: 100)
        let chunkFileName = "workout_\(workoutId)_0.cbor"
        let chunkURL = documentsDir.appendingPathComponent(chunkFileName)
        try chunkData.write(to: chunkURL)
        defer { try? FileManager.default.removeItem(at: chunkURL) }

        let hash = try md5Hex(of: chunkURL)
        let size = Int64(chunkData.count)

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
        record.failedChunks = [0]
        manager.workouts.append(record)

        manager.reverifyChunks(workoutId: workoutId)

        let updated = manager.workouts.first { $0.workoutId == workoutId }
        #expect(updated?.mergedFileName != nil)

        if let r = updated { manager.deleteWorkout(r) }
    }

    @Test func reverifyChunksSkipsAlreadyMerged() {
        let manager = WatchConnectivityManager.shared
        let workoutId = "reverify_merged_\(UUID().uuidString)"

        var record = WorkoutRecord(
            workoutId: workoutId,
            startDate: Date(),
            totalSampleCount: 10,
            totalChunks: 1
        )
        record.mergedFileName = "already_merged.cbor"
        record.manifest = TransferManifest(
            workoutId: workoutId,
            startDate: Date(),
            totalSampleCount: 10,
            totalChunks: 1,
            chunks: []
        )
        manager.workouts.append(record)

        manager.reverifyChunks(workoutId: workoutId)

        let updated = manager.workouts.first { $0.workoutId == workoutId }
        #expect(updated?.mergedFileName == "already_merged.cbor")

        if let r = updated { manager.deleteWorkout(r) }
    }

    @Test func reverifyChunksSkipsNoManifest() {
        let manager = WatchConnectivityManager.shared
        let workoutId = "reverify_noman_\(UUID().uuidString)"

        let record = WorkoutRecord(
            workoutId: workoutId,
            startDate: Date(),
            totalSampleCount: 10,
            totalChunks: 1
        )
        manager.workouts.append(record)

        manager.reverifyChunks(workoutId: workoutId)

        let updated = manager.workouts.first { $0.workoutId == workoutId }
        #expect(updated?.mergedFileName == nil)

        if let r = updated { manager.deleteWorkout(r) }
    }

    @Test func processChunkWithVerificationCatchBlock() {
        let manager = WatchConnectivityManager.shared
        let workoutId = "pcwv_catch_\(UUID().uuidString)"

        var record = WorkoutRecord(
            workoutId: workoutId,
            startDate: Date(),
            totalSampleCount: 10,
            totalChunks: 2
        )
        record.manifest = TransferManifest(
            workoutId: workoutId,
            startDate: Date(),
            totalSampleCount: 10,
            totalChunks: 2,
            chunks: [
                TransferManifest.ChunkEntry(
                    fileName: "chunk_0.cbor", sizeBytes: 100, md5: "abc"
                ),
                TransferManifest.ChunkEntry(
                    fileName: "chunk_1.cbor", sizeBytes: 100, md5: "def"
                ),
            ]
        )
        manager.workouts.append(record)

        // File does not exist in documents dir, so md5Hex will throw
        let info = ChunkTransferInfo(
            workoutId: workoutId,
            chunkIndex: 0,
            totalChunks: 2,
            startDate: Date(),
            totalSampleCount: 10,
            fileName: "nonexistent_\(UUID().uuidString).cbor",
            chunkSizeBytes: 100
        )
        manager.processChunkWithVerification(info)

        let updated = manager.workouts.first { $0.workoutId == workoutId }
        #expect(updated?.failedChunks.contains(0) == true)

        if let r = updated { manager.deleteWorkout(r) }
    }

    // MARK: - processManifestFile

    @Test func processManifestFile() async throws {
        let manager = WatchConnectivityManager.shared
        let workoutId = "manifest_\(UUID().uuidString)"

        let manifest = TransferManifest(
            workoutId: workoutId,
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            totalSampleCount: 50,
            totalChunks: 2,
            chunks: []
        )

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("manifest_\(UUID().uuidString).json")
        try JSONEncoder().encode(manifest).write(to: tempURL)

        let metadata: [String: Any] = [
            "isManifest": true,
            "workoutId": workoutId,
        ]
        manager.processReceivedFile(fileURL: tempURL, metadata: metadata)
        try await Task.sleep(for: .milliseconds(200))

        let record = manager.workouts.first { $0.workoutId == workoutId }
        #expect(record?.manifest != nil)
        #expect(record?.totalChunks == 2)

        if let r = record { manager.deleteWorkout(r) }
    }

    @Test func processManifestFileCorruptData() async throws {
        let manager = WatchConnectivityManager.shared
        let workoutId = "corrupt_\(UUID().uuidString)"

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("bad_manifest_\(UUID().uuidString).json")
        try Data("not json".utf8).write(to: tempURL)

        let metadata: [String: Any] = [
            "isManifest": true,
            "workoutId": workoutId,
        ]
        manager.processReceivedFile(fileURL: tempURL, metadata: metadata)
        try await Task.sleep(for: .milliseconds(200))

        // Corrupt manifest should not create a record for this workoutId
        let record = manager.workouts.first { $0.workoutId == workoutId }
        #expect(record == nil)
    }

}
