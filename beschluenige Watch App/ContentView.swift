import SwiftUI
import os

struct ContentView: View {
    @State private var workoutManager: WorkoutManager
    @State private var showExport = false

    private let logger = Logger(
        subsystem: "net.lnor.beschluenige.watchkitapp",
        category: "ContentView"
    )

    init() {
        if CommandLine.arguments.contains("--ui-testing") {
            _workoutManager = State(initialValue: WorkoutManager(
                provider: UITestHeartRateProvider(),
                locationProvider: UITestLocationProvider(),
                motionProvider: UITestMotionProvider()
            ))
        } else {
            _workoutManager = State(initialValue: WorkoutManager(
                provider: HealthKitHeartRateProvider(),
                locationProvider: CoreLocationProvider(),
                motionProvider: CoreMotionProvider()
            ))
        }
    }

    init(workoutManager: WorkoutManager) {
        _workoutManager = State(initialValue: workoutManager)
    }

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
            await authorizeProviders()
        }
    }

    func authorizeProviders() async {
        do {
            try await workoutManager.requestAuthorization()
        } catch {
            logger.error("Authorization failed: \(error.localizedDescription)")
        }
    }
}

#Preview {
    ContentView()
}
