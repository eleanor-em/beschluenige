import SwiftUI
import os

struct StartView: View {
    var workoutManager: WorkoutManager
    @Binding var showExport: Bool
    @State private var errorMessage: String?

    private let logger = Logger(
        subsystem: "net.lnor.beschluenige.watchkitapp",
        category: "StartView"
    )

    var body: some View {
        VStack(spacing: 16) {
            Button {
                Task {
                    do {
                        try await workoutManager.startRecording()
                    } catch {
                        logger.error("Failed to start recording: \(error.localizedDescription)")
                        errorMessage = error.localizedDescription
                    }
                }
            } label: {
                Label("Start", systemImage: "heart.fill")
            }
            .tint(.green)

            if workoutManager.currentSession != nil {
                Button("Export Data") {
                    showExport = true
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
        .navigationTitle("beschluenige")
    }
}
