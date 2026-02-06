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

    func sendChunk(
        fileURL: URL,
        workoutId: String,
        chunkIndex: Int,
        totalChunks: Int,
        startDate: Date,
        totalSampleCount: Int
    ) -> Bool {
        guard session.activationState == .activated else { return false }

        let metadata: [String: Any] = [
            "fileName": fileURL.lastPathComponent,
            "workoutId": workoutId,
            "chunkIndex": chunkIndex,
            "totalChunks": totalChunks,
            "startDate": startDate.timeIntervalSince1970,
            "totalSampleCount": totalSampleCount,
        ]

        session.sendFile(fileURL, metadata: metadata)
        return true
    }

    func sendChunks(
        chunkURLs: [URL],
        workoutId: String,
        startDate: Date,
        totalSampleCount: Int
    ) -> Bool {
        guard session.activationState == .activated else { return false }
        guard !chunkURLs.isEmpty else { return false }

        let totalChunks = chunkURLs.count
        for (index, url) in chunkURLs.enumerated() {
            let sent = sendChunk(
                fileURL: url,
                workoutId: workoutId,
                chunkIndex: index,
                totalChunks: totalChunks,
                startDate: startDate,
                totalSampleCount: totalSampleCount
            )
            if !sent { return false }
        }
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
