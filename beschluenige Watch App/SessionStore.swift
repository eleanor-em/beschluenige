import Foundation
import os

@Observable
final class SessionStore: @unchecked Sendable {
    var sessions: [WatchSessionRecord] = []

    private let persistenceURL: URL
    private let logger = Logger(
        subsystem: "net.lnor.beschluenige.watchkitapp",
        category: "SessionStore"
    )

    init(persistenceURL: URL? = nil) {
        self.persistenceURL = persistenceURL ?? FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!.appendingPathComponent("watch_sessions.json")
        loadSessions()
    }

    func registerSession(
        sessionId: String,
        startDate: Date,
        chunkURLs: [URL],
        totalSampleCount: Int
    ) {
        guard !sessions.contains(where: { $0.sessionId == sessionId }) else { return }
        let record = WatchSessionRecord(
            id: UUID(),
            sessionId: sessionId,
            startDate: startDate,
            chunkCount: chunkURLs.count,
            totalSampleCount: totalSampleCount,
            transferred: false,
            chunkFileNames: chunkURLs.map { $0.lastPathComponent }
        )
        sessions.append(record)
        saveSessions()
    }

    func markTransferred(sessionId: String) {
        guard let index = sessions.firstIndex(where: { $0.sessionId == sessionId }) else {
            return
        }
        sessions[index].transferred = true
        saveSessions()
    }

    func deleteAll() {
        let fm = FileManager.default
        let documentsDir = fm.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!
        for record in sessions {
            for fileName in record.chunkFileNames {
                let url = documentsDir.appendingPathComponent(fileName)
                try? fm.removeItem(at: url)
            }
        }
        sessions.removeAll()
        saveSessions()
    }

    private func saveSessions() {
        do {
            let data = try JSONEncoder().encode(sessions)
            try data.write(to: persistenceURL, options: .atomic)
        } catch {
            logger.error("Failed to persist watch sessions: \(error.localizedDescription)")
        }
    }

    private func loadSessions() {
        guard FileManager.default.fileExists(atPath: persistenceURL.path) else { return }
        do {
            let data = try Data(contentsOf: persistenceURL)
            sessions = try JSONDecoder().decode([WatchSessionRecord].self, from: data)
        } catch {
            logger.error("Failed to load watch sessions: \(error.localizedDescription)")
        }
    }
}
