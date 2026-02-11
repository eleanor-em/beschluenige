import Foundation
import Testing
@testable import beschluenige

@MainActor
struct ChunkTransferInfoTests {

    @Test func metadataContainsAllFields() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        var info = ChunkTransferInfo(
            workoutId: "w123",
            chunkIndex: 2,
            totalChunks: 5,
            startDate: date,
            totalSampleCount: 42
        )
        info.fileName = "chunk_2.cbor"
        info.chunkSizeBytes = 1024

        let meta = info.metadata()
        #expect(meta["fileName"] as? String == "chunk_2.cbor")
        #expect(meta["workoutId"] as? String == "w123")
        #expect(meta["chunkIndex"] as? Int == 2)
        #expect(meta["totalChunks"] as? Int == 5)
        #expect(meta["startDate"] as? TimeInterval == date.timeIntervalSince1970)
        #expect(meta["totalSampleCount"] as? Int == 42)
        #expect(meta["chunkSizeBytes"] as? Int64 == 1024)
    }

    @Test func metadataDefaultValues() {
        let info = ChunkTransferInfo(
            workoutId: "w1",
            chunkIndex: 0,
            totalChunks: 1,
            startDate: Date(),
            totalSampleCount: 0
        )
        let meta = info.metadata()
        #expect(meta["fileName"] as? String == "")
        #expect(meta["chunkSizeBytes"] as? Int64 == 0)
    }
}

@MainActor
struct TransferManifestTests {

    @Test func codableRoundTrip() throws {
        let manifest = TransferManifest(
            workoutId: "w1",
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            totalSampleCount: 100,
            totalChunks: 2,
            chunks: [
                TransferManifest.ChunkEntry(
                    fileName: "chunk_0.cbor",
                    sizeBytes: 512,
                    md5: "abc123"
                ),
                TransferManifest.ChunkEntry(
                    fileName: "chunk_1.cbor",
                    sizeBytes: 256,
                    md5: "def456"
                ),
            ]
        )

        let data = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(TransferManifest.self, from: data)

        #expect(decoded.workoutId == "w1")
        #expect(decoded.totalChunks == 2)
        #expect(decoded.chunks.count == 2)
        #expect(decoded.chunks[0].fileName == "chunk_0.cbor")
        #expect(decoded.chunks[0].sizeBytes == 512)
        #expect(decoded.chunks[0].md5 == "abc123")
        #expect(decoded.chunks[1].fileName == "chunk_1.cbor")
    }

    @Test func md5HexComputesCorrectly() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("md5test_\(UUID().uuidString).bin")
        try Data("hello world".utf8).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let hash = try md5Hex(of: tempURL)
        // MD5 of "hello world" is 5eb63bbbe01eeed093cb22bb8f5acdc3
        #expect(hash == "5eb63bbbe01eeed093cb22bb8f5acdc3")
    }
}

@MainActor
struct RetransmissionRequestTests {

    @Test func initFromDictionary() {
        let dict: [String: Any] = [
            "type": "requestChunks",
            "workoutId": "w1",
            "chunkIndices": [0, 2, 4],
            "needsManifest": true,
        ]
        let req = RetransmissionRequest(dictionary: dict)
        #expect(req != nil)
        #expect(req?.workoutId == "w1")
        #expect(req?.chunkIndices == [0, 2, 4])
        #expect(req?.needsManifest == true)
    }

    @Test func initFromDictionaryMissingOptionals() {
        let dict: [String: Any] = [
            "type": "requestChunks",
            "workoutId": "w2",
        ]
        let req = RetransmissionRequest(dictionary: dict)
        #expect(req != nil)
        #expect(req?.chunkIndices == [])
        #expect(req?.needsManifest == false)
    }

    @Test func initFromDictionaryNilOnWrongType() {
        let dict: [String: Any] = [
            "type": "somethingElse",
            "workoutId": "w1",
        ]
        #expect(RetransmissionRequest(dictionary: dict) == nil)
    }

    @Test func initFromDictionaryNilOnMissingWorkoutId() {
        let dict: [String: Any] = [
            "type": "requestChunks",
        ]
        #expect(RetransmissionRequest(dictionary: dict) == nil)
    }

    @Test func toDictionaryRoundTrip() {
        let req = RetransmissionRequest(
            workoutId: "w1",
            chunkIndices: [1, 3],
            needsManifest: true
        )
        let dict = req.toDictionary()
        let decoded = RetransmissionRequest(dictionary: dict)
        #expect(decoded?.workoutId == "w1")
        #expect(decoded?.chunkIndices == [1, 3])
        #expect(decoded?.needsManifest == true)
    }
}

@MainActor
struct RetransmissionResponseTests {

    @Test func initFromDictionary() {
        #expect(RetransmissionResponse(dictionary: ["status": "accepted"]) == .accepted)
        #expect(RetransmissionResponse(dictionary: ["status": "denied"]) == .denied)
        #expect(RetransmissionResponse(dictionary: ["status": "notFound"]) == .notFound)
    }

    @Test func initFromDictionaryNilOnInvalid() {
        #expect(RetransmissionResponse(dictionary: ["status": "invalid"]) == nil)
        #expect(RetransmissionResponse(dictionary: [:]) == nil)
        #expect(RetransmissionResponse(dictionary: ["status": 42]) == nil)
    }

    @Test func toDictionaryRoundTrip() {
        for response in [
            RetransmissionResponse.accepted,
            .denied,
            .notFound,
        ] {
            let dict = response.toDictionary()
            let decoded = RetransmissionResponse(dictionary: dict)
            #expect(decoded == response)
        }
    }
}
