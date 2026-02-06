import SwiftUI
import os

struct ContentView: View {
    @State private var workoutManager: WorkoutManager
    @State private var workoutStore: WorkoutStore
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
                motionProvider: CoreDeviceMotionProvider()
            ))
        }
        let store = WorkoutStore()
        if CommandLine.arguments.contains("--ui-testing") {
            store.registerWorkout(
                workoutId: "ui-test",
                startDate: Date(),
                chunkURLs: [],
                totalSampleCount: 42
            )
        }
        _workoutStore = State(initialValue: store)
    }

    init(workoutManager: WorkoutManager, workoutStore: WorkoutStore = WorkoutStore()) {
        _workoutManager = State(initialValue: workoutManager)
        _workoutStore = State(initialValue: workoutStore)
    }

    var body: some View {
        NavigationStack {
            if workoutManager.isRecording {
                WorkoutView(workoutManager: workoutManager)
            } else {
                StartView(
                    workoutManager: workoutManager,
                    workoutStore: workoutStore,
                    showExport: $showExport
                )
            }
        }
        .sheet(isPresented: $showExport) {
            ExportView(workoutManager: workoutManager, workoutStore: workoutStore)
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
