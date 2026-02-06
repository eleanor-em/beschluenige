import Foundation
import WatchConnectivity
import os

@Observable
final class WatchConnectivityManager: NSObject, @unchecked Sendable {
    static let shared = WatchConnectivityManager()

    var sessions: [SessionRecord] = []

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

    struct SessionRecord: Identifiable, Codable, Sendable {
        let id: UUID
        let sessionId: String
        let startDate: Date
        let totalSampleCount: Int
        let totalChunks: Int
        var receivedChunks: [ChunkFile]
        var mergedFileName: String?

        var isComplete: Bool { receivedChunks.count == totalChunks }

        var mergedFileURL: URL? {
            guard let name = mergedFileName else { return nil }
            return FileManager.default.urls(
                for: .documentDirectory, in: .userDomainMask
            ).first!.appendingPathComponent(name)
        }

        var displayName: String {
            let prefix = sessionId.hasPrefix("TEST_") ? "TEST_" : ""
            return "\(prefix)session_\(sessionId)"
        }

        init(
            sessionId: String,
            startDate: Date,
            totalSampleCount: Int,
            totalChunks: Int
        ) {
            self.id = UUID()
            self.sessionId = sessionId
            self.startDate = startDate
            self.totalSampleCount = totalSampleCount
            self.totalChunks = totalChunks
            self.receivedChunks = []
        }
    }

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        session.delegate = self
        session.activate()
        loadSessions()
    }

    func deleteSession(_ record: SessionRecord) {
        if let mergedURL = record.mergedFileURL {
            try? FileManager.default.removeItem(at: mergedURL)
        }
        for chunk in record.receivedChunks {
            try? FileManager.default.removeItem(at: chunk.fileURL)
        }
        sessions.removeAll { $0.id == record.id }
        saveSessions()
    }

    func processChunk(
        sessionId: String,
        chunkIndex: Int,
        totalChunks: Int,
        fileName: String,
        startDate: Date,
        totalSampleCount: Int
    ) {
        var recordIndex = sessions.firstIndex(where: { $0.sessionId == sessionId })

        if recordIndex == nil {
            let record = SessionRecord(
                sessionId: sessionId,
                startDate: startDate,
                totalSampleCount: totalSampleCount,
                totalChunks: totalChunks
            )
            sessions.append(record)
            recordIndex = sessions.count - 1
        }

        guard let idx = recordIndex else { return }

        // Guard against duplicate chunk
        if sessions[idx].receivedChunks.contains(where: { $0.chunkIndex == chunkIndex }) {
            logger.warning("Duplicate chunk \(chunkIndex) for session \(sessionId)")
            return
        }

        sessions[idx].receivedChunks.append(
            ChunkFile(chunkIndex: chunkIndex, fileName: fileName)
        )

        if sessions[idx].isComplete {
            mergeChunks(at: idx)
        }

        saveSessions()
    }

    func mergeChunks(at index: Int) {
        let record = sessions[index]
        let sorted = record.receivedChunks.sorted { $0.chunkIndex < $1.chunkIndex }

        var merged = Data()
        for (i, chunk) in sorted.enumerated() {
            guard let data = try? Data(contentsOf: chunk.fileURL) else {
                logger.error("Failed to read chunk file: \(chunk.fileName)")
                return
            }
            if i == 0 {
                merged.append(data)
            } else {
                // Strip header line from subsequent chunks
                guard let content = String(data: data, encoding: .utf8) else {
                    logger.error("Failed to decode chunk: \(chunk.fileName)")
                    return
                }
                if let newlineIndex = content.firstIndex(of: "\n") {
                    let body = content[content.index(after: newlineIndex)...]
                    merged.append(Data(body.utf8))
                }
            }
        }

        let mergedName = "session_\(record.sessionId).csv"
        let documentsDir = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!
        let mergedURL = documentsDir.appendingPathComponent(mergedName)

        do {
            try merged.write(to: mergedURL)
            sessions[index].mergedFileName = mergedName

            // Delete individual chunk files
            for chunk in sorted {
                try? FileManager.default.removeItem(at: chunk.fileURL)
            }
            logger.info("Merged \(sorted.count) chunks into \(mergedName)")
        } catch {
            logger.error("Failed to write merged file: \(error.localizedDescription)")
        }
    }

    private func persistedFilesURL() -> URL {
        FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!.appendingPathComponent("sessions.json")
    }

    private func saveSessions() {
        do {
            let data = try JSONEncoder().encode(sessions)
            try data.write(to: persistedFilesURL(), options: .atomic)
        } catch {
            logger.error("Failed to persist sessions list: \(error.localizedDescription)")
        }
    }

    private func loadSessions() {
        let url = persistedFilesURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            sessions = try JSONDecoder().decode([SessionRecord].self, from: data)
        } catch {
            logger.error("Failed to load sessions list: \(error.localizedDescription)")
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
        let fileName = metadata?["fileName"] as? String ?? "unknown.csv"
        let sessionId = metadata?["sessionId"] as? String ?? "unknown"
        let chunkIndex = metadata?["chunkIndex"] as? Int ?? 0
        let totalChunks = metadata?["totalChunks"] as? Int ?? 1
        let totalSampleCount = metadata?["totalSampleCount"] as? Int ?? 0
        let startInterval = metadata?["startDate"] as? TimeInterval ?? 0

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

            Task { @MainActor in
                self.processChunk(
                    sessionId: sessionId,
                    chunkIndex: chunkIndex,
                    totalChunks: totalChunks,
                    fileName: fileName,
                    startDate: startDate,
                    totalSampleCount: totalSampleCount
                )
            }
        } catch {
            logger.error("Failed to save received file: \(error.localizedDescription)")
        }
    }
}
