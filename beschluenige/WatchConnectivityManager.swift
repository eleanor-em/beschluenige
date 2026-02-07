import Foundation
import WatchConnectivity
import os

@Observable
final class WatchConnectivityManager: NSObject, @unchecked Sendable {
    static let shared = WatchConnectivityManager()

    var workouts: [WorkoutRecord] = []

    private let session = WCSession.default
    private let logger = Logger(
        subsystem: "net.lnor.beschluenige",
        category: "Connectivity"
    )

    struct ChunkFile: Codable, Sendable {
        let chunkIndex: Int
        let fileName: String

        var fileURL: URL {
            FileManager.default.urls(
                for: .documentDirectory, in: .userDomainMask
            ).first!.appendingPathComponent(fileName)
        }
    }

    struct WorkoutRecord: Identifiable, Codable, Sendable {
        let id: UUID
        let workoutId: String
        let startDate: Date
        let totalSampleCount: Int
        let totalChunks: Int
        var receivedChunks: [ChunkFile]
        var mergedFileName: String?
        var fileSizeBytes: Int64

        var isComplete: Bool { receivedChunks.count == totalChunks }
        var fileSizeMB: Double { Double(fileSizeBytes) / 1_048_576.0 }

        var mergedFileURL: URL? {
            guard let name = mergedFileName else { return nil }
            return FileManager.default.urls(
                for: .documentDirectory, in: .userDomainMask
            ).first!.appendingPathComponent(name)
        }

        var displayName: String {
            let prefix = workoutId.hasPrefix("TEST_") ? "TEST_" : ""
            return "\(prefix)workout_\(workoutId)"
        }

        init(
            workoutId: String,
            startDate: Date,
            totalSampleCount: Int,
            totalChunks: Int
        ) {
            self.id = UUID()
            self.workoutId = workoutId
            self.startDate = startDate
            self.totalSampleCount = totalSampleCount
            self.totalChunks = totalChunks
            self.receivedChunks = []
            self.fileSizeBytes = 0
        }

        // Returns false if the chunk is a duplicate.
        mutating func processChunk(_ info: ChunkTransferInfo, logger: Logger) -> Bool {
            if receivedChunks.contains(where: { $0.chunkIndex == info.chunkIndex }) {
                logger.warning("Duplicate chunk \(info.chunkIndex) for workout \(info.workoutId)")
                return false
            }

            receivedChunks.append(
                ChunkFile(chunkIndex: info.chunkIndex, fileName: info.fileName)
            )
            fileSizeBytes += info.chunkSizeBytes

            if isComplete {
                mergeChunks(logger: logger)
            }
            return true
        }

        mutating func mergeChunks(logger: Logger) {
            let sorted = receivedChunks.sorted { $0.chunkIndex < $1.chunkIndex }

            // buckets[0]=HR, [1]=GPS, [2]=accel, [3]=DM
            var buckets: [[[Double]]] = [[], [], [], []]

            for chunk in sorted {
                guard let data = try? Data(contentsOf: chunk.fileURL) else {
                    logger.error("Failed to read chunk file: \(chunk.fileName)")
                    return
                }
                guard Self.decodeChunk(data, into: &buckets, fileName: chunk.fileName, logger: logger)
                else { return }
            }

            // Encode merged CBOR with indefinite-length per-sensor arrays
            var enc = CBOREncoder()
            enc.encodeMapHeader(count: 4)
            for (key, samples) in buckets.enumerated() {
                enc.encodeUInt(UInt64(key))
                enc.encodeIndefiniteArrayHeader()
                for sample in samples {
                    enc.encodeFloat64Array(sample)
                }
                enc.encodeBreak()
            }

            let merged = enc.data
            let mergedName = "workout_\(workoutId).cbor"
            let documentsDir = FileManager.default.urls(
                for: .documentDirectory, in: .userDomainMask
            ).first!
            let mergedURL = documentsDir.appendingPathComponent(mergedName)

            do {
                try merged.write(to: mergedURL)
                mergedFileName = mergedName
                fileSizeBytes = Int64(merged.count)

                for chunk in sorted {
                    do {
                        try FileManager.default.removeItem(at: chunk.fileURL)
                    } catch {
                        logger.error(
                            "Failed to remove chunk file \(chunk.fileName): \(error.localizedDescription)"
                        )
                    }
                }
                logger.info("Merged \(sorted.count) chunks into \(mergedName)")
            } catch {
                logger.error("Failed to write merged file: \(error.localizedDescription)")
            }
        }

        // Decode a CBOR chunk and append samples into the 4 per-sensor buckets.
        private static func decodeChunk(
            _ data: Data,
            into buckets: inout [[[Double]]],
            fileName: String,
            logger: Logger
        ) -> Bool {
            do {
                var dec = CBORDecoder(data: data)
                let mapCount = try dec.decodeMapHeader()
                for _ in 0..<mapCount {
                    let key = Int(try dec.decodeUInt())
                    guard let count = try dec.decodeArrayHeader() else {
                        logger.error("Unexpected indefinite array in chunk: \(fileName)")
                        return false
                    }
                    guard key >= 0, key < buckets.count else { continue }
                    for _ in 0..<count {
                        buckets[key].append(try dec.decodeFloat64Array())
                    }
                }
                return true
            } catch {
                logger.error(
                    "Failed to decode CBOR chunk \(fileName): \(error.localizedDescription)"
                )
                return false
            }
        }
    }

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        session.delegate = self
        session.activate()
        loadWorkouts()
    }

    func deleteWorkout(_ record: WorkoutRecord) {
        if let mergedURL = record.mergedFileURL {
            do {
                try FileManager.default.removeItem(at: mergedURL)
            } catch {
                logger.error(
                    "Failed to remove merged file \(mergedURL.lastPathComponent): \(error.localizedDescription)"
                )
            }
        }
        for chunk in record.receivedChunks {
            do {
                try FileManager.default.removeItem(at: chunk.fileURL)
            } catch {
                logger.error(
                    "Failed to remove chunk file \(chunk.fileName): \(error.localizedDescription)"
                )
            }
        }
        workouts.removeAll { $0.id == record.id }
        saveWorkouts()
    }

    func processChunk(_ info: ChunkTransferInfo) {
        var idx = workouts.firstIndex(where: { $0.workoutId == info.workoutId })

        if idx == nil {
            workouts.append(WorkoutRecord(
                workoutId: info.workoutId,
                startDate: info.startDate,
                totalSampleCount: info.totalSampleCount,
                totalChunks: info.totalChunks
            ))
            idx = workouts.count - 1
        }

        guard let idx else { return }
        guard workouts[idx].processChunk(info, logger: logger) else { return }

        saveWorkouts()
    }

    private func persistedFilesURL() -> URL {
        FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!.appendingPathComponent("workouts.json")
    }

    private func saveWorkouts() {
        do {
            let data = try JSONEncoder().encode(workouts)
            try data.write(to: persistedFilesURL(), options: .atomic)
        } catch {
            logger.error("Failed to persist workouts list: \(error.localizedDescription)")
        }
    }

    private func loadWorkouts() {
        let url = persistedFilesURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            workouts = try JSONDecoder().decode([WorkoutRecord].self, from: data)
        } catch {
            logger.error("Failed to load workouts list: \(error.localizedDescription)")
        }
    }
}

extension WatchConnectivityManager: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            logger.error("WCSession activation failed: \(error.localizedDescription)")
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        processReceivedFile(fileURL: file.fileURL, metadata: file.metadata)
    }

    nonisolated func processReceivedFile(
        fileURL: URL,
        metadata: [String: Any]?
    ) {
        let fileName = metadata?["fileName"] as? String ?? "unknown.cbor"
        let workoutId = metadata?["workoutId"] as? String ?? "unknown"
        let chunkIndex = metadata?["chunkIndex"] as? Int ?? 0
        let totalChunks = metadata?["totalChunks"] as? Int ?? 1
        let totalSampleCount = metadata?["totalSampleCount"] as? Int ?? 0
        let startInterval = metadata?["startDate"] as? TimeInterval ?? 0
        let chunkSizeBytes = metadata?["chunkSizeBytes"] as? Int64 ?? 0

        guard let documentsDir = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first else { return }

        let destinationURL = documentsDir.appendingPathComponent(fileName)

        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: fileURL, to: destinationURL)

            let startDate = Date(timeIntervalSince1970: startInterval)

            let info = ChunkTransferInfo(
                workoutId: workoutId,
                chunkIndex: chunkIndex,
                totalChunks: totalChunks,
                startDate: startDate,
                totalSampleCount: totalSampleCount,
                fileName: fileName,
                chunkSizeBytes: chunkSizeBytes
            )
            Task { @MainActor in
                self.processChunk(info)
            }
        } catch {
            logger.error("Failed to save received file: \(error.localizedDescription)")
        }
    }
}
