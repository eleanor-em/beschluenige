import Foundation
import Testing
@testable import beschluenige_Watch_App

@MainActor
struct WorkoutListViewTests {

    private func makeTempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("test_\(UUID().uuidString).json")
    }

    private func makeRecord(
        workoutId: String = "s1",
        transferred: Bool = false,
        totalSampleCount: Int = 10
    ) -> WatchWorkoutRecord {
        WatchWorkoutRecord(
            id: UUID(),
            workoutId: workoutId,
            startDate: Date(),
            chunkCount: 1,
            totalSampleCount: totalSampleCount,
            fileSizeBytes: 1_048_576,
            transferred: transferred,
            chunkFileNames: ["chunk.cbor"]
        )
    }

    // MARK: - WorkoutListView body

    @Test func bodyRendersEmpty() {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = WorkoutStore(persistenceURL: url)
        let view = WorkoutListView(workoutStore: store)
        _ = view.body
    }

    @Test func bodyRendersWithWorkouts() {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = WorkoutStore(persistenceURL: url)
        store.registerWorkout(
            workoutId: "s1",
            startDate: Date(),
            chunkURLs: [],
            totalSampleCount: 10
        )
        store.markTransferred(workoutId: "s1")

        let view = WorkoutListView(workoutStore: store)
        _ = view.body
    }

    @Test func bodyRendersWithDeleteConfirmation() {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = WorkoutStore(persistenceURL: url)
        store.registerWorkout(
            workoutId: "s1",
            startDate: Date(),
            chunkURLs: [],
            totalSampleCount: 5
        )
        let view = WorkoutListView(
            workoutStore: store,
            initialShowDeleteConfirmation: true
        )
        _ = view.body
    }

    // MARK: - Extracted helpers

    @Test func deleteConfirmationMessageRenders() {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = WorkoutStore(persistenceURL: url)
        let view = WorkoutListView(workoutStore: store)
        _ = view.deleteConfirmationMessage
    }

    @Test func handleDeleteAllClearsStore() {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = WorkoutStore(persistenceURL: url)
        store.registerWorkout(
            workoutId: "d1",
            startDate: Date(),
            chunkURLs: [],
            totalSampleCount: 3
        )
        let view = WorkoutListView(workoutStore: store)
        view.handleDeleteAll()
        #expect(store.workouts.isEmpty)
    }

    @Test func requestDeleteConfirmation() {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = WorkoutStore(persistenceURL: url)
        let view = WorkoutListView(workoutStore: store)
        view.requestDeleteConfirmation()
    }

    @Test func handleCancelDelete() {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = WorkoutStore(persistenceURL: url)
        let view = WorkoutListView(workoutStore: store)
        view.handleCancelDelete()
    }

    // MARK: - WorkoutRowView

    @Test func rowRendersTransferred() {
        let view = WorkoutRowView(record: makeRecord(transferred: true))
        _ = view.body
    }

    @Test func rowRendersNotTransferred() {
        let view = WorkoutRowView(record: makeRecord(transferred: false))
        _ = view.body
    }

    @Test func rowRendersWithActiveProgress() {
        let progress = Progress(totalUnitCount: 10)
        progress.completedUnitCount = 3
        let view = WorkoutRowView(record: makeRecord(transferred: false), progress: progress)
        _ = view.body
    }

    @Test func rowRendersWithCompletedProgress() {
        let progress = Progress(totalUnitCount: 10)
        progress.completedUnitCount = 10
        let view = WorkoutRowView(record: makeRecord(transferred: true), progress: progress)
        _ = view.body
    }
}
