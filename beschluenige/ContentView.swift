import HealthKit
import SwiftUI
import os

struct ContentView: View {
    var connectivityManager = WatchConnectivityManager.shared
    @State private var healthAuthDenied = false
    @State private var fileToDelete: WatchConnectivityManager.ReceivedFile?

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

                if connectivityManager.receivedFiles.isEmpty {
                    ContentUnavailableView(
                        "No Recordings",
                        systemImage: "heart.slash",
                        description: Text(
                            "Record heart rate data on your Apple Watch, then export it here."
                        )
                    )
                } else {
                    ForEach(connectivityManager.receivedFiles) { file in
                        VStack(alignment: .leading) {
                            Text(file.fileName)
                                .font(.headline)
                            Text(
                                "\(file.sampleCount) samples - \(file.startDate, style: .date)"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .contextMenu {
                            ShareLink(item: file.fileURL)
                            Button(role: .destructive) {
                                fileToDelete = file
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .listRowBackground(
                            fileToDelete?.id == file.id
                                ? Color.red.opacity(0.2)
                                : nil
                        )
                        .swipeActions(edge: .trailing) {
                            Button {
                                fileToDelete = file
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .tint(.red)
                        }
                    }
                }
            }
            .navigationTitle("beschluenige")
            .alert(
                "Delete Recording",
                isPresented: Binding(
                    get: { fileToDelete != nil },
                    set: { if !$0 { fileToDelete = nil } }
                )
            ) {
                Button("Delete", role: .destructive) {
                    if let file = fileToDelete {
                        connectivityManager.deleteFile(file)
                        fileToDelete = nil
                    }
                }
                Button("Cancel", role: .cancel) {
                    fileToDelete = nil
                }
            } message: {
                if let file = fileToDelete {
                    Text("Are you sure you want to delete \"\(file.fileName)\"? This cannot be undone.")
                }
            }
        }
        .task {
            await requestHealthKitAuthorization()
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
