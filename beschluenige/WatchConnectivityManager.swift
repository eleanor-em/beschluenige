import CryptoKit
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

    enum RetransmissionResult: Equatable {
        case alreadyMerged
        case nothingToRequest
        case accepted
        case denied
        case unreachable
        case notFound
        case error(String)
    }

    @ObservationIgnored
    var sendRetransmissionRequest: (RetransmissionRequest) async throws -> RetransmissionResponse = { request in
        let reply: [String: Any] = try await withCheckedThrowingContinuation { continuation in
            WCSession.default.sendMessage(request.toDictionary(), replyHandler: { reply in
                continuation.resume(returning: reply)
            }, errorHandler: { error in
                continuation.resume(throwing: error)
            })
        }
        guard let response = RetransmissionResponse(dictionary: reply) else {
            throw RetransmissionError.unexpectedReply
        }
        return response
    }

    @ObservationIgnored
    var isWatchReachable: () -> Bool = {
        WCSession.default.isReachable
    }

    enum RetransmissionError: Error {
        case unexpectedReply
    }

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
        var manifest: TransferManifest?
        var failedChunks: Set<Int> = []

        var isComplete: Bool { receivedChunks.count == totalChunks }

        var mergedFileURL: URL? {
            guard let name = mergedFileName else { return nil }
            return FileManager.default.urls(
                for: .documentDirectory, in: .userDomainMask
            ).first!.appendingPathComponent(name)
        }

        var displayName: String {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            let dateStr = formatter.string(from: startDate)
            if workoutId.hasPrefix("TEST_") {
                return "TEST - \(dateStr)"
            }
            return dateStr
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
            self.manifest = nil
            self.failedChunks = []
        }

        mutating func verifyReceivedChunks(against manifest: TransferManifest, logger: Logger) {
            var verified: [ChunkFile] = []
            for chunk in receivedChunks {
                guard chunk.chunkIndex < manifest.chunks.count else {
                    logger.error("Chunk index \(chunk.chunkIndex) out of manifest range")
                    failedChunks.insert(chunk.chunkIndex)
                    continue
                }
                let entry = manifest.chunks[chunk.chunkIndex]
                do {
                    let hash = try md5Hex(of: chunk.fileURL)
                    let attrs = try FileManager.default.attributesOfItem(atPath: chunk.fileURL.path)
                    // swiftlint:disable:next force_cast
                    let size = attrs[.size] as! Int64
                    if hash == entry.md5, size == entry.sizeBytes {
                        verified.append(chunk)
                    } else {
                        // swiftlint:disable:next line_length
                        logger.error("Chunk \(chunk.chunkIndex) verify failed md5:\(hash)/\(entry.md5) size:\(size)/\(entry.sizeBytes)")
                        failedChunks.insert(chunk.chunkIndex)
                        try? FileManager.default.removeItem(at: chunk.fileURL)
                    }
                } catch {
                    logger.error(
                        "Failed to verify chunk \(chunk.chunkIndex): \(error.localizedDescription)"
                    )
                    failedChunks.insert(chunk.chunkIndex)
                    try? FileManager.default.removeItem(at: chunk.fileURL)
                }
            }
            receivedChunks = verified
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

    func processChunkWithVerification(_ info: ChunkTransferInfo) {
        // Look up existing record
        let idx = workouts.firstIndex(where: { $0.workoutId == info.workoutId })

        if let idx, let manifest = workouts[idx].manifest {
            // Manifest present: verify before processing
            guard info.chunkIndex < manifest.chunks.count else {
                logger.error("Chunk index \(info.chunkIndex) out of manifest range")
                return
            }
            let entry = manifest.chunks[info.chunkIndex]
            guard let documentsDir = FileManager.default.urls(
                for: .documentDirectory, in: .userDomainMask
            ).first else { return }
            let chunkURL = documentsDir.appendingPathComponent(info.fileName)
            do {
                let hash = try md5Hex(of: chunkURL)
                let attrs = try FileManager.default.attributesOfItem(atPath: chunkURL.path)
                // swiftlint:disable:next force_cast
                let size = attrs[.size] as! Int64
                if hash != entry.md5 || size != entry.sizeBytes {
                    // swiftlint:disable:next line_length
                    logger.error("Chunk \(info.chunkIndex) verify failed md5:\(hash)/\(entry.md5) size:\(size)/\(entry.sizeBytes)")
                    try? FileManager.default.removeItem(at: chunkURL)
                    workouts[idx].failedChunks.insert(info.chunkIndex)
                    saveWorkouts()
                    return
                }
            } catch {
                logger.error("Failed to verify chunk \(info.chunkIndex): \(error.localizedDescription)")
                workouts[idx].failedChunks.insert(info.chunkIndex)
                saveWorkouts()
                return
            }
        }

        // Either no manifest yet or verification passed
        processChunk(info)
    }

    func applyManifest(_ manifest: TransferManifest, workoutId: String) {
        var idx = workouts.firstIndex(where: { $0.workoutId == workoutId })

        if idx == nil {
            workouts.append(WorkoutRecord(
                workoutId: manifest.workoutId,
                startDate: manifest.startDate,
                totalSampleCount: manifest.totalSampleCount,
                totalChunks: manifest.totalChunks
            ))
            idx = workouts.count - 1
        }

        guard let idx else { return }
        workouts[idx].manifest = manifest
        workouts[idx].verifyReceivedChunks(against: manifest, logger: logger)
        saveWorkouts()
    }

    func reverifyChunks(workoutId: String) {
        guard let idx = workouts.firstIndex(where: { $0.workoutId == workoutId }),
              let manifest = workouts[idx].manifest,
              workouts[idx].mergedFileName == nil
        else { return }
        workouts[idx].failedChunks = []
        workouts[idx].verifyReceivedChunks(against: manifest, logger: logger)
        if workouts[idx].isComplete {
            workouts[idx].mergeChunks(logger: logger)
        }
        saveWorkouts()
    }

    func requestRetransmission(workoutId: String) async -> RetransmissionResult {
        guard let record = workouts.first(where: { $0.workoutId == workoutId }) else {
            return .error("Workout not found")
        }

        if record.mergedFileName != nil {
            return .alreadyMerged
        }

        reverifyChunks(workoutId: workoutId)

        // Re-read the record (reverify may have auto-merged)
        guard let updated = workouts.first(where: { $0.workoutId == workoutId }) else {
            return .error("Workout not found after reverify")
        }

        if updated.mergedFileName != nil {
            return .nothingToRequest
        }

        let receivedIndices = Set(updated.receivedChunks.map(\.chunkIndex))
        let allIndices = Set(0..<updated.totalChunks)
        let missing = allIndices.subtracting(receivedIndices).union(updated.failedChunks)

        if missing.isEmpty {
            return .nothingToRequest
        }

        guard isWatchReachable() else {
            return .unreachable
        }

        let request = RetransmissionRequest(
            workoutId: workoutId,
            chunkIndices: missing.sorted(),
            needsManifest: updated.manifest == nil
        )

        do {
            let response = try await sendRetransmissionRequest(request)
            switch response {
            case .accepted: return .accepted
            case .denied: return .denied
            case .notFound: return .notFound
            }
        } catch {
            return .unreachable
        }
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
        if metadata?["isManifest"] as? Bool == true {
            processManifestFile(fileURL: fileURL, metadata: metadata)
            return
        }

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
                self.processChunkWithVerification(info)
            }
        } catch {
            logger.error("Failed to save received file: \(error.localizedDescription)")
        }
    }

    nonisolated private func processManifestFile(
        fileURL: URL,
        metadata: [String: Any]?
    ) {
        let workoutId = metadata?["workoutId"] as? String ?? "unknown"

        do {
            let data = try Data(contentsOf: fileURL)
            let manifest = try JSONDecoder().decode(TransferManifest.self, from: data)
            try? FileManager.default.removeItem(at: fileURL)

            Task { @MainActor in
                self.applyManifest(manifest, workoutId: workoutId)
            }
        } catch {
            logger.error("Failed to decode manifest for \(workoutId): \(error.localizedDescription)")
        }
    }
}
