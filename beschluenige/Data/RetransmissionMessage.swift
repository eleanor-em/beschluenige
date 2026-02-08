import Foundation

struct RetransmissionRequest {
    let workoutId: String
    let chunkIndices: [Int]
    let needsManifest: Bool

    func toDictionary() -> [String: Any] {
        [
            "type": "requestChunks",
            "workoutId": workoutId,
            "chunkIndices": chunkIndices,
            "needsManifest": needsManifest,
        ]
    }

    init(workoutId: String, chunkIndices: [Int], needsManifest: Bool) {
        self.workoutId = workoutId
        self.chunkIndices = chunkIndices
        self.needsManifest = needsManifest
    }

    init?(dictionary: [String: Any]) {
        guard dictionary["type"] as? String == "requestChunks",
              let workoutId = dictionary["workoutId"] as? String
        else { return nil }
        self.workoutId = workoutId
        self.chunkIndices = dictionary["chunkIndices"] as? [Int] ?? []
        self.needsManifest = dictionary["needsManifest"] as? Bool ?? false
    }
}

enum RetransmissionResponse: String {
    case accepted
    case denied
    case notFound

    func toDictionary() -> [String: Any] {
        ["status": rawValue]
    }

    init?(dictionary: [String: Any]) {
        guard let status = dictionary["status"] as? String,
              let value = RetransmissionResponse(rawValue: status)
        else { return nil }
        self = value
    }
}
