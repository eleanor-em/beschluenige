import Foundation
import WatchConnectivity
import os

final class PhoneConnectivityManager: NSObject, @unchecked Sendable {
    static let shared = PhoneConnectivityManager()

    private let session: any ConnectivitySession
    private let logger = Logger(
        subsystem: "net.lnor.beschluenige.watchkitapp",
        category: "Connectivity"
    )

    private override init() {
        self.session = WCSession.default
        super.init()
    }

    init(session: any ConnectivitySession) {
        self.session = session
        super.init()
    }

    func activate() {
        guard session.isDeviceSupported else { return }
        session.setDelegate(self)
        session.activate()
    }

    func prepareFileForTransfer(
        _ recordingSession: RecordingSession
    ) throws -> (URL, [String: Any]) {
        let csvData = recordingSession.csvData()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let prefix = isRunningTests ? "TEST_" : ""
        let fileName = "\(prefix)hr_\(formatter.string(from: recordingSession.startDate)).csv"

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName)
        try csvData.write(to: tempURL)

        let metadata: [String: Any] = [
            "fileName": fileName,
            "sampleCount": recordingSession.totalSampleCount,
            "startDate": recordingSession.startDate.timeIntervalSince1970,
        ]

        return (tempURL, metadata)
    }

    func sendSession(_ recordingSession: RecordingSession) -> Bool {
        guard session.activationState == .activated else { return false }

        do {
            let (tempURL, metadata) = try prepareFileForTransfer(recordingSession)
            session.sendFile(tempURL, metadata: metadata)
            return true
        } catch {
            logger.error("Failed to write temp CSV: \(error.localizedDescription)")
            return false
        }
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
