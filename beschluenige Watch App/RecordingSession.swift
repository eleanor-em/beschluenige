import Foundation

struct RecordingSession: Sendable {
    let startDate: Date
    var endDate: Date?
    var heartRateSamples: [HeartRateSample] = []
    var locationSamples: [LocationSample] = []
    var accelerometerSamples: [AccelerometerSample] = []

    var sampleCount: Int { heartRateSamples.count }
    var totalSampleCount: Int {
        heartRateSamples.count + locationSamples.count + accelerometerSamples.count
    }

    func csvData() -> Data {
        var csv = "type,timestamp,bpm,lat,lon,alt,h_acc,v_acc,speed,course,ax,ay,az\n"

        // Build (type, timestamp, row-string) tuples for sorting
        var rows: [(timestamp: Double, line: String)] = []

        for s in heartRateSamples {
            let t = s.timestamp.timeIntervalSince1970
            rows.append((t, "H,\(t),\(s.beatsPerMinute),,,,,,,,,,"))
        }

        for s in locationSamples {
            let t = s.timestamp.timeIntervalSince1970
            rows.append((
                t,
                "G,\(t),,\(s.latitude),\(s.longitude),\(s.altitude),"
                    + "\(s.horizontalAccuracy),\(s.verticalAccuracy),"
                    + "\(s.speed),\(s.course),,,"
            ))
        }

        for s in accelerometerSamples {
            let t = s.timestamp.timeIntervalSince1970
            rows.append((t, "A,\(t),,,,,,,,\(s.x),\(s.y),\(s.z)"))
        }

        rows.sort { $0.timestamp < $1.timestamp }

        for row in rows {
            csv += row.line + "\n"
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
