import Foundation
import WatchConnectivity
import os

final class PhoneConnectivityManager: NSObject, @unchecked Sendable {
    static let shared = PhoneConnectivityManager()

    private let session = WCSession.default
    private let logger = Logger(
        subsystem: "net.lnor.beschluenige.watchkitapp",
        category: "Connectivity"
    )

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        session.delegate = self
        session.activate()
    }

    func sendSession(_ recordingSession: RecordingSession) -> Bool {
        guard session.activationState == .activated else { return false }

        let csvData = recordingSession.csvData()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let fileName = "hr_\(formatter.string(from: recordingSession.startDate)).csv"

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName)
        do {
            try csvData.write(to: tempURL)
        } catch {
            logger.error("Failed to write temp CSV: \(error.localizedDescription)")
            return false
        }

        let metadata: [String: Any] = [
            "fileName": fileName,
            "sampleCount": recordingSession.sampleCount,
            "startDate": recordingSession.startDate.timeIntervalSince1970,
        ]

        session.transferFile(tempURL, metadata: metadata)
        return true
    }
}

extension PhoneConnectivityManager: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            logger.error("WCSession activation failed: \(error.localizedDescription)")
        }
    }
}
