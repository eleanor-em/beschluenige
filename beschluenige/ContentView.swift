import HealthKit
import SwiftUI
import os

struct ContentView: View {
    var connectivityManager = WatchConnectivityManager.shared
    @State private var healthAuthDenied = false
    @State private var workoutToDelete: WatchConnectivityManager.WorkoutRecord?

    private let logger = Logger(
        subsystem: "net.lnor.beschluenige",
        category: "ContentView"
    )

    var body: some View {
        NavigationStack {
            List {
                if healthAuthDenied {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("HealthKit Access Required", systemImage: "heart.circle.fill")
                                .font(.headline)
                                .foregroundStyle(.red)
                            Text(
                                "beschluenige needs permission to read heart rate and write"
                                    + " workouts. Open Settings > Privacy & Security > Health >"
                                    + " beschluenige and enable all permissions."
                            )
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            if let url = URL(string: "x-apple-health://") {
                                Link("Open Health App", destination: url)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                if connectivityManager.workouts.isEmpty {
                    ContentUnavailableView(
                        "No Workouts",
                        systemImage: "heart.slash",
                        description: Text(
                            "Record heart rate data on your Apple Watch, then export it here."
                        )
                    )
                } else {
                    ForEach(connectivityManager.workouts) { record in
                        NavigationLink(destination: WorkoutDetailView(record: record)) {
                            workoutRow(record)
                        }
                    }
                }
            }
            .navigationTitle("beschluenige")
            .alert(
                "Delete Workout",
                isPresented: Binding(
                    get: { workoutToDelete != nil },
                    set: { if !$0 { workoutToDelete = nil } }
                )
            ) {
                Button("Delete", role: .destructive) {
                    if let record = workoutToDelete {
                        connectivityManager.deleteWorkout(record)
                        workoutToDelete = nil
                    }
                }
                Button("Cancel", role: .cancel) {
                    workoutToDelete = nil
                }
            } message: {
                if let record = workoutToDelete {
                    Text(
                        "Are you sure you want to delete"
                            + " \"\(record.displayName)\"? This cannot be undone."
                    )
                }
            }
        }
        .task {
            await requestHealthKitAuthorization()
        }
    }

    @ViewBuilder
    private func workoutRow(
        _ record: WatchConnectivityManager.WorkoutRecord
    ) -> some View {
        VStack(alignment: .leading) {
            Text(record.displayName)
                .font(.headline)
            if record.isComplete {
                Text(
                    "\(record.totalChunks) chunks - \(record.fileSizeBytes.formattedFileSize)"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                let sizeStr = record.fileSizeBytes.formattedFileSize
                let chunkLabel =
                    "Receiving \(record.receivedChunks.count)/\(record.totalChunks)"
                    + " chunks - \(sizeStr)"
                Text(chunkLabel)
                    .font(.caption)

            }
        }
        .contextMenu {
            if let mergedURL = record.mergedFileURL {
                ShareLink(item: mergedURL)
            }
            Button(role: .destructive) {
                workoutToDelete = record
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .listRowBackground(
            workoutToDelete?.id == record.id
                ? Color.red.opacity(0.2)
                : nil
        )
        .swipeActions(edge: .trailing) {
            Button {
                workoutToDelete = record
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(.red)
        }
    }

    private func requestHealthKitAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            logger.error("HealthKit not available on this device")
            return
        }

        let store = HKHealthStore()
        let heartRateType = HKQuantityType(.heartRate)
        let workoutType = HKObjectType.workoutType()

        do {
            logger.info("Requesting HealthKit authorization")
            try await store.requestAuthorization(
                toShare: [workoutType],
                read: [heartRateType]
            )
            let wkStatus = store.authorizationStatus(for: workoutType)
            logger.info("HealthKit authorization status: \(wkStatus.rawValue)")
            healthAuthDenied = wkStatus != .sharingAuthorized
        } catch {
            logger.error("HealthKit authorization error: \(error.localizedDescription)")
            healthAuthDenied = true
        }
    }
}

#Preview {
    ContentView()
}
