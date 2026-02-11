import SwiftUI

struct WorkoutDetailView: View {
    let record: WatchConnectivityManager.WorkoutRecord
    var connectivityManager = WatchConnectivityManager.shared
    @State private var diskFiles: [DiskFile] = []
    @State private var selectedTab: DetailTab = .summary
    @Environment(\.dismiss) private var dismiss

    init(
        record: WatchConnectivityManager.WorkoutRecord,
        connectivityManager: WatchConnectivityManager = .shared,
        initialSelectedTab: DetailTab = .summary,
        initialDiskFiles: [DiskFile] = []
    ) {
        self.record = record
        self.connectivityManager = connectivityManager
        _diskFiles = State(initialValue: initialDiskFiles)
        _selectedTab = State(initialValue: initialSelectedTab)
    }

    private var summary: WorkoutSummary? {
        connectivityManager.decodedSummaries[record.workoutId]
    }

    private var timeseries: WorkoutTimeseries? {
        connectivityManager.decodedTimeseries[record.workoutId]
    }

    private var decodingProgress: Double? {
        connectivityManager.decodingProgress[record.workoutId]
    }

    private var loadError: String? {
        connectivityManager.decodingErrors[record.workoutId]
    }

    enum DetailTab: String, CaseIterable {
        case summary = "Summary"
        case charts = "Charts"
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $selectedTab) {
                ForEach(DetailTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            switch selectedTab {
            case .summary:
                summaryList
            case .charts:
                chartsContent
            }
        }
        .navigationTitle("Workout")
        .task {
            loadDiskFiles()
            connectivityManager.decodeWorkout(record)
        }
    }

    // MARK: - Summary Tab

    var summaryList: some View {
        List {
            metadataSection
            if let progress = decodingProgress {
                Section {
                    ProgressView(value: progress) {
                        Text("Decoding workout data...")
                    } currentValueLabel: {
                        Text("\(Int(progress * 100))%")
                    }
                    .padding(.vertical, 4)
                }
            }
            if let error = loadError {
                Section {
                    Label(error, systemImage: "exclamation.triangle")
                        .foregroundStyle(.orange)
                }
            }
            if let summary {
                if summary.heartRateCount > 0 {
                    heartRateSection(summary)
                }
                if summary.gpsCount > 0 {
                    gpsSection(summary)
                }
                sampleCountsSection(summary)
            }
            filesSection
            actionsSection
        }
    }

    // MARK: - Charts Tab

    var chartsContent: some View {
        Group {
            if let error = loadError {
                VStack {
                    Spacer()
                    Label(error, systemImage: "exclamation.triangle")
                        .foregroundStyle(.orange)
                    Spacer()
                }
            } else if let ts = timeseries {
                ScrollView {
                    VStack(spacing: 24) {
                        if let progress = decodingProgress {
                            ProgressView(value: progress) {
                                Text("Loading data...")
                            } currentValueLabel: {
                                Text("\(Int(progress * 100))%")
                            }
                        }
                        TimeseriesView(
                            title: "Heart Rate",
                            unit: "bpm",
                            color: .red,
                            points: ts.heartRate
                        )
                    }
                    .padding()
                }
            } else if decodingProgress != nil {
                VStack {
                    Spacer()
                    ProgressView("Loading chart data...")
                    Spacer()
                }
            } else {
                VStack {
                    Spacer()
                    ContentUnavailableView(
                        "No Data",
                        systemImage: "chart.xyaxis.line",
                        description: Text("Workout data is not available yet.")
                    )
                    Spacer()
                }
            }
        }
    }

    // MARK: - Summary Sections

    var metadataSection: some View {
        Section("Overview") {
            LabeledContent("Date") {
                Text(record.startDate, style: .date)
            }
            LabeledContent("Time") {
                Text(record.startDate, style: .time)
            }
            if let summary, let duration = summary.duration {
                LabeledContent("Duration") {
                    Text(formattedDuration(duration))
                }
            }
            if record.isComplete {
                NavigationLink {
                    ChunkListView(workoutId: record.workoutId)
                } label: {
                    LabeledContent("Status") {
                        HStack(spacing: 4) {
                            Text("Complete")
                            Image(systemName: "checkmark.circle.fill")
                        }
                        .foregroundStyle(.green)
                    }
                }
            } else {
                NavigationLink {
                    ChunkListView(workoutId: record.workoutId)
                } label: {
                    LabeledContent("Status") {
                        Text(
                            "Receiving \(record.receivedChunks.count)"
                                + "/\(record.totalChunks) chunks"
                        )
                        .foregroundStyle(.orange)
                    }
                }
            }
            LabeledContent("File Size") {
                Text(record.fileSizeBytes.formattedFileSize)
            }
        }
    }

    func heartRateSection(_ summary: WorkoutSummary) -> some View {
        Section("Heart Rate") {
            LabeledContent("Samples") {
                Text("\(summary.heartRateCount)")
            }
            if let min = summary.heartRateMin {
                LabeledContent("Min") {
                    Text("\(Int(min)) bpm")
                }
            }
            if let max = summary.heartRateMax {
                LabeledContent("Max") {
                    Text("\(Int(max)) bpm")
                }
            }
            if let avg = summary.heartRateAvg {
                LabeledContent("Average") {
                    Text("\(Int(avg)) bpm")
                }
            }
        }
    }

    func gpsSection(_ summary: WorkoutSummary) -> some View {
        Section("GPS") {
            LabeledContent("Samples") {
                Text("\(summary.gpsCount)")
            }
            if let maxSpeed = summary.maxSpeed, maxSpeed > 0 {
                LabeledContent("Max Speed") {
                    Text(String(format: "%.1f km/h", maxSpeed * 3.6))
                }
            }
        }
    }

    func sampleCountsSection(_ summary: WorkoutSummary) -> some View {
        Section("Sensor Data") {
            LabeledContent("Accelerometer") {
                Text(summary.accelerometerCount.roundedWithAbbreviations)
            }
            LabeledContent("Device Motion") {
                Text(summary.deviceMotionCount.roundedWithAbbreviations)
            }
        }
    }

    var actionsSection: some View {
        Section {
            if let mergedURL = record.mergedFileURL {
                ShareLink(item: mergedURL) {
                    Label("Share Workout", systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    var filesSection: some View {
        Section("Files on Disk") {
            if diskFiles.isEmpty {
                Text("No files found")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(diskFiles) { file in
                    LabeledContent(file.name) {
                        Text(file.formattedSize)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    func loadDiskFiles() {
        guard let documentsDir = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first else { return }

        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: documentsDir,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return }

        let id = record.workoutId
        diskFiles = contents
            .filter { $0.lastPathComponent.contains(id) }
            .compactMap { Self.diskFile(for: $0) }
            .sorted { $0.name < $1.name }
    }

    static func diskFile(for url: URL) -> DiskFile {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        return DiskFile(name: url.lastPathComponent, sizeBytes: Int64(size))
    }

    func formattedDuration(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        let seconds = Int(interval) % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m \(seconds)s"
        }
        return "\(minutes)m \(seconds)s"
    }
}

struct DiskFile: Identifiable {
    let name: String
    let sizeBytes: Int64

    var id: String { name }

    var formattedSize: String { sizeBytes.formattedFileSize }
}

struct ChunkListView: View {
    let workoutId: String
    var connectivityManager = WatchConnectivityManager.shared
    @State private var alertType: RetransmissionAlert?

    enum RetransmissionAlert: Identifiable {
        case alreadyMerged
        case denied
        case unreachable
        case error(String)

        var id: String {
            switch self {
            case .alreadyMerged: return "alreadyMerged"
            case .denied: return "denied"
            case .unreachable: return "unreachable"
            case .error(let msg): return "error:\(msg)"
            }
        }
    }

    private var record: WatchConnectivityManager.WorkoutRecord? {
        connectivityManager.workouts.first { $0.workoutId == workoutId }
    }

    var body: some View {
        if let record {
            List {
                manifestRow(record)
                ForEach(0..<record.totalChunks, id: \.self) { index in
                    chunkRow(record: record, index: index)
                }
            }
            .navigationTitle(
                "\(record.receivedChunks.count)/\(record.totalChunks) Chunks"
            )
            .refreshable {
                let result = await connectivityManager.requestRetransmission(
                    workoutId: workoutId
                )
                alertType = Self.alertType(for: result)
            }
            .alert(item: $alertType) { alert in
                Self.alertFor(alert)
            }
        }
    }

    func manifestRow(_ record: WatchConnectivityManager.WorkoutRecord) -> some View {
        Label {
            if record.manifest != nil {
                Text("Manifest received")
            } else {
                Text("Manifest pending")
            }
        } icon: {
            Image(
                systemName: record.manifest != nil
                    ? "checkmark.circle.fill"
                    : "circle.dashed"
            )
            .foregroundStyle(record.manifest != nil ? .green : .orange)
        }
    }

    static func alertType(
        for result: WatchConnectivityManager.RetransmissionResult
    ) -> RetransmissionAlert? {
        switch result {
        case .accepted, .nothingToRequest:
            return nil
        case .alreadyMerged:
            return .alreadyMerged
        case .denied:
            return .denied
        case .unreachable:
            return .unreachable
        case .notFound:
            return .error("Workout not found on watch.")
        case .error(let msg):
            return .error(msg)
        }
    }

    static func alertFor(_ alert: RetransmissionAlert) -> Alert {
        switch alert {
        case .alreadyMerged:
            Alert(
                title: Text("Already Merged"),
                message: Text(
                    "Nothing to verify -- this workout has already been merged."
                )
            )
        case .denied:
            Alert(
                title: Text("Transfer In Progress"),
                message: Text(
                    "The watch is still sending this workout."
                        + " Please wait for it to finish."
                )
            )
        case .unreachable:
            Alert(
                title: Text("Watch Unreachable"),
                message: Text(
                    "Make sure your Apple Watch is nearby and unlocked."
                )
            )
        case .error(let msg):
            Alert(
                title: Text("Error"),
                message: Text(msg)
            )
        }
    }

    func chunkRow(record: WatchConnectivityManager.WorkoutRecord, index: Int) -> some View {
        let received = record.receivedChunks.contains { $0.chunkIndex == index }
        let failed = record.failedChunks.contains(index)
        let hasManifest = record.manifest != nil

        let label: String
        let icon: String
        let color: Color

        if failed {
            label = "Chunk \(index) - Failed"
            icon = "xmark.circle.fill"
            color = .red
        } else if received, hasManifest {
            label = "Chunk \(index) - Verified"
            icon = "checkmark.circle.fill"
            color = .green
        } else if received {
            label = "Chunk \(index) - Unverified"
            icon = "checkmark.circle.fill"
            color = .blue
        } else {
            label = "Chunk \(index)"
            icon = "circle.dashed"
            color = .orange
        }

        return Label {
            Text(label)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(color)
        }
    }
}
