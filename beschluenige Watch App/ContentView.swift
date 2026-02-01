import SwiftUI

struct ContentView: View {
    @State private var workoutManager = WorkoutManager(
        provider: MockHeartRateProvider(),
        locationProvider: MockLocationProvider(),
        motionProvider: MockMotionProvider()
    )
    @State private var showExport = false

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
            try? await workoutManager.requestAuthorization()
        }
    }
}

#Preview {
    ContentView()
}
