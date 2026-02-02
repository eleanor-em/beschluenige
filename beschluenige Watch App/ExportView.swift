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

    var body: some View {
        VStack(spacing: 12) {
            if let session = workoutManager.currentSession {
                Text("\(session.totalSampleCount) samples")
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
        transferState = ExportAction().execute(session: session)
        if case .savedLocally(let url) = transferState {
            logger.info("CSV saved to \(url.path)")
        } else if case .failed(let message) = transferState {
            logger.error("Export failed: \(message)")
        }
    }
}
