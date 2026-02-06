import Foundation

struct ChunkTransferInfo {
    let workoutId: String
    let chunkIndex: Int
    let totalChunks: Int
    let startDate: Date
    let totalSampleCount: Int
    var fileName: String = ""

    func metadata() -> [String: Any] {
        [
            "fileName": fileName,
            "workoutId": workoutId,
            "chunkIndex": chunkIndex,
            "totalChunks": totalChunks,
            "startDate": startDate.timeIntervalSince1970,
            "totalSampleCount": totalSampleCount,
        ]
    }
}
