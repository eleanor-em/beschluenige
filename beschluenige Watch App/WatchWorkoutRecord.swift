import Foundation

struct WatchWorkoutRecord: Identifiable, Codable, Sendable {
    let id: UUID
    let workoutId: String
    let startDate: Date
    let chunkCount: Int
    let totalSampleCount: Int
    var transferred: Bool
    var chunkFileNames: [String]
    var displayName: String { "workout_\(workoutId)" }
}
