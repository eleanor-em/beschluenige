import SwiftUI

struct SessionRowView: View {
    var record: WatchSessionRecord

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

struct SessionListView: View {
    var sessionStore: SessionStore
    @State private var showDeleteConfirmation: Bool

    init(
        sessionStore: SessionStore,
        initialShowDeleteConfirmation: Bool = false
    ) {
        self.sessionStore = sessionStore
        self._showDeleteConfirmation = State(initialValue: initialShowDeleteConfirmation)
    }

    var deleteConfirmationMessage: some View {
        Text("This will remove all recorded data from this watch.")
    }

    func handleDeleteAll() {
        sessionStore.deleteAll()
    }

    func requestDeleteConfirmation() {
        showDeleteConfirmation = true
    }

    func handleCancelDelete() {}

    var body: some View {
        List {
            if sessionStore.sessions.isEmpty {
                Text("No sessions")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sessionStore.sessions, content: SessionRowView.init(record:))
            }

            Section {
                Button(role: .destructive, action: requestDeleteConfirmation) {
                    Text("Delete All")
                        .frame(maxWidth: .infinity)
                }
                .disabled(sessionStore.sessions.isEmpty)
            }
        }
        .navigationTitle("Sessions")
        .alert("Delete All Sessions?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive, action: handleDeleteAll)
            Button("Cancel", role: .cancel, action: handleCancelDelete)
        } message: {
            deleteConfirmationMessage
        }
    }
}
