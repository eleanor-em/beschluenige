import Foundation

nonisolated struct ChunkFile: Codable, Sendable {
    let chunkIndex: Int
    let fileName: String

    var fileURL: URL {
        FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!.appendingPathComponent(fileName)
    }
}

nonisolated struct ChunkTransferInfo {
    let workoutId: String
    let chunkIndex: Int
    let totalChunks: Int
    let startDate: Date
    let totalSampleCount: Int
    var fileName: String = ""
    var chunkSizeBytes: Int64 = 0

    func metadata() -> [String: Any] {
        [
            "fileName": fileName,
            "workoutId": workoutId,
            "chunkIndex": chunkIndex,
            "totalChunks": totalChunks,
            "startDate": startDate.timeIntervalSince1970,
            "totalSampleCount": totalSampleCount,
            "chunkSizeBytes": chunkSizeBytes,
        ]
    }
}
