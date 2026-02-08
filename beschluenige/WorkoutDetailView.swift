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
            LabeledContent("Status") {
                if record.isComplete {
                    Label("Complete", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Text(
                        "Receiving \(record.receivedChunks.count)"
                            + "/\(record.totalChunks) chunks"
                    )
                    .foregroundStyle(.orange)
                }
            }
            LabeledContent("File Size") {
                Text(String(format: "%.1f MB", record.fileSizeMB))
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
                Text(formattedCount(summary.accelerometerCount))
            }
            LabeledContent("Device Motion") {
                Text(formattedCount(summary.deviceMotionCount))
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

        for _ in 0..<mapCount {
            let key = Int(try dec.decodeUInt())
            let definiteCount = try dec.decodeArrayHeader()

            if let count = definiteCount {
                // Definite-length (chunk format)
                for _ in 0..<count {
                    let sample = try dec.decodeFloat64Array()
                    processSample(
                        key: key, sample: sample,
                        hrCount: &hrCount, hrMin: &hrMin, hrMax: &hrMax, hrSum: &hrSum,
                        gpsCount: &gpsCount, maxSpeed: &maxSpeed,
                        accelCount: &accelCount, dmCount: &dmCount,
                        firstTimestamp: &firstTimestamp, lastTimestamp: &lastTimestamp
                    )
                }
            } else {
                // Indefinite-length (merged format)
                while try !dec.isBreak() {
                    let sample = try dec.decodeFloat64Array()
                    processSample(
                        key: key, sample: sample,
                        hrCount: &hrCount, hrMin: &hrMin, hrMax: &hrMax, hrSum: &hrSum,
                        gpsCount: &gpsCount, maxSpeed: &maxSpeed,
                        accelCount: &accelCount, dmCount: &dmCount,
                        firstTimestamp: &firstTimestamp, lastTimestamp: &lastTimestamp
                    )
                }
                try dec.decodeBreak()
            }
        }

        return WorkoutSummary(
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

    private static func processSample(
        key: Int,
        sample: [Double],
        hrCount: inout Int,
        hrMin: inout Double,
        hrMax: inout Double,
        hrSum: inout Double,
        gpsCount: inout Int,
        maxSpeed: inout Double,
        accelCount: inout Int,
        dmCount: inout Int,
        firstTimestamp: inout Double?,
        lastTimestamp: inout Double?
    ) {
        guard !sample.isEmpty else { return }
        let ts = sample[0]
        if firstTimestamp == nil || ts < firstTimestamp! {
            firstTimestamp = ts
        }
        if lastTimestamp == nil || ts > lastTimestamp! {
            lastTimestamp = ts
        }

        switch key {
        case 0: // Heart rate: [ts, bpm]
            guard sample.count >= 2 else { return }
            let bpm = sample[1]
            hrCount += 1
            hrMin = min(hrMin, bpm)
            hrMax = max(hrMax, bpm)
            hrSum += bpm
        case 1: // GPS: [ts, lat, lon, alt, h_acc, v_acc, speed, course]
            gpsCount += 1
            if sample.count >= 7 {
                let speed = sample[6]
                if speed >= 0 { // CLLocation reports -1 for invalid speed
                    maxSpeed = max(maxSpeed, speed)
                }
            }
        case 2: // Accelerometer
            accelCount += 1
        case 3: // Device motion
            dmCount += 1
        default:
            break
        }
    }

    private func formattedDuration(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        let seconds = Int(interval) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func formattedCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}

struct DiskFile: Identifiable {
    let name: String
    let sizeBytes: Int64

    var id: String { name }

    var formattedSize: String {
        if sizeBytes >= 1_048_576 {
            return String(format: "%.1f MB", Double(sizeBytes) / 1_048_576)
        } else if sizeBytes >= 1024 {
            return String(format: "%.1f KB", Double(sizeBytes) / 1024)
        }
        return "\(sizeBytes) B"
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
