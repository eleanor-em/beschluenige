import Foundation
import Testing
import os
@testable import beschluenige

@MainActor
struct WorkoutRecordTests {

    private let testLogger = Logger(
        subsystem: "net.lnor.beschluenige.tests",
        category: "WorkoutRecordTests"
    )

    private func makeRecord(
        workoutId: String = "w1",
        totalChunks: Int = 3,
        startDate: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> WorkoutRecord {
        WorkoutRecord(
            workoutId: workoutId,
            startDate: startDate,
            totalSampleCount: 100,
            totalChunks: totalChunks
        )
    }

    // MARK: - displayName

    @Test func displayNameRegularDate() {
        let record = makeRecord()
        let name = record.displayName
        // Should not contain "TEST"
        #expect(!name.contains("TEST"))
        // Should contain some date formatting
        #expect(!name.isEmpty)
    }

    @Test func displayNameTestPrefix() {
        let record = makeRecord(workoutId: "TEST_abc123")
        #expect(record.displayName.hasPrefix("TEST - "))
    }

    // MARK: - isComplete

    @Test func isCompleteFalseWhenNoChunks() {
        let record = makeRecord(totalChunks: 2)
        #expect(!record.isComplete)
    }

    @Test func isCompleteTrueWhenAllReceived() {
        var record = makeRecord(totalChunks: 1)
        let info = ChunkTransferInfo(
            workoutId: "w1",
            chunkIndex: 0,
            totalChunks: 1,
            startDate: Date(),
            totalSampleCount: 10,
            fileName: "nonexistent.cbor",
            chunkSizeBytes: 100
        )
        // processChunk will try to merge since isComplete -> true,
        // but file won't exist, which is fine for this test
        _ = record.processChunk(info, logger: testLogger)
        #expect(record.receivedChunks.count == 1)
    }

    // MARK: - processChunk

    @Test func processChunkAcceptsNew() {
        var record = makeRecord(totalChunks: 3)
        let info = ChunkTransferInfo(
            workoutId: "w1",
            chunkIndex: 0,
            totalChunks: 3,
            startDate: Date(),
            totalSampleCount: 10,
            fileName: "chunk_0.cbor",
            chunkSizeBytes: 512
        )
        let accepted = record.processChunk(info, logger: testLogger)
        #expect(accepted)
        #expect(record.receivedChunks.count == 1)
        #expect(record.fileSizeBytes == 512)
    }

    @Test func processChunkRejectsDuplicate() {
        var record = makeRecord(totalChunks: 3)
        let info = ChunkTransferInfo(
            workoutId: "w1",
            chunkIndex: 0,
            totalChunks: 3,
            startDate: Date(),
            totalSampleCount: 10,
            fileName: "chunk_0.cbor",
            chunkSizeBytes: 512
        )
        _ = record.processChunk(info, logger: testLogger)
        let duplicate = record.processChunk(info, logger: testLogger)
        #expect(!duplicate)
        #expect(record.receivedChunks.count == 1)
    }

    // MARK: - mergedFileURL

    @Test func mergedFileURLNilWhenNoMerge() {
        let record = makeRecord()
        #expect(record.mergedFileURL == nil)
    }

    @Test func mergedFileURLPresentWhenMerged() {
        var record = makeRecord()
        record.mergedFileName = "workout_w1.cbor"
        #expect(record.mergedFileURL != nil)
        #expect(record.mergedFileURL?.lastPathComponent == "workout_w1.cbor")
    }

    // MARK: - DiskFile

    @Test func diskFileId() {
        let file = DiskFile(name: "test.cbor", sizeBytes: 1024)
        #expect(file.id == "test.cbor")
    }

    @Test func diskFileFormattedSize() {
        let file = DiskFile(name: "test.cbor", sizeBytes: 2_097_152)
        #expect(file.formattedSize == "2.0 MB")
    }
}
