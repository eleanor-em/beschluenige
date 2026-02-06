import HealthKit
import SwiftUI
import os

struct ContentView: View {
    var connectivityManager = WatchConnectivityManager.shared
    @State private var healthAuthDenied = false
    @State private var sessionToDelete: WatchConnectivityManager.SessionRecord?

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

                if connectivityManager.sessions.isEmpty {
                    ContentUnavailableView(
                        "No Recordings",
                        systemImage: "heart.slash",
                        description: Text(
                            "Record heart rate data on your Apple Watch, then export it here."
                        )
                    )
                } else {
                    ForEach(connectivityManager.sessions) { record in
                        sessionRow(record)
                    }
                }
            }
            .navigationTitle("beschluenige")
            .alert(
                "Delete Recording",
                isPresented: Binding(
                    get: { sessionToDelete != nil },
                    set: { if !$0 { sessionToDelete = nil } }
                )
            ) {
                Button("Delete", role: .destructive) {
                    if let record = sessionToDelete {
                        connectivityManager.deleteSession(record)
                        sessionToDelete = nil
                    }
                }
                Button("Cancel", role: .cancel) {
                    sessionToDelete = nil
                }
            } message: {
                if let record = sessionToDelete {
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
    private func sessionRow(
        _ record: WatchConnectivityManager.SessionRecord
    ) -> some View {
        VStack(alignment: .leading) {
            Text(record.displayName)
                .font(.headline)
            if record.isComplete {
                let label = "\(record.totalSampleCount) samples"
                (Text(label + " - ") + Text(record.startDate, style: .date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                let chunkLabel =
                    "Receiving \(record.receivedChunks.count)/\(record.totalChunks) chunks"
                Text(chunkLabel)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .contextMenu {
            if let mergedURL = record.mergedFileURL {
                ShareLink(item: mergedURL)
            }
            Button(role: .destructive) {
                sessionToDelete = record
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .listRowBackground(
            sessionToDelete?.id == record.id
                ? Color.red.opacity(0.2)
                : nil
        )
        .swipeActions(edge: .trailing) {
            Button {
                sessionToDelete = record
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(.red)
        }
    }

    private func requestHealthKitAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            logger.warning("HealthKit not available on this device")
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
            logger.info("HealthKit workout authorization status: \(wkStatus.rawValue)")
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
