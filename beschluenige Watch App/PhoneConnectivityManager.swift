import CryptoKit
import Foundation
import WatchConnectivity

final class PhoneConnectivityManager: NSObject, @unchecked Sendable {
    static let shared = PhoneConnectivityManager()

    private let session: any ConnectivitySession
    private let logger = AppLogger(category: "Connectivity")

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
        logger.info("sendChunks(): \(workoutId), \(chunkURLs.count) chunks, \(totalSampleCount) samples")
        guard session.activationState == .activated else { return nil }
        guard !chunkURLs.isEmpty else { return nil }

        let totalChunks = chunkURLs.count
        let (manifest, fileSizes) = buildManifest(
            chunkURLs: chunkURLs, workoutId: workoutId,
            startDate: startDate, totalSampleCount: totalSampleCount
        )

        // 1 unit for manifest + N units for chunks
        let parent = Progress(totalUnitCount: Int64(1 + totalChunks))

        // Send manifest first
        guard let manifestProgress = sendManifestFile(manifest, workoutId: workoutId) else {
            return nil
        }
        parent.addChild(manifestProgress, withPendingUnitCount: 1)

        // Send chunks
        for (index, url) in chunkURLs.enumerated() {
            let info = ChunkTransferInfo(
                workoutId: workoutId, chunkIndex: index,
                totalChunks: totalChunks, startDate: startDate,
                totalSampleCount: totalSampleCount,
                fileName: url.lastPathComponent,
                chunkSizeBytes: fileSizes[index]
            )
            guard let child = sendChunk(fileURL: url, info: info) else { return nil }
            parent.addChild(child, withPendingUnitCount: 1)
        }
        return parent
    }

    private func buildManifest(
        chunkURLs: [URL],
        workoutId: String,
        startDate: Date,
        totalSampleCount: Int
    ) -> (TransferManifest, [Int64]) {
        var entries: [TransferManifest.ChunkEntry] = []
        var fileSizes: [Int64] = []
        for url in chunkURLs {
            let fileSize: Int64 = {
                do {
                    let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
                    // swiftlint:disable:next force_cast
                    return attrs[.size] as! Int64
                } catch {
                    logger.error("Failed to read attrs for \(url.lastPathComponent): \(error)")
                    return 0
                }
            }()
            fileSizes.append(fileSize)
            let hash: String = {
                do { return try md5Hex(of: url) } catch {
                    logger.error("Failed to compute MD5 for \(url.lastPathComponent): \(error)")
                    return ""
                }
            }()
            entries.append(TransferManifest.ChunkEntry(
                fileName: url.lastPathComponent, sizeBytes: fileSize, md5: hash
            ))
        }
        let manifest = TransferManifest(
            workoutId: workoutId, startDate: startDate,
            totalSampleCount: totalSampleCount,
            totalChunks: chunkURLs.count, chunks: entries
        )
        return (manifest, fileSizes)
    }

    private func sendManifestFile(_ manifest: TransferManifest, workoutId: String) -> Progress? {
        do {
            let data = try JSONEncoder().encode(manifest)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("manifest_\(workoutId).json")
            try data.write(to: url, options: .atomic)
            let meta: [String: Any] = ["isManifest": true, "workoutId": workoutId]
            return session.sendFile(url, metadata: meta)
        } catch {
            logger.error("Failed to encode/send manifest: \(error.localizedDescription)")
            return nil
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
