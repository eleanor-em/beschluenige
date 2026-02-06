import Foundation

enum TransferState: Sendable {
    case idle, sending, sent, savedLocally([URL]), failed(String)
}

struct ExportAction {
    var sendChunksViaPhone: ([URL], String, Date, Int) -> Bool = { chunkURLs, workoutId, startDate, totalSampleCount in
        PhoneConnectivityManager.shared.sendChunks(
            chunkURLs: chunkURLs,
            workoutId: workoutId,
            startDate: startDate,
            totalSampleCount: totalSampleCount
        )
    }
    var finalizeWorkout: (inout Workout) throws -> [URL] = { workout in
        try workout.finalizeChunks()
    }
    var registerWorkout: (String, Date, [URL], Int) -> Void = { _, _, _, _ in }
    var markTransferred: (String) -> Void = { _ in }

    func execute(workout: inout Workout) -> TransferState {
        let chunkURLs: [URL]
        do {
            chunkURLs = try finalizeWorkout(&workout)
        } catch {
            return .failed(error.localizedDescription)
        }
        guard !chunkURLs.isEmpty else { return .failed("No data to export") }

        registerWorkout(
            workout.workoutId, workout.startDate, chunkURLs, workout.cumulativeSampleCount
        )

        let success = sendChunksViaPhone(
            chunkURLs, workout.workoutId, workout.startDate, workout.cumulativeSampleCount
        )
        if success {
            markTransferred(workout.workoutId)
            return .sent
        }
        return .savedLocally(chunkURLs)
    }
}
