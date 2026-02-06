import Foundation
import Testing
@testable import beschluenige_Watch_App

struct ExportActionTests {

    @Test func executeReturnsSentOnSuccess() {
        var action = ExportAction()
        action.sendChunksViaPhone = { _, _, _, _ in Progress() }
        action.finalizeWorkout = { workout in
            workout.heartRateSamples = [
                HeartRateSample(timestamp: Date(), beatsPerMinute: 100),
            ]
            return try workout.finalizeChunks()
        }

        var workout = Workout(startDate: Date(timeIntervalSince1970: 2000000000))
        let result = action.execute(workout: &workout)
        if case .sent = result {
            // pass
        } else {
            Issue.record("Expected .sent, got \(result)")
        }

        // Clean up
        for url in workout.chunkURLs {
            try? FileManager.default.removeItem(at: url)
        }
    }

    @Test func executeReturnsSavedLocallyOnTransferFailure() throws {
        var action = ExportAction()
        action.sendChunksViaPhone = { _, _, _, _ in nil }
        action.finalizeWorkout = { workout in
            workout.heartRateSamples = [
                HeartRateSample(timestamp: Date(), beatsPerMinute: 100),
            ]
            return try workout.finalizeChunks()
        }

        var workout = Workout(startDate: Date(timeIntervalSince1970: 2000000001))
        let result = action.execute(workout: &workout)

        if case .savedLocally(let urls) = result {
            #expect(!urls.isEmpty)
            for url in urls {
                #expect(FileManager.default.fileExists(atPath: url.path))
                try FileManager.default.removeItem(at: url)
            }
        } else {
            Issue.record("Expected .savedLocally, got \(result)")
        }
    }

    @Test func executeReturnsFailedWhenFinalizeThrows() {
        var action = ExportAction()
        action.finalizeWorkout = { _ in
            throw NSError(domain: "test", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "disk full",
            ])
        }

        var workout = Workout(startDate: Date())
        let result = action.execute(workout: &workout)
        if case .failed(let message) = result {
            #expect(message == "disk full")
        } else {
            Issue.record("Expected .failed, got \(result)")
        }
    }

    @Test func executeReturnsFailedWhenNoChunks() {
        var action = ExportAction()
        action.finalizeWorkout = { _ in [] }

        var workout = Workout(startDate: Date())
        let result = action.execute(workout: &workout)
        if case .failed(let message) = result {
            #expect(message == "No data to export")
        } else {
            Issue.record("Expected .failed, got \(result)")
        }
    }

    @Test func executeCallsRegisterWorkoutAfterFinalize() {
        var registered = false
        var action = ExportAction()
        action.sendChunksViaPhone = { _, _, _, _ in Progress() }
        action.finalizeWorkout = { workout in
            workout.heartRateSamples = [
                HeartRateSample(timestamp: Date(), beatsPerMinute: 100),
            ]
            return try workout.finalizeChunks()
        }
        action.registerWorkout = { _, _, _, _ in registered = true }

        var workout = Workout(startDate: Date(timeIntervalSince1970: 2000000010))
        _ = action.execute(workout: &workout)

        #expect(registered)

        for url in workout.chunkURLs {
            try? FileManager.default.removeItem(at: url)
        }
    }

    @Test func executeCallsMarkTransferredOnSuccess() {
        var marked = false
        var action = ExportAction()
        action.sendChunksViaPhone = { _, _, _, _ in Progress() }
        action.finalizeWorkout = { workout in
            workout.heartRateSamples = [
                HeartRateSample(timestamp: Date(), beatsPerMinute: 100),
            ]
            return try workout.finalizeChunks()
        }
        action.markTransferred = { _ in marked = true }

        var workout = Workout(startDate: Date(timeIntervalSince1970: 2000000011))
        _ = action.execute(workout: &workout)

        #expect(marked)

        for url in workout.chunkURLs {
            try? FileManager.default.removeItem(at: url)
        }
    }

    @Test func executeDoesNotCallMarkTransferredOnFailure() {
        var marked = false
        var action = ExportAction()
        action.sendChunksViaPhone = { _, _, _, _ in nil }
        action.finalizeWorkout = { workout in
            workout.heartRateSamples = [
                HeartRateSample(timestamp: Date(), beatsPerMinute: 100),
            ]
            return try workout.finalizeChunks()
        }
        action.markTransferred = { _ in marked = true }

        var workout = Workout(startDate: Date(timeIntervalSince1970: 2000000012))
        _ = action.execute(workout: &workout)

        #expect(!marked)

        for url in workout.chunkURLs {
            try? FileManager.default.removeItem(at: url)
        }
    }

    @Test func executeDoesNotCallRegisterWhenFinalizeThrows() {
        var registered = false
        var action = ExportAction()
        action.finalizeWorkout = { _ in
            throw NSError(domain: "test", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "disk full",
            ])
        }
        action.registerWorkout = { _, _, _, _ in registered = true }

        var workout = Workout(startDate: Date())
        _ = action.execute(workout: &workout)

        #expect(!registered)
    }

    @Test func executeCallsStoreProgressOnSuccess() {
        var storedWorkoutId: String?
        var storedProgress: Progress?
        var action = ExportAction()
        action.sendChunksViaPhone = { _, _, _, _ in Progress() }
        action.finalizeWorkout = { workout in
            workout.heartRateSamples = [
                HeartRateSample(timestamp: Date(), beatsPerMinute: 100),
            ]
            return try workout.finalizeChunks()
        }
        action.storeProgress = { workoutId, progress in
            storedWorkoutId = workoutId
            storedProgress = progress
        }

        var workout = Workout(startDate: Date(timeIntervalSince1970: 2000000013))
        _ = action.execute(workout: &workout)

        #expect(storedWorkoutId == workout.workoutId)
        #expect(storedProgress != nil)

        for url in workout.chunkURLs {
            try? FileManager.default.removeItem(at: url)
        }
    }

    @Test func executeDoesNotCallStoreProgressOnFailure() {
        var storeCalled = false
        var action = ExportAction()
        action.sendChunksViaPhone = { _, _, _, _ in nil }
        action.finalizeWorkout = { workout in
            workout.heartRateSamples = [
                HeartRateSample(timestamp: Date(), beatsPerMinute: 100),
            ]
            return try workout.finalizeChunks()
        }
        action.storeProgress = { _, _ in storeCalled = true }

        var workout = Workout(startDate: Date(timeIntervalSince1970: 2000000014))
        _ = action.execute(workout: &workout)

        #expect(!storeCalled)

        for url in workout.chunkURLs {
            try? FileManager.default.removeItem(at: url)
        }
    }

    @Test func executeUsesDefaultPhoneConnectivityOnSimulator() throws {
        // Default sendChunksViaPhone uses PhoneConnectivityManager.shared
        // On simulator, WCSession is not activated, so this falls back to local save
        #if !targetEnvironment(simulator)
        // On a real watch WCSession may be activated, so .sent is valid
        return
        #else
        var action = ExportAction()
        action.finalizeWorkout = { workout in
            workout.heartRateSamples = [
                HeartRateSample(timestamp: Date(), beatsPerMinute: 100),
            ]
            return try workout.finalizeChunks()
        }
        var workout = Workout(startDate: Date(timeIntervalSince1970: 2000000002))
        let result = action.execute(workout: &workout)

        // Should not be .sent (WCSession not activated on simulator)
        if case .sent = result {
            Issue.record("Expected fallback, not .sent on simulator")
        }

        // Clean up
        for url in workout.chunkURLs {
            try? FileManager.default.removeItem(at: url)
        }
        #endif
    }
}
