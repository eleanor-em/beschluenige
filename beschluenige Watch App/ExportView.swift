import SwiftUI
import os

struct ExportView: View {
    var workoutManager: WorkoutManager
    @State private var transferState: TransferState = .idle
    @Environment(\.dismiss) private var dismiss

    private let logger = Logger(
        subsystem: "net.lnor.beschluenige.watchkitapp",
        category: "Export"
    )

    enum TransferState {
        case idle, sending, sent, savedLocally(URL), failed(String)
    }

    var body: some View {
        VStack(spacing: 12) {
            if let session = workoutManager.currentSession {
                Text("\(session.sampleCount) samples")
                Text(session.startDate, style: .date)
                    .font(.caption)

                switch transferState {
                case .idle:
                    Button("Send to iPhone") {
                        sendToPhone(session: session)
                    }
                case .sending:
                    ProgressView("Sending...")
                case .sent:
                    Label("Sent", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .savedLocally(let url):
                    Text("Transfer failed. Saved locally:")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Text(url.path)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                case .failed(let message):
                    Text("Error: \(message)")
                        .foregroundStyle(.red)
                }
            } else {
                Text("No recording data")
            }

            Button("Done") { dismiss() }
        }
    }

    private func sendToPhone(session: RecordingSession) {
        transferState = .sending
        let success = PhoneConnectivityManager.shared.sendSession(session)
        if success {
            transferState = .sent
        } else {
            logger.warning("WatchConnectivity transfer failed, saving locally")
            do {
                let url = try session.saveLocally()
                logger.info("CSV saved to \(url.path)")
                transferState = .savedLocally(url)
            } catch {
                logger.error("Local save also failed: \(error.localizedDescription)")
                transferState = .failed(error.localizedDescription)
            }
        }
    }
}
