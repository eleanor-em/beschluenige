import SwiftUI

struct StartView: View {
    var workoutManager: WorkoutManager
    @Binding var showExport: Bool

    var body: some View {
        VStack(spacing: 16) {
            Button {
                Task { try? await workoutManager.startRecording() }
            } label: {
                Label("Start", systemImage: "heart.fill")
            }
            .tint(.green)

            if workoutManager.currentSession != nil {
                Button("Export Data") {
                    showExport = true
                }
            }
        }
        .navigationTitle("beschluenige")
    }
}
