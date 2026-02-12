import CryptoKit
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

nonisolated func md5Hex(of url: URL) throws -> String {
    let data = try Data(contentsOf: url)
    let digest = Insecure.MD5.hash(data: data)
    return digest.map { String(format: "%02x", $0) }.joined()
}
