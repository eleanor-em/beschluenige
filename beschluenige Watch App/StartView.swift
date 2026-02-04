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

    init(
        workoutManager: WorkoutManager,
        showExport: Binding<Bool>,
        initialErrorMessage: String? = nil
    ) {
        self.workoutManager = workoutManager
        self._showExport = showExport
        self._errorMessage = State(initialValue: initialErrorMessage)
    }

    var body: some View {
        VStack(spacing: 16) {
            Button {
                Task { await handleStartTapped() }
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

    func handleStartTapped() async {
        do {
            try await workoutManager.startRecording()
        } catch {
            logger.error("Failed to start recording: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }
}
