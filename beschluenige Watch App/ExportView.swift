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
        workoutStore: WorkoutStore = WorkoutStore()
    ) {
        self.workoutManager = workoutManager
        var action = exportAction
        action.registerWorkout = { workoutId, startDate, chunkURLs, totalSampleCount in
            workoutStore.registerWorkout(
                workoutId: workoutId,
                startDate: startDate,
                chunkURLs: chunkURLs,
                totalSampleCount: totalSampleCount
            )
        }
        action.markTransferred = { workoutId in
            workoutStore.markTransferred(workoutId: workoutId)
        }
        self.exportAction = action
        self._transferState = State(initialValue: initialTransferState)
    }

    var body: some View {
        VStack(spacing: 12) {
            if workoutManager.currentWorkout != nil {
                let totalSamples = workoutManager.heartRateSampleCount
                    + workoutManager.locationSampleCount
                    + workoutManager.accelerometerSampleCount
                    + workoutManager.deviceMotionSampleCount
                Text("\(totalSamples) samples")
                Text(workoutManager.currentWorkout!.startDate, style: .date)
                    .font(.caption)

                switch transferState {
                case .idle, .sending:
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
                Text("No workout data")
            }

            Button("Done", action: handleDismiss)
        }
        .task {
            handleSendToPhone()
        }
    }

    func handleSendToPhone() {
        guard workoutManager.currentWorkout != nil else { return }
        sendToPhone()
    }

    func handleDismiss() {
        dismiss()
    }

    func sendToPhone() {
        transferState = .sending
        let result = exportAction.execute(workout: &workoutManager.currentWorkout!)
        transferState = result
        if case .savedLocally(let urls) = result {
            logger.info("Chunks saved locally: \(urls.count) file(s)")
        } else if case .failed(let message) = result {
            logger.error("Export failed: \(message)")
        }
    }
}
