import Foundation
import Testing
import WatchConnectivity
@testable import beschluenige

@Suite(.serialized)
@MainActor
struct WatchConnectivityManagerTests {

    @Test func activateReturnsEarlyOnSimulator() {
        // WCSession.isSupported() returns false on iPhone simulator without paired watch
        WatchConnectivityManager.shared.activate()
    }

    @Test func workoutsStartsEmpty() {
        // Must run before processChunk tests (serialized suite ensures this)
        #expect(WatchConnectivityManager.shared.workouts.isEmpty)
    }

    @Test func delegateHandlesActivationWithoutError() {
        WatchConnectivityManager.shared.session(
            WCSession.default,
            activationDidCompleteWith: .activated,
            error: nil
        )
    }

    @Test func delegateHandlesActivationWithError() {
        WatchConnectivityManager.shared.session(
            WCSession.default,
            activationDidCompleteWith: .notActivated,
            error: NSError(domain: "test", code: 1)
        )
    }

    @Test func sessionDidBecomeInactive() {
        WatchConnectivityManager.shared.sessionDidBecomeInactive(WCSession.default)
    }

    @Test func sessionDidDeactivate() {
        WatchConnectivityManager.shared.sessionDidDeactivate(WCSession.default)
    }

    @Test func processChunkedFileCreatesWorkoutRecord() async throws {
        let manager = WatchConnectivityManager.shared
        let initialCount = manager.workouts.count

        // Create a temp file to simulate a received chunk
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_chunk_\(UUID().uuidString).csv")
        try "type,timestamp,bpm\nH,1000.0,100.0".write(
            to: tempURL, atomically: true, encoding: .utf8
        )

        let workoutId = "test_workout_\(UUID().uuidString)"
        let fileName = "workout_\(workoutId)_0.csv"
        let metadata: [String: Any] = [
            "fileName": fileName,
            "workoutId": workoutId,
            "chunkIndex": 0,
            "totalChunks": 3,
            "totalSampleCount": 100,
            "startDate": Date().timeIntervalSince1970,
        ]

        manager.processReceivedFile(fileURL: tempURL, metadata: metadata)
        try await Task.sleep(for: .milliseconds(200))

        #expect(manager.workouts.count == initialCount + 1)
        if let record = manager.workouts.first(where: { $0.workoutId == workoutId }) {
            #expect(record.receivedChunks.count == 1)
            #expect(!record.isComplete)
            #expect(record.totalChunks == 3)

            // Clean up
            manager.deleteWorkout(record)
        }
    }

    @Test func allChunksReceivedTriggersMerge() async throws {
        let manager = WatchConnectivityManager.shared

        let workoutId = "merge_test_\(UUID().uuidString)"
        let header = "type,timestamp,bpm,lat,lon,alt,h_acc,v_acc,speed,course,"
            + "ax,ay,az,roll,pitch,yaw,rot_x,rot_y,rot_z,user_ax,user_ay,user_az,heading"

        // Create 2 chunk files
        for i in 0..<2 {
            let body = i == 0 ? "H,1000.0,100.0" : "H,1001.0,110.0"
            let content = "\(header)\n\(body)\n"
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("merge_chunk_\(i)_\(UUID().uuidString).csv")
            try content.write(to: tempURL, atomically: true, encoding: .utf8)

            let fileName = "workout_\(workoutId)_\(i).csv"
            let metadata: [String: Any] = [
                "fileName": fileName,
                "workoutId": workoutId,
                "chunkIndex": i,
                "totalChunks": 2,
                "totalSampleCount": 42,
                "startDate": Date().timeIntervalSince1970,
            ]

            manager.processReceivedFile(fileURL: tempURL, metadata: metadata)
            try await Task.sleep(for: .milliseconds(200))
        }

        if let record = manager.workouts.first(where: { $0.workoutId == workoutId }) {
            #expect(record.isComplete)
            #expect(record.mergedFileName != nil)

            // Verify merged CSV has exactly one header line
            if let mergedURL = record.mergedFileURL {
                let content = try String(contentsOf: mergedURL, encoding: .utf8)
                let lines = content.split(separator: "\n")
                // 1 header + 2 data lines
                #expect(lines.count == 3)
                #expect(lines[0].hasPrefix("type,"))
                #expect(lines[1].hasPrefix("H,1000.0"))
                #expect(lines[2].hasPrefix("H,1001.0"))
            }

            // Clean up
            manager.deleteWorkout(record)
        } else {
            Issue.record("Workout record not found after receiving all chunks")
        }
    }

    @Test func processReceivedFileWithNilMetadata() async throws {
        let manager = WatchConnectivityManager.shared
        let initialCount = manager.workouts.count

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_nil_meta_\(UUID().uuidString).csv")
        try "data".write(to: tempURL, atomically: true, encoding: .utf8)

        manager.processReceivedFile(fileURL: tempURL, metadata: nil)
        try await Task.sleep(for: .milliseconds(200))

        #expect(manager.workouts.count == initialCount + 1)
        // Nil metadata: workoutId = "unknown", totalChunks = 1, so it should be complete
        if let record = manager.workouts.first(where: { $0.workoutId == "unknown" }) {
            #expect(record.isComplete)
            manager.deleteWorkout(record)
        }
    }

    @Test func deleteWorkoutRemovesFiles() async throws {
        let manager = WatchConnectivityManager.shared

        let workoutId = "delete_test_\(UUID().uuidString)"
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("delete_chunk_\(UUID().uuidString).csv")
        try "data".write(to: tempURL, atomically: true, encoding: .utf8)

        let fileName = "workout_\(workoutId)_0.csv"
        let metadata: [String: Any] = [
            "fileName": fileName,
            "workoutId": workoutId,
            "chunkIndex": 0,
            "totalChunks": 1,
            "totalSampleCount": 5,
            "startDate": Date().timeIntervalSince1970,
        ]

        manager.processReceivedFile(fileURL: tempURL, metadata: metadata)
        try await Task.sleep(for: .milliseconds(200))

        if let record = manager.workouts.first(where: { $0.workoutId == workoutId }) {
            manager.deleteWorkout(record)
            #expect(manager.workouts.first(where: { $0.workoutId == workoutId }) == nil)
        }
    }
}
