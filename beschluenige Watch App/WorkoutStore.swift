import Foundation
import os

@Observable
final class WorkoutStore: @unchecked Sendable {
    var workouts: [WatchWorkoutRecord] = []
    var activeTransfers: [String: Progress] = [:]
    private var transferObservations: [String: NSKeyValueObservation] = [:]

    private let persistenceURL: URL
    private let logger = Logger(
        subsystem: "net.lnor.beschluenige.watchkitapp",
        category: "WorkoutStore"
    )

    init(persistenceURL: URL? = nil) {
        self.persistenceURL = persistenceURL ?? FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!.appendingPathComponent("watch_workouts.json")
        loadWorkouts()
    }

    func registerWorkout(
        workoutId: String,
        startDate: Date,
        chunkURLs: [URL],
        totalSampleCount: Int
    ) {
        guard !workouts.contains(where: { $0.workoutId == workoutId }) else { return }
        let fm = FileManager.default
        var totalBytes: Int64 = 0
        for url in chunkURLs {
            if let attrs = try? fm.attributesOfItem(atPath: url.path) {
                totalBytes += (attrs[.size] as? Int64) ?? 0
            }
        }
        let record = WatchWorkoutRecord(
            id: UUID(),
            workoutId: workoutId,
            startDate: startDate,
            chunkCount: chunkURLs.count,
            totalSampleCount: totalSampleCount,
            fileSizeBytes: totalBytes,
            transferred: false,
            chunkFileNames: chunkURLs.map { $0.lastPathComponent }
        )
        workouts.append(record)
        saveWorkouts()
    }

    func markTransferred(workoutId: String) {
        guard let index = workouts.firstIndex(where: { $0.workoutId == workoutId }) else {
            return
        }
        workouts[index].transferred = true
        saveWorkouts()
    }

    func storeTransferProgress(workoutId: String, progress: Progress) {
        activeTransfers[workoutId] = progress
        transferObservations[workoutId] = progress.observe(
            \.fractionCompleted, options: [.new]
        ) { [weak self] _, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                if progress.fractionCompleted >= 1.0 {
                    self.activeTransfers.removeValue(forKey: workoutId)
                    self.transferObservations.removeValue(forKey: workoutId)
                }
            }
        }
    }

    func deleteAll() {
        let fm = FileManager.default
        let documentsDir = fm.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!
        for record in workouts {
            for fileName in record.chunkFileNames {
                let url = documentsDir.appendingPathComponent(fileName)
                try? fm.removeItem(at: url)
            }
        }
        workouts.removeAll()
        saveWorkouts()
    }

    private func saveWorkouts() {
        do {
            let data = try JSONEncoder().encode(workouts)
            try data.write(to: persistenceURL, options: .atomic)
        } catch {
            logger.error("Failed to persist watch workouts: \(error.localizedDescription)")
        }
    }

    private func loadWorkouts() {
        guard FileManager.default.fileExists(atPath: persistenceURL.path) else { return }
        do {
            let data = try Data(contentsOf: persistenceURL)
            workouts = try JSONDecoder().decode([WatchWorkoutRecord].self, from: data)
        } catch {
            logger.error("Failed to load watch workouts: \(error.localizedDescription)")
        }
    }
}
