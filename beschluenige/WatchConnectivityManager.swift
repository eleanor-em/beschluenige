import Foundation
import WatchConnectivity
import os

@Observable
final class WatchConnectivityManager: NSObject, @unchecked Sendable {
    static let shared = WatchConnectivityManager()

    var receivedFiles: [ReceivedFile] = []

    private let session = WCSession.default
    private let logger = Logger(
        subsystem: "net.lnor.beschluenige",
        category: "Connectivity"
    )

    struct ReceivedFile: Identifiable, Codable, Sendable {
        let id: UUID
        let fileName: String
        let sampleCount: Int
        let startDate: Date

        var fileURL: URL {
            FileManager.default.urls(
                for: .documentDirectory, in: .userDomainMask
            ).first!.appendingPathComponent(fileName)
        }

        init(fileName: String, sampleCount: Int, startDate: Date) {
            self.id = UUID()
            self.fileName = fileName
            self.sampleCount = sampleCount
            self.startDate = startDate
        }
    }

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        session.delegate = self
        session.activate()
        loadReceivedFiles()
    }

    func deleteFile(_ file: ReceivedFile) {
        try? FileManager.default.removeItem(at: file.fileURL)
        receivedFiles.removeAll { $0.id == file.id }
        saveReceivedFiles()
    }

    private func persistedFilesURL() -> URL {
        FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!.appendingPathComponent("received_files.json")
    }

    private func saveReceivedFiles() {
        do {
            let data = try JSONEncoder().encode(receivedFiles)
            try data.write(to: persistedFilesURL(), options: .atomic)
        } catch {
            logger.error("Failed to persist received files list: \(error.localizedDescription)")
        }
    }

    private func loadReceivedFiles() {
        let url = persistedFilesURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            let files = try JSONDecoder().decode([ReceivedFile].self, from: data)
            receivedFiles = files.filter {
                FileManager.default.fileExists(atPath: $0.fileURL.path)
            }
        } catch {
            logger.error("Failed to load received files list: \(error.localizedDescription)")
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
        let sampleCount = metadata?["sampleCount"] as? Int ?? 0
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
                let receivedFile = ReceivedFile(
                    fileName: fileName,
                    sampleCount: sampleCount,
                    startDate: startDate
                )
                self.receivedFiles.append(receivedFile)
                self.saveReceivedFiles()
            }
        } catch {
            logger.error("Failed to save received file: \(error.localizedDescription)")
        }
    }
}
