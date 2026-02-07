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

    func sendChunk(fileURL: URL, info: ChunkTransferInfo) -> Progress? {
        guard session.activationState == .activated else { return nil }
        return session.sendFile(fileURL, metadata: info.metadata())
    }

    func sendChunks(
        chunkURLs: [URL],
        workoutId: String,
        startDate: Date,
        totalSampleCount: Int
    ) -> Progress? {
        guard session.activationState == .activated else { return nil }
        guard !chunkURLs.isEmpty else { return nil }

        let totalChunks = chunkURLs.count
        let parent = Progress(totalUnitCount: Int64(totalChunks))
        for (index, url) in chunkURLs.enumerated() {
            let fileSize: Int64 = {
                do {
                    let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
                    // swiftlint:disable:next force_cast
                    return attrs[.size] as! Int64
                } catch {
                    logger.error(
                        "Failed to read file attributes for \(url.lastPathComponent): \(error.localizedDescription)"
                    )
                    return 0
                }
            }()
            let info = ChunkTransferInfo(
                workoutId: workoutId,
                chunkIndex: index,
                totalChunks: totalChunks,
                startDate: startDate,
                totalSampleCount: totalSampleCount,
                fileName: url.lastPathComponent,
                chunkSizeBytes: fileSize
            )
            guard let child = sendChunk(
                fileURL: url, info: info
            ) else { return nil }
            parent.addChild(child, withPendingUnitCount: 1)
        }
        return parent
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

    nonisolated func session(
        _ session: WCSession,
        didFinish fileTransfer: WCSessionFileTransfer,
        error: Error?
    ) {
        if let error {
            logger.error(
                "File transfer failed: \(error.localizedDescription)"
            )
        }
    }
}
