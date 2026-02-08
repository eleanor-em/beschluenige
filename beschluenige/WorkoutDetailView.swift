import SwiftUI
import os

struct WorkoutDetailView: View {
    let record: WatchConnectivityManager.WorkoutRecord
    var connectivityManager = WatchConnectivityManager.shared
    @State private var summary: WorkoutSummary?
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var diskFiles: [DiskFile] = []
    @Environment(\.dismiss) private var dismiss

    private let logger = Logger(
        subsystem: "net.lnor.beschluenige",
        category: "WorkoutDetail"
    )

    var body: some View {
        List {
            metadataSection
            if isLoading {
                Section {
                    HStack {
                        ProgressView()
                        Text("Analyzing workout data...")
                            .foregroundStyle(.secondary)
                            .padding(.leading, 8)
                    }
                }
            } else if let error = loadError {
                Section {
                    Label(error, systemImage: "exclamation.triangle")
                        .foregroundStyle(.orange)
                }
            } else if let summary {
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
        .navigationTitle("Workout")
        .task {
            loadDiskFiles()
            await loadSummary()
        }
    }

    private var metadataSection: some View {
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

    private func heartRateSection(_ summary: WorkoutSummary) -> some View {
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

    private func gpsSection(_ summary: WorkoutSummary) -> some View {
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

    private func sampleCountsSection(_ summary: WorkoutSummary) -> some View {
        Section("Sensor Data") {
            LabeledContent("Accelerometer") {
                Text(summary.accelerometerCount.roundedWithAbbreviations)
            }
            LabeledContent("Device Motion") {
                Text(summary.deviceMotionCount.roundedWithAbbreviations)
            }
        }
    }

    private var actionsSection: some View {
        Section {
            if let mergedURL = record.mergedFileURL {
                ShareLink(item: mergedURL) {
                    Label("Share Workout", systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    private var filesSection: some View {
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

    private func loadDiskFiles() {
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
            .compactMap { url -> DiskFile? in
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                return DiskFile(name: url.lastPathComponent, sizeBytes: Int64(size))
            }
            .sorted { $0.name < $1.name }
    }

    private func loadSummary() async {
        guard let url = record.mergedFileURL else { return }
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await Task.detached {
                try Self.decodeSummary(from: url)
            }.value
            summary = result
        } catch {
            logger.error("Failed to decode workout: \(error.localizedDescription)")
            loadError = "Could not read workout data"
        }
    }

    private static func decodeSummary(from url: URL) throws -> WorkoutSummary {
        let data = try Data(contentsOf: url)
        var dec = CBORDecoder(data: data)
        let mapCount = try dec.decodeMapHeader()
        var acc = SummaryAccumulator()

        for _ in 0..<mapCount {
            let key = Int(try dec.decodeUInt())
            let definiteCount = try dec.decodeArrayHeader()

            if let count = definiteCount {
                for _ in 0..<count {
                    acc.process(key: key, sample: try dec.decodeFloat64Array())
                }
            } else {
                while try !dec.isBreak() {
                    acc.process(key: key, sample: try dec.decodeFloat64Array())
                }
                try dec.decodeBreak()
            }
        }

        return acc.makeSummary()
    }

    private func formattedDuration(_ interval: TimeInterval) -> String {
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
                switch result {
                case .accepted, .nothingToRequest:
                    break
                case .alreadyMerged:
                    alertType = .alreadyMerged
                case .denied:
                    alertType = .denied
                case .unreachable:
                    alertType = .unreachable
                case .notFound:
                    alertType = .error("Workout not found on watch.")
                case .error(let msg):
                    alertType = .error(msg)
                }
            }
            .alert(item: $alertType) { alert in
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
        }
    }

    private func manifestRow(_ record: WatchConnectivityManager.WorkoutRecord) -> some View {
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

private struct SummaryAccumulator {
    var hrCount = 0
    var hrMin = Double.greatestFiniteMagnitude
    var hrMax = -Double.greatestFiniteMagnitude
    var hrSum = 0.0
    var gpsCount = 0
    var maxSpeed = 0.0
    var accelCount = 0
    var dmCount = 0
    var firstTimestamp: Double?
    var lastTimestamp: Double?

    mutating func process(key: Int, sample: [Double]) {
        guard !sample.isEmpty else { return }
        let ts = sample[0]
        if firstTimestamp == nil || ts < firstTimestamp! { firstTimestamp = ts }
        if lastTimestamp == nil || ts > lastTimestamp! { lastTimestamp = ts }

        switch key {
        case 0: processHeartRate(sample)
        case 1: processGPS(sample)
        case 2: accelCount += 1
        case 3: dmCount += 1
        default: break
        }
    }

    private mutating func processHeartRate(_ sample: [Double]) {
        guard sample.count >= 2 else { return }
        let bpm = sample[1]
        hrCount += 1
        hrMin = min(hrMin, bpm)
        hrMax = max(hrMax, bpm)
        hrSum += bpm
    }

    private mutating func processGPS(_ sample: [Double]) {
        gpsCount += 1
        if sample.count >= 7 {
            let speed = sample[6]
            if speed >= 0 { maxSpeed = max(maxSpeed, speed) }
        }
    }

    func makeSummary() -> WorkoutSummary {
        WorkoutSummary(
            heartRateCount: hrCount,
            heartRateMin: hrCount > 0 ? hrMin : nil,
            heartRateMax: hrCount > 0 ? hrMax : nil,
            heartRateAvg: hrCount > 0 ? hrSum / Double(hrCount) : nil,
            gpsCount: gpsCount,
            maxSpeed: gpsCount > 0 ? maxSpeed : nil,
            accelerometerCount: accelCount,
            deviceMotionCount: dmCount,
            firstTimestamp: firstTimestamp.map { Date(timeIntervalSince1970: $0) },
            lastTimestamp: lastTimestamp.map { Date(timeIntervalSince1970: $0) }
        )
    }
}

struct WorkoutSummary {
    let heartRateCount: Int
    let heartRateMin: Double?
    let heartRateMax: Double?
    let heartRateAvg: Double?
    let gpsCount: Int
    let maxSpeed: Double?
    let accelerometerCount: Int
    let deviceMotionCount: Int
    let firstTimestamp: Date?
    let lastTimestamp: Date?

    var duration: TimeInterval? {
        guard let first = firstTimestamp, let last = lastTimestamp else { return nil }
        let d = last.timeIntervalSince(first)
        return d > 0 ? d : nil
    }
}
