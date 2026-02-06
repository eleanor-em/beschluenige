import Foundation

enum TransferState: Sendable {
    case idle, sending, sent, savedLocally([URL]), failed(String)
}

struct ExportAction {
    var sendChunksViaPhone: ([URL], String, Date, Int) -> Bool = { chunkURLs, sessionId, startDate, totalSampleCount in
        PhoneConnectivityManager.shared.sendChunks(
            chunkURLs: chunkURLs,
            sessionId: sessionId,
            startDate: startDate,
            totalSampleCount: totalSampleCount
        )
    }
    var finalizeSession: (inout RecordingSession) throws -> [URL] = { session in
        try session.finalizeChunks()
    }
    var registerSession: (String, Date, [URL], Int) -> Void = { _, _, _, _ in }
    var markTransferred: (String) -> Void = { _ in }

    func execute(session: inout RecordingSession) -> TransferState {
        let chunkURLs: [URL]
        do {
            chunkURLs = try finalizeSession(&session)
        } catch {
            return .failed(error.localizedDescription)
        }
        guard !chunkURLs.isEmpty else { return .failed("No data to export") }

        registerSession(
            session.sessionId, session.startDate, chunkURLs, session.cumulativeSampleCount
        )

        let success = sendChunksViaPhone(
            chunkURLs, session.sessionId, session.startDate, session.cumulativeSampleCount
        )
        if success {
            markTransferred(session.sessionId)
            return .sent
        }
        return .savedLocally(chunkURLs)
    }
}
