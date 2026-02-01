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

    struct ReceivedFile: Identifiable, Sendable {
        let id = UUID()
        let fileName: String
        let fileURL: URL
        let sampleCount: Int
        let startDate: Date
    }

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        session.delegate = self
        session.activate()
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
        let metadata = file.metadata
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
            try FileManager.default.moveItem(at: file.fileURL, to: destinationURL)

            let receivedFile = ReceivedFile(
                fileName: fileName,
                fileURL: destinationURL,
                sampleCount: sampleCount,
                startDate: Date(timeIntervalSince1970: startInterval)
            )

            Task { @MainActor in
                self.receivedFiles.append(receivedFile)
            }
        } catch {
            logger.error("Failed to save received file: \(error.localizedDescription)")
        }
    }
}
