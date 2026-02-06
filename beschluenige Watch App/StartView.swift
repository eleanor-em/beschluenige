import SwiftUI
import os

struct StartView: View {
    var workoutManager: WorkoutManager
    var workoutStore: WorkoutStore
    @State private var errorMessage: String?

    private let logger = Logger(
        subsystem: "net.lnor.beschluenige.watchkitapp",
        category: "StartView"
    )

    init(
        workoutManager: WorkoutManager,
        workoutStore: WorkoutStore = WorkoutStore(),
        initialErrorMessage: String? = nil
    ) {
        self.workoutManager = workoutManager
        self.workoutStore = workoutStore
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

            NavigationLink("Workouts") {
                WorkoutListView(workoutStore: workoutStore)
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
