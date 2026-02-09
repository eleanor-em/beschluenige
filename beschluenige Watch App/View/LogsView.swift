import SwiftUI

struct LogEntryRow: View {
    var entry: AppLogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(entry.date, format: .dateTime.hour().minute().second().secondFraction(.fractional(3)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(levelLabel(entry.level))
                    .font(.caption2)
                    .foregroundStyle(levelColor(entry.level))
            }
            Text("[\(entry.category)]")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(entry.message)
                .font(.caption)
        }
    }

    func levelLabel(_ level: AppLogLevel) -> String {
        switch level {
        case .info: "INF"
        case .notice: "NTC"
        case .warning: "WRN"
        case .error: "ERR"
        case .fault: "FLT"
        }
    }

    func levelColor(_ level: AppLogLevel) -> Color {
        switch level {
        case .error, .fault: .red
        case .warning, .notice: .yellow
        case .info: .secondary
        }
    }
}

struct LogsView: View {
    var store: AppLogStore

    init(store: AppLogStore = .shared) {
        self.store = store
    }

    var body: some View {
        List {
            if store.entries.isEmpty {
                Text("No log entries")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.entries) { entry in
                    LogEntryRow(entry: entry)
                }
            }
            Section {
                Button(action: handleClear) {
                    Label("Clear", systemImage: "trash")
                }
            }
        }
        .navigationTitle("Logs")
    }

    func handleClear() {
        store.clear()
    }
}
