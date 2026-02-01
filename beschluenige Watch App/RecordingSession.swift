import Foundation

struct RecordingSession: Sendable {
    let startDate: Date
    var endDate: Date?
    var samples: [HeartRateSample] = []

    var sampleCount: Int { samples.count }

    func csvData() -> Data {
        var csv = "timestamp,bpm\n"
        for sample in samples {
            let unix = sample.timestamp.timeIntervalSince1970
            csv += "\(unix),\(sample.beatsPerMinute)\n"
        }
        return Data(csv.utf8)
    }

    func saveLocally() throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let fileName = "hr_\(formatter.string(from: startDate)).csv"

        let documentsDir = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!
        let fileURL = documentsDir.appendingPathComponent(fileName)
        try csvData().write(to: fileURL)
        return fileURL
    }
}
