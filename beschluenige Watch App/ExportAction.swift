import Foundation

enum TransferState: Sendable {
    case idle, sending, sent, savedLocally(URL), failed(String)
}

struct ExportAction {
    var sendViaPhone: (RecordingSession) -> Bool = {
        PhoneConnectivityManager.shared.sendSession($0)
    }
    var saveLocally: (RecordingSession) throws -> URL = { session in
        try session.saveLocally()
    }

    func execute(session: RecordingSession) -> TransferState {
        let success = sendViaPhone(session)
        if success {
            return .sent
        }
        do {
            let url = try saveLocally(session)
            return .savedLocally(url)
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
