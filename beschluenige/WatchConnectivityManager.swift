import CryptoKit
import Foundation
import WatchConnectivity
import os

@Observable
final class WatchConnectivityManager: NSObject {
    static let shared = WatchConnectivityManager()

    var workouts: [WorkoutRecord] = []

    // Streaming decode state -- accessible to any iOS component.
    var decodedSummaries: [String: WorkoutSummary] = [:]
    var decodedTimeseries: [String: WorkoutTimeseries] = [:]
    var decodingProgress: [String: Double] = [:]
    var decodingErrors: [String: String] = [:]

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
    var sendRetransmissionRequest: (RetransmissionRequest) async throws -> RetransmissionResponse =
        defaultSendRetransmissionRequest

    nonisolated static func defaultSendRetransmissionRequest(
        _ request: RetransmissionRequest
    ) async throws -> RetransmissionResponse {
        #if targetEnvironment(simulator)
        throw RetransmissionError.unexpectedReply
        #else
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
        #endif
    }

    @ObservationIgnored
    var isWatchReachable: () -> Bool = {
        WCSession.default.isReachable
    }

    enum RetransmissionError: Error {
        case unexpectedReply
    }

    nonisolated struct ChunkFile: Codable, Sendable {
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
            return true
        }

        mutating func mergeChunks(logger: Logger) {
            guard let result = Self.performMerge(
                chunks: receivedChunks, workoutId: workoutId, logger: logger
            ) else { return }
            mergedFileName = result.mergedName
            fileSizeBytes = result.fileSize
        }

        /// Performs the actual merge work: reads chunk files, decodes CBOR,
        /// re-encodes into a single merged file, and cleans up chunk files.
        /// Returns nil on failure.
        nonisolated static func performMerge(
            chunks: [ChunkFile],
            workoutId: String,
            logger: Logger
        ) -> (mergedName: String, fileSize: Int64)? {
            let sorted = chunks.sorted { $0.chunkIndex < $1.chunkIndex }

            // buckets[0]=HR, [1]=GPS, [2]=accel, [3]=DM
            var buckets: [[[Double]]] = [[], [], [], []]

            for chunk in sorted {
                guard let data = try? Data(contentsOf: chunk.fileURL) else {
                    logger.error("Failed to read chunk file: \(chunk.fileName)")
                    return nil
                }
                guard decodeChunk(data, into: &buckets, fileName: chunk.fileName, logger: logger)
                else { return nil }
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
                for chunk in sorted {
                    try? FileManager.default.removeItem(at: chunk.fileURL)
                }
                logger.info("Merged chunks successfully")
                return (mergedName, Int64(merged.count))
            } catch {
                logger.error("Failed to write merged file")
                return nil
            }
        }

        // Decode a CBOR chunk and append samples into the 4 per-sensor buckets.
        nonisolated static func decodeChunk(
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
        let id = record.workoutId
        decodedSummaries.removeValue(forKey: id)
        decodedTimeseries.removeValue(forKey: id)
        decodingProgress.removeValue(forKey: id)
        decodingErrors.removeValue(forKey: id)
        workouts.removeAll { $0.id == record.id }
        saveWorkouts()
    }

    // MARK: - Streaming Workout Decoding

    /// Decodes a merged CBOR workout file incrementally, yielding partial
    /// summaries and progress updates so the UI stays responsive.
    func decodeWorkout(_ record: WorkoutRecord) {
        let workoutId = record.workoutId

        // Already decoded or currently decoding.
        guard decodedSummaries[workoutId] == nil else { return }
        guard decodingProgress[workoutId] == nil else { return }
        guard let url = record.mergedFileURL else { return }
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        decodingProgress[workoutId] = 0
        decodingErrors.removeValue(forKey: workoutId)

        Task.detached { [self] in
            do {
                let (summary, timeseries) = try await Self.streamDecode(
                    from: url
                ) { p, s, ts in
                    await MainActor.run {
                        self.decodingProgress[workoutId] = p
                        self.decodedSummaries[workoutId] = s
                        self.decodedTimeseries[workoutId] = ts
                    }
                }
                await MainActor.run {
                    self.decodedSummaries[workoutId] = summary
                    self.decodedTimeseries[workoutId] = timeseries
                    self.decodingProgress.removeValue(forKey: workoutId)
                }
            } catch {
                self.logger.error(
                    "Failed to decode workout \(workoutId): \(error.localizedDescription)"
                )
                await MainActor.run {
                    self.decodingErrors[workoutId] = "Could not read workout data"
                    self.decodingProgress.removeValue(forKey: workoutId)
                }
            }
        }
    }

    /// Reads and decodes the CBOR file, calling onProgress every 10 000
    /// samples and after each sensor type finishes.
    nonisolated static func streamDecode(
        from url: URL,
        onProgress: @Sendable (Double, WorkoutSummary, WorkoutTimeseries) async -> Void
    ) async throws -> (WorkoutSummary, WorkoutTimeseries) {
        let data = try Data(contentsOf: url)
        let totalBytes = data.count
        var dec = CBORDecoder(data: data)
        var acc = SummaryAccumulator()
        var tsAcc = TimeseriesAccumulator()

        let mapCount = try dec.decodeMapHeader()

        for _ in 0..<mapCount {
            let key = Int(try dec.decodeUInt())
            let definiteCount = try dec.decodeArrayHeader()
            var sampleCount = 0

            if let n = definiteCount {
                for _ in 0..<n {
                    let sample = try dec.decodeFloat64Array()
                    acc.process(key: key, sample: sample)
                    tsAcc.process(key: key, sample: sample)
                    sampleCount += 1
                    if sampleCount.isMultiple(of: 10000) {
                        await onProgress(
                            Double(dec.offset) / Double(totalBytes),
                            acc.makeSummary(),
                            tsAcc.makeTimeseries()
                        )
                    }
                }
            } else {
                while try !dec.isBreak() {
                    let sample = try dec.decodeFloat64Array()
                    acc.process(key: key, sample: sample)
                    tsAcc.process(key: key, sample: sample)
                    sampleCount += 1
                    if sampleCount.isMultiple(of: 10000) {
                        await onProgress(
                            Double(dec.offset) / Double(totalBytes),
                            acc.makeSummary(),
                            tsAcc.makeTimeseries()
                        )
                    }
                }
                try dec.decodeBreak()
            }
            await onProgress(
                Double(dec.offset) / Double(totalBytes),
                acc.makeSummary(),
                tsAcc.makeTimeseries()
            )
        }

        return (acc.makeSummary(), tsAcc.makeTimeseries())
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

        if workouts[idx].isComplete {
            mergeChunksAsync(workoutId: info.workoutId)
        }
    }

    func mergeChunksAsync(workoutId: String) {
        guard !mergingWorkouts.contains(workoutId) else { return }
        guard let idx = workouts.firstIndex(where: { $0.workoutId == workoutId }),
              workouts[idx].isComplete,
              workouts[idx].mergedFileName == nil
        else { return }

        mergingWorkouts.insert(workoutId)
        let chunks = workouts[idx].receivedChunks
        let log = logger

        Task.detached {
            let result = WorkoutRecord.performMerge(
                chunks: chunks, workoutId: workoutId, logger: log
            )
            await MainActor.run { [self] in
                self.mergingWorkouts.remove(workoutId)
                guard let result else { return }
                guard let i = self.workouts.firstIndex(where: { $0.workoutId == workoutId })
                else { return }
                self.workouts[i].mergedFileName = result.mergedName
                self.workouts[i].fileSizeBytes = result.fileSize
                self.saveWorkouts()
            }
        }
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

    @ObservationIgnored
    private var mergingWorkouts: Set<String> = []

    @ObservationIgnored
    var persistedFilesURLOverride: URL?

    func persistedFilesURL() -> URL {
        if let override = persistedFilesURLOverride { return override }
        return FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!.appendingPathComponent("workouts.json")
    }

    func saveWorkouts() {
        do {
            let data = try JSONEncoder().encode(workouts)
            try data.write(to: persistedFilesURL(), options: .atomic)
        } catch {
            logger.error("Failed to persist workouts list")
        }
    }

    func loadWorkouts() {
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
            logger.error("Failed to save received file")
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
            logger.error("Failed to decode manifest")
        }
    }
}

// MARK: - Workout Summary

nonisolated struct WorkoutSummary {
    let heartRateCount: Int
    let heartRateMin: Double?
    let heartRateMax: Double?
    let heartRateAvg: Double?
    let gpsCount: Int
    let maxSpeed: Double?
    let accelerometerCount: Int
    let deviceMotionCount: Int
    let firstTimestamp: Date?
    let lastTimestamp: Date?

    var duration: TimeInterval? {
        guard let first = firstTimestamp, let last = lastTimestamp else { return nil }
        let d = last.timeIntervalSince(first)
        return d > 0 ? d : nil
    }
}

nonisolated struct SummaryAccumulator {
    var hrCount = 0
    var hrMin = Double.greatestFiniteMagnitude
    var hrMax = -Double.greatestFiniteMagnitude
    var hrSum = 0.0
    var gpsCount = 0
    var maxSpeed = 0.0
    var accelCount = 0
    var dmCount = 0
    var firstTimestamp: Double?
    var lastTimestamp: Double?

    mutating func process(key: Int, sample: [Double]) {
        guard !sample.isEmpty else { return }
        let ts = sample[0]
        if firstTimestamp == nil || ts < firstTimestamp! { firstTimestamp = ts }
        if lastTimestamp == nil || ts > lastTimestamp! { lastTimestamp = ts }

        switch key {
        case 0: processHeartRate(sample)
        case 1: processGPS(sample)
        case 2: accelCount += 1
        case 3: dmCount += 1
        default: break
        }
    }

    private mutating func processHeartRate(_ sample: [Double]) {
        guard sample.count >= 2 else { return }
        let bpm = sample[1]
        hrCount += 1
        hrMin = min(hrMin, bpm)
        hrMax = max(hrMax, bpm)
        hrSum += bpm
    }

    private mutating func processGPS(_ sample: [Double]) {
        gpsCount += 1
        if sample.count >= 7 {
            let speed = sample[6]
            if speed >= 0 { maxSpeed = max(maxSpeed, speed) }
        }
    }

    func makeSummary() -> WorkoutSummary {
        WorkoutSummary(
            heartRateCount: hrCount,
            heartRateMin: hrCount > 0 ? hrMin : nil,
            heartRateMax: hrCount > 0 ? hrMax : nil,
            heartRateAvg: hrCount > 0 ? hrSum / Double(hrCount) : nil,
            gpsCount: gpsCount,
            maxSpeed: gpsCount > 0 ? maxSpeed : nil,
            accelerometerCount: accelCount,
            deviceMotionCount: dmCount,
            firstTimestamp: firstTimestamp.map { Date(timeIntervalSince1970: $0) },
            lastTimestamp: lastTimestamp.map { Date(timeIntervalSince1970: $0) },
            )
    }
}

// MARK: - Timeseries

struct WorkoutTimeseries: Sendable {
    let heartRate: [TimeseriesPoint]
    let speed: [TimeseriesPoint]
}

nonisolated struct TimeseriesAccumulator: Sendable {
    var hrPoints: [TimeseriesPoint] = []
    var speedPoints: [TimeseriesPoint] = []

    mutating func process(key: Int, sample: [Double]) {
        guard !sample.isEmpty else { return }
        let date = Date(timeIntervalSince1970: sample[0])

        switch key {
        case 0:
            if sample.count >= 2 {
                hrPoints.append(
                    TimeseriesPoint(id: hrPoints.count, date: date, value: sample[1])
                )
            }
        case 1:
            if sample.count >= 7, sample[6] >= 0 {
                speedPoints.append(
                    TimeseriesPoint(
                        id: speedPoints.count, date: date, value: sample[6] * 3.6
                    )
                )
            }
        default:
            break
        }
    }

    func makeTimeseries() -> WorkoutTimeseries {
        WorkoutTimeseries(heartRate: hrPoints, speed: speedPoints)
    }
}

// MARK: - Retransmission

extension WatchConnectivityManager {
    func requestRetransmission(workoutId: String) async -> RetransmissionResult {
        guard let record = workouts.first(where: { $0.workoutId == workoutId }) else {
            return .error("Workout not found")
        }

        if record.mergedFileName != nil {
            return .alreadyMerged
        }

        reverifyChunks(workoutId: workoutId)

        // Re-read the record (reverify may have auto-merged)
        let updated = workouts.first(where: { $0.workoutId == workoutId })!

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
}
