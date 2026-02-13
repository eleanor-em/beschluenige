import Foundation

nonisolated struct TransferManifest: Codable, Sendable {
    struct ChunkEntry: Codable, Sendable {
        let fileName: String
        let sizeBytes: Int64
        let md5: String
    }

    let workoutId: String
    let startDate: Date
    let totalSampleCount: Int
    let totalChunks: Int
    let chunks: [ChunkEntry]
}
