import Foundation

struct WatchSessionRecord: Identifiable, Codable, Sendable {
    let id: UUID
    let sessionId: String
    let startDate: Date
    let chunkCount: Int
    let totalSampleCount: Int
    var transferred: Bool
    var chunkFileNames: [String]
    var displayName: String { "session_\(sessionId)" }
}
