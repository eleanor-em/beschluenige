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
        initialTransferState: TransferState = .idle,
        sessionStore: SessionStore = SessionStore()
    ) {
        self.workoutManager = workoutManager
        var action = exportAction
        action.registerSession = { sessionId, startDate, chunkURLs, totalSampleCount in
            sessionStore.registerSession(
                sessionId: sessionId,
                startDate: startDate,
                chunkURLs: chunkURLs,
                totalSampleCount: totalSampleCount
            )
        }
        action.markTransferred = { sessionId in
            sessionStore.markTransferred(sessionId: sessionId)
        }
        self.exportAction = action
        self._transferState = State(initialValue: initialTransferState)
    }

    var body: some View {
        VStack(spacing: 12) {
            if workoutManager.currentSession != nil {
                let totalSamples = workoutManager.heartRateSampleCount
                    + workoutManager.locationSampleCount
                    + workoutManager.accelerometerSampleCount
                    + workoutManager.deviceMotionSampleCount
                Text("\(totalSamples) samples")
                Text(workoutManager.currentSession!.startDate, style: .date)
                    .font(.caption)

                switch transferState {
                case .idle:
                    Button("Send to iPhone", action: handleSendToPhone)
                case .sending:
                    ProgressView("Sending...")
                case .sent:
                    Label("Sent", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .savedLocally(let urls):
                    Text("Transfer failed. \(urls.count) chunk(s) saved locally:")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    if let first = urls.first {
                        Text(first.deletingLastPathComponent().path)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
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
        guard workoutManager.currentSession != nil else { return }
        sendToPhone()
    }

    func handleDismiss() {
        dismiss()
    }

    func sendToPhone() {
        transferState = .sending
        let result = exportAction.execute(session: &workoutManager.currentSession!)
        transferState = result
        if case .savedLocally(let urls) = result {
            logger.info("Chunks saved locally: \(urls.count) file(s)")
        } else if case .failed(let message) = result {
            logger.error("Export failed: \(message)")
        }
    }
}
