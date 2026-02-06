import SwiftUI
import os

struct ContentView: View {
    @State private var workoutManager: WorkoutManager
    @State private var sessionStore: SessionStore
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
        let store = SessionStore()
        if CommandLine.arguments.contains("--ui-testing") {
            store.registerSession(
                sessionId: "ui-test",
                startDate: Date(),
                chunkURLs: [],
                totalSampleCount: 42
            )
        }
        _sessionStore = State(initialValue: store)
    }

    init(workoutManager: WorkoutManager, sessionStore: SessionStore = SessionStore()) {
        _workoutManager = State(initialValue: workoutManager)
        _sessionStore = State(initialValue: sessionStore)
    }

    var body: some View {
        NavigationStack {
            if workoutManager.isRecording {
                RecordingView(workoutManager: workoutManager)
            } else {
                StartView(
                    workoutManager: workoutManager,
                    sessionStore: sessionStore,
                    showExport: $showExport
                )
            }
        }
        .sheet(isPresented: $showExport) {
            ExportView(workoutManager: workoutManager, sessionStore: sessionStore)
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
