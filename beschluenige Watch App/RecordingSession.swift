import Foundation

struct RecordingSession: Sendable {
    let startDate: Date
    var endDate: Date?
    var heartRateSamples: [HeartRateSample] = []
    var locationSamples: [LocationSample] = []
    var accelerometerSamples: [AccelerometerSample] = []
    var deviceMotionSamples: [DeviceMotionSample] = []

    var sampleCount: Int { heartRateSamples.count }
    var totalSampleCount: Int {
        heartRateSamples.count + locationSamples.count
            + accelerometerSamples.count + deviceMotionSamples.count
    }

    func csvData() -> Data {
        var csv = "type,timestamp,bpm,"
            + "lat,lon,alt,h_acc,v_acc,speed,course,"
            + "ax,ay,az,"
            + "roll,pitch,yaw,rot_x,rot_y,rot_z,user_ax,user_ay,user_az,heading\n"

        // Build (timestamp, row-string) tuples for sorting
        var rows: [(timestamp: Double, line: String)] = []

        // Empty-field separators per group.
        // GPS: 7 fields (lat..course) -> 6 internal commas + 1 trailing = 7
        // Accel: 3 fields (ax,ay,az) -> 2 internal commas + 1 trailing = 3
        // DM: 10 fields (roll..heading) -> 9 internal commas, no trailing = 9
        let emptyGPS = ",,,,,,,"
        let emptyAccel = ",,,"
        let emptyDM = ",,,,,,,,,"

        for s in heartRateSamples {
            let t = s.timestamp.timeIntervalSince1970
            rows.append((t, "H,\(t),\(s.beatsPerMinute),\(emptyGPS)\(emptyAccel)\(emptyDM)"))
        }

        for s in locationSamples {
            let t = s.timestamp.timeIntervalSince1970
            rows.append((
                t,
                "G,\(t),,"
                    + "\(s.latitude),\(s.longitude),\(s.altitude),"
                    + "\(s.horizontalAccuracy),\(s.verticalAccuracy),"
                    + "\(s.speed),\(s.course),"
                    + "\(emptyAccel)\(emptyDM)",
                ))
        }

        for s in accelerometerSamples {
            let t = s.timestamp.timeIntervalSince1970
            rows.append((
                t,
                "A,\(t),,\(emptyGPS)\(s.x),\(s.y),\(s.z),\(emptyDM)",
                ))
        }

        for s in deviceMotionSamples {
            let t = s.timestamp.timeIntervalSince1970
            rows.append((
                t,
                "M,\(t),,\(emptyGPS)\(emptyAccel)"
                    + "\(s.roll),\(s.pitch),\(s.yaw),"
                    + "\(s.rotationRateX),\(s.rotationRateY),\(s.rotationRateZ),"
                    + "\(s.userAccelerationX),\(s.userAccelerationY),\(s.userAccelerationZ),"
                    + "\(s.heading)",
                ))
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
        let prefix = isRunningTests ? "TEST_" : ""
        let fileName = "\(prefix)hr_\(formatter.string(from: startDate)).csv"

        let documentsDir = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!
        let fileURL = documentsDir.appendingPathComponent(fileName)
        try csvData().write(to: fileURL)
        return fileURL
    }
}
