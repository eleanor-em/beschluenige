import SwiftUI
import os

struct ContentView: View {
    @State private var workoutManager = WorkoutManager(
        provider: MockHeartRateProvider(),
        locationProvider: MockLocationProvider(),
        motionProvider: MockMotionProvider()
    )
    @State private var showExport = false

    private let logger = Logger(
        subsystem: "net.lnor.beschluenige.watchkitapp",
        category: "ContentView"
    )

    var body: some View {
        NavigationStack {
            if workoutManager.isRecording {
                RecordingView(workoutManager: workoutManager)
            } else {
                StartView(workoutManager: workoutManager, showExport: $showExport)
            }
        }
        .sheet(isPresented: $showExport) {
            ExportView(workoutManager: workoutManager)
        }
        .task {
            do {
                try await workoutManager.requestAuthorization()
            } catch {
                logger.error("Authorization failed: \(error.localizedDescription)")
            }
        }
    }
}

#Preview {
    ContentView()
}
