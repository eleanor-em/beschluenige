import SwiftUI

struct WorkoutRowView: View {
    var record: WatchWorkoutRecord

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(record.startDate, style: .date)
                    .font(.caption)
                Text("\(record.totalSampleCount) samples")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if record.transferred {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Image(systemName: "clock.fill")
                    .foregroundStyle(.orange)
            }
        }
    }
}

struct WorkoutListView: View {
    var workoutStore: WorkoutStore
    @State private var showDeleteConfirmation: Bool

    init(
        workoutStore: WorkoutStore,
        initialShowDeleteConfirmation: Bool = false
    ) {
        self.workoutStore = workoutStore
        self._showDeleteConfirmation = State(initialValue: initialShowDeleteConfirmation)
    }

    var deleteConfirmationMessage: some View {
        Text("This will remove all recorded data from this watch.")
    }

    func handleDeleteAll() {
        workoutStore.deleteAll()
    }

    func requestDeleteConfirmation() {
        showDeleteConfirmation = true
    }

    func handleCancelDelete() {}

    var body: some View {
        List {
            if workoutStore.workouts.isEmpty {
                Text("No workouts")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(workoutStore.workouts, content: WorkoutRowView.init(record:))
            }

            Section {
                Button(role: .destructive, action: requestDeleteConfirmation) {
                    Text("Delete All")
                        .frame(maxWidth: .infinity)
                }
                .disabled(workoutStore.workouts.isEmpty)
            }
        }
        .navigationTitle("Workouts")
        .alert("Delete All Workouts?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive, action: handleDeleteAll)
            Button("Cancel", role: .cancel, action: handleCancelDelete)
        } message: {
            deleteConfirmationMessage
        }
    }
}
