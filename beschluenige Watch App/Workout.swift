import Foundation

struct Workout: Sendable {
    let startDate: Date
    var workoutId: String
    var endDate: Date?
    var heartRateSamples: [HeartRateSample] = []
    var locationSamples: [LocationSample] = []
    var accelerometerSamples: [AccelerometerSample] = []
    var deviceMotionSamples: [DeviceMotionSample] = []
    var nextChunkIndex: Int = 0
    var chunkURLs: [URL] = []
    var cumulativeSampleCount: Int = 0

    init(startDate: Date) {
        self.startDate = startDate
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        self.workoutId = formatter.string(from: startDate)
    }

    var sampleCount: Int { heartRateSamples.count }
    var totalSampleCount: Int {
        heartRateSamples.count + locationSamples.count
            + accelerometerSamples.count + deviceMotionSamples.count
    }

    // CBOR chunk: Map(4) { 0: HR, 1: GPS, 2: accel, 3: device motion }
    // Each value is a definite-length array of definite-length Float64 arrays.
    func cborData() -> Data {
        var enc = CBOREncoder()
        enc.encodeMapHeader(count: 4)

        // Key 0: heart rate -- [[ts, bpm], ...]
        enc.encodeUInt(0)
        enc.encodeArrayHeader(count: heartRateSamples.count)
        for s in heartRateSamples {
            enc.encodeFloat64Array([
                s.timestamp.timeIntervalSince1970,
                s.beatsPerMinute,
            ])
        }

        // Key 1: GPS -- [[ts, lat, lon, alt, h_acc, v_acc, speed, course], ...]
        enc.encodeUInt(1)
        enc.encodeArrayHeader(count: locationSamples.count)
        for s in locationSamples {
            enc.encodeFloat64Array([
                s.timestamp.timeIntervalSince1970,
                s.latitude, s.longitude, s.altitude,
                s.horizontalAccuracy, s.verticalAccuracy,
                s.speed, s.course,
            ])
        }

        // Key 2: accelerometer -- [[ts, x, y, z], ...]
        enc.encodeUInt(2)
        enc.encodeArrayHeader(count: accelerometerSamples.count)
        for s in accelerometerSamples {
            enc.encodeFloat64Array([
                s.timestamp.timeIntervalSince1970,
                s.x, s.y, s.z,
            ])
        }

        // Key 3: device motion -- [[ts, r, p, y, rx, ry, rz, ax, ay, az, hdg], ...]
        enc.encodeUInt(3)
        enc.encodeArrayHeader(count: deviceMotionSamples.count)
        for s in deviceMotionSamples {
            enc.encodeFloat64Array([
                s.timestamp.timeIntervalSince1970,
                s.roll, s.pitch, s.yaw,
                s.rotationRateX, s.rotationRateY, s.rotationRateZ,
                s.userAccelerationX, s.userAccelerationY, s.userAccelerationZ,
                s.heading,
            ])
        }

        return enc.data
    }

    mutating func flushChunk() throws -> URL? {
        guard totalSampleCount > 0 else { return nil }

        let data = cborData()
        let prefix = isRunningTests ? "TEST_" : ""
        let fileName = "\(prefix)workout_\(workoutId)_\(nextChunkIndex).cbor"

        let documentsDir = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!
        let fileURL = documentsDir.appendingPathComponent(fileName)
        try data.write(to: fileURL)

        heartRateSamples.removeAll(keepingCapacity: false)
        locationSamples.removeAll(keepingCapacity: false)
        accelerometerSamples.removeAll(keepingCapacity: false)
        deviceMotionSamples.removeAll(keepingCapacity: false)

        chunkURLs.append(fileURL)
        nextChunkIndex += 1
        return fileURL
    }

    mutating func finalizeChunks() throws -> [URL] {
        _ = try flushChunk()
        return chunkURLs
    }
}
