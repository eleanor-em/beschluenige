import SwiftUI
import os

struct ExportView: View {
    var workoutManager: WorkoutManager
    var exportAction: ExportAction
    @State private var transferState: TransferState
    @Environment(\.dismiss) private var dismiss

    private let logger = Logger(
        subsystem: "net.lnor.beschluenige.watchkitapp",
        category: "Export"
    )

    init(
        workoutManager: WorkoutManager,
        exportAction: ExportAction = ExportAction(),
        initialTransferState: TransferState = .idle
    ) {
        self.workoutManager = workoutManager
        self.exportAction = exportAction
        self._transferState = State(initialValue: initialTransferState)
    }

    var body: some View {
        VStack(spacing: 12) {
            if let session = workoutManager.currentSession {
                Text("\(session.totalSampleCount) samples")
                Text(session.startDate, style: .date)
                    .font(.caption)

                switch transferState {
                case .idle:
                    Button("Send to iPhone", action: handleSendToPhone)
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

            Button("Done", action: handleDismiss)
        }
    }

    func handleSendToPhone() {
        guard let session = workoutManager.currentSession else { return }
        sendToPhone(session: session)
    }

    func handleDismiss() {
        dismiss()
    }

    func sendToPhone(session: RecordingSession) {
        transferState = .sending
        let result = exportAction.execute(session: session)
        transferState = result
        if case .savedLocally(let url) = result {
            logger.info("CSV saved to \(url.path)")
        } else if case .failed(let message) = result {
            logger.error("Export failed: \(message)")
        }
    }
}
