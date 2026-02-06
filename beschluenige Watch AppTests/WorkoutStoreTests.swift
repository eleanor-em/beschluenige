import Foundation
import Testing
@testable import beschluenige_Watch_App

struct WorkoutStoreTests {

    private func makeTempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("test_\(UUID().uuidString).json")
    }

    private func makeStore(url: URL? = nil) -> (WorkoutStore, URL) {
        let persistenceURL = url ?? makeTempURL()
        let store = WorkoutStore(persistenceURL: persistenceURL)
        return (store, persistenceURL)
    }

    @Test func registerWorkoutAddsRecord() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        store.registerWorkout(
            workoutId: "2026-02-06_183000",
            startDate: Date(timeIntervalSince1970: 1000),
            chunkURLs: [URL(fileURLWithPath: "/tmp/chunk_0.csv")],
            totalSampleCount: 42
        )

        #expect(store.workouts.count == 1)
        #expect(store.workouts[0].workoutId == "2026-02-06_183000")
        #expect(store.workouts[0].chunkCount == 1)
        #expect(store.workouts[0].totalSampleCount == 42)
        #expect(store.workouts[0].transferred == false)
        #expect(store.workouts[0].chunkFileNames == ["chunk_0.csv"])
        #expect(store.workouts[0].displayName == "workout_2026-02-06_183000")
    }

    @Test func duplicateWorkoutIdIsIgnored() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        store.registerWorkout(
            workoutId: "dup",
            startDate: Date(),
            chunkURLs: [URL(fileURLWithPath: "/tmp/a.csv")],
            totalSampleCount: 10
        )
        store.registerWorkout(
            workoutId: "dup",
            startDate: Date(),
            chunkURLs: [URL(fileURLWithPath: "/tmp/b.csv")],
            totalSampleCount: 20
        )

        #expect(store.workouts.count == 1)
        #expect(store.workouts[0].totalSampleCount == 10)
    }

    @Test func markTransferredSetsFlag() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        store.registerWorkout(
            workoutId: "s1",
            startDate: Date(),
            chunkURLs: [],
            totalSampleCount: 5
        )

        store.markTransferred(workoutId: "s1")

        #expect(store.workouts[0].transferred == true)
    }

    @Test func markTransferredIgnoresUnknownWorkout() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        store.markTransferred(workoutId: "nonexistent")

        #expect(store.workouts.isEmpty)
    }

    @Test func deleteAllRemovesFilesAndClears() throws {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        // Create a real chunk file in Documents
        let documentsDir = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!
        let chunkName = "test_deleteall_\(UUID().uuidString).csv"
        let chunkURL = documentsDir.appendingPathComponent(chunkName)
        try Data("test".utf8).write(to: chunkURL)

        store.registerWorkout(
            workoutId: "del1",
            startDate: Date(),
            chunkURLs: [chunkURL],
            totalSampleCount: 1
        )

        store.deleteAll()

        #expect(store.workouts.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: chunkURL.path))
    }

    @Test func persistenceRoundTrip() {
        let persistenceURL = makeTempURL()
        defer { try? FileManager.default.removeItem(at: persistenceURL) }

        let store1 = WorkoutStore(persistenceURL: persistenceURL)
        store1.registerWorkout(
            workoutId: "rt1",
            startDate: Date(timeIntervalSince1970: 5000),
            chunkURLs: [URL(fileURLWithPath: "/tmp/c.csv")],
            totalSampleCount: 99
        )
        store1.markTransferred(workoutId: "rt1")

        let store2 = WorkoutStore(persistenceURL: persistenceURL)

        #expect(store2.workouts.count == 1)
        #expect(store2.workouts[0].workoutId == "rt1")
        #expect(store2.workouts[0].transferred == true)
        #expect(store2.workouts[0].totalSampleCount == 99)
    }

    @Test func initWithNonexistentFileStartsEmpty() {
        let url = makeTempURL()
        let store = WorkoutStore(persistenceURL: url)
        #expect(store.workouts.isEmpty)
    }

    @Test func deleteAllOnEmptyStoreIsNoOp() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        store.deleteAll()
        #expect(store.workouts.isEmpty)
    }

    @Test func loadCorruptedFileStartsEmpty() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try Data("not valid json".utf8).write(to: url)
        let store = WorkoutStore(persistenceURL: url)
        #expect(store.workouts.isEmpty)
    }

    @Test func saveToUnwritablePathDoesNotCrash() {
        // Point persistence to a directory path (can't write a file over a directory)
        let dirURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_dir_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dirURL) }

        let store = WorkoutStore(persistenceURL: dirURL)
        store.registerWorkout(
            workoutId: "x",
            startDate: Date(),
            chunkURLs: [],
            totalSampleCount: 1
        )
        // Should not crash; the error is logged
        #expect(store.workouts.count == 1)
    }

    @Test func storeTransferProgressAddsToActiveTransfers() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        let progress = Progress(totalUnitCount: 10)
        store.storeTransferProgress(workoutId: "w1", progress: progress)

        #expect(store.activeTransfers["w1"] === progress)
    }

    @Test func storeTransferProgressCleansUpOnCompletion() async {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        let progress = Progress(totalUnitCount: 1)
        store.storeTransferProgress(workoutId: "w2", progress: progress)

        #expect(store.activeTransfers["w2"] != nil)

        progress.completedUnitCount = 1

        // KVO cleanup dispatches to main queue asynchronously
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(50))

        #expect(store.activeTransfers["w2"] == nil)
    }

    @Test func multipleWorkoutsRegistered() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        store.registerWorkout(
            workoutId: "a",
            startDate: Date(),
            chunkURLs: [],
            totalSampleCount: 1
        )
        store.registerWorkout(
            workoutId: "b",
            startDate: Date(),
            chunkURLs: [],
            totalSampleCount: 2
        )

        #expect(store.workouts.count == 2)
        #expect(store.workouts[0].workoutId == "a")
        #expect(store.workouts[1].workoutId == "b")
    }
}
