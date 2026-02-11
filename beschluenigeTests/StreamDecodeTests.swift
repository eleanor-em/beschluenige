import Foundation
import Testing
@testable import beschluenige

@MainActor
struct SummaryAccumulatorTests {

    @Test func processHeartRate() {
        var acc = SummaryAccumulator()
        // HR sample: [timestamp, bpm]
        acc.process(key: 0, sample: [1000.0, 80.0])
        acc.process(key: 0, sample: [1001.0, 120.0])
        acc.process(key: 0, sample: [1002.0, 100.0])

        let summary = acc.makeSummary()
        #expect(summary.heartRateCount == 3)
        #expect(summary.heartRateMin == 80.0)
        #expect(summary.heartRateMax == 120.0)
        #expect(summary.heartRateAvg == 100.0)
    }

    @Test func processGPS() {
        var acc = SummaryAccumulator()
        // GPS sample: [ts, lat, lon, alt, h_acc, v_acc, speed, course]
        acc.process(key: 1, sample: [1000.0, 0, 0, 0, 0, 0, 5.0, 0])
        acc.process(key: 1, sample: [1001.0, 0, 0, 0, 0, 0, 10.0, 0])

        let summary = acc.makeSummary()
        #expect(summary.gpsCount == 2)
        #expect(summary.maxSpeed == 10.0)
    }

    @Test func processGPSNegativeSpeedIgnored() {
        var acc = SummaryAccumulator()
        acc.process(key: 1, sample: [1000.0, 0, 0, 0, 0, 0, -1.0, 0])

        let summary = acc.makeSummary()
        #expect(summary.gpsCount == 1)
        #expect(summary.maxSpeed == 0.0)
    }

    @Test func processAccelerometer() {
        var acc = SummaryAccumulator()
        acc.process(key: 2, sample: [1000.0, 0.1, 0.2, 0.3])
        acc.process(key: 2, sample: [1001.0, 0.4, 0.5, 0.6])

        let summary = acc.makeSummary()
        #expect(summary.accelerometerCount == 2)
    }

    @Test func processDeviceMotion() {
        var acc = SummaryAccumulator()
        acc.process(key: 3, sample: [1000.0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])

        let summary = acc.makeSummary()
        #expect(summary.deviceMotionCount == 1)
    }

    @Test func processEmptySampleIgnored() {
        var acc = SummaryAccumulator()
        acc.process(key: 0, sample: [])

        let summary = acc.makeSummary()
        #expect(summary.heartRateCount == 0)
    }

    @Test func processUnknownKeyIgnored() {
        var acc = SummaryAccumulator()
        acc.process(key: 99, sample: [1000.0])

        let summary = acc.makeSummary()
        #expect(summary.heartRateCount == 0)
        #expect(summary.gpsCount == 0)
        #expect(summary.accelerometerCount == 0)
        #expect(summary.deviceMotionCount == 0)
    }

    @Test func timestampTracking() {
        var acc = SummaryAccumulator()
        acc.process(key: 0, sample: [1002.0, 100.0])
        acc.process(key: 1, sample: [1000.0, 0, 0, 0, 0, 0, 5.0, 0])
        acc.process(key: 2, sample: [1005.0, 0, 0, 0])

        let summary = acc.makeSummary()
        #expect(summary.firstTimestamp == Date(timeIntervalSince1970: 1000.0))
        #expect(summary.lastTimestamp == Date(timeIntervalSince1970: 1005.0))
    }

    @Test func makeSummaryNilValuesWhenEmpty() {
        let acc = SummaryAccumulator()
        let summary = acc.makeSummary()
        #expect(summary.heartRateCount == 0)
        #expect(summary.heartRateMin == nil)
        #expect(summary.heartRateMax == nil)
        #expect(summary.heartRateAvg == nil)
        #expect(summary.gpsCount == 0)
        #expect(summary.maxSpeed == nil)
        #expect(summary.firstTimestamp == nil)
        #expect(summary.lastTimestamp == nil)
    }

    @Test func hrSampleTooShortIgnored() {
        var acc = SummaryAccumulator()
        // Only timestamp, no BPM value
        acc.process(key: 0, sample: [1000.0])

        let summary = acc.makeSummary()
        #expect(summary.heartRateCount == 0)
    }

    @Test func gpsSampleTooShortNoSpeed() {
        var acc = SummaryAccumulator()
        // GPS sample with only 3 fields (no speed)
        acc.process(key: 1, sample: [1000.0, 1.0, 2.0])

        let summary = acc.makeSummary()
        #expect(summary.gpsCount == 1)
        #expect(summary.maxSpeed == 0.0)
    }
}

@MainActor
struct WorkoutSummaryTests {

    @Test func durationComputed() {
        let summary = WorkoutSummary(
            heartRateCount: 0,
            heartRateMin: nil,
            heartRateMax: nil,
            heartRateAvg: nil,
            gpsCount: 0,
            maxSpeed: nil,
            accelerometerCount: 0,
            deviceMotionCount: 0,
            firstTimestamp: Date(timeIntervalSince1970: 1000),
            lastTimestamp: Date(timeIntervalSince1970: 1300)
        )
        #expect(summary.duration == 300)
    }

    @Test func durationNilWhenNoTimestamps() {
        let summary = WorkoutSummary(
            heartRateCount: 0,
            heartRateMin: nil,
            heartRateMax: nil,
            heartRateAvg: nil,
            gpsCount: 0,
            maxSpeed: nil,
            accelerometerCount: 0,
            deviceMotionCount: 0,
            firstTimestamp: nil,
            lastTimestamp: nil
        )
        #expect(summary.duration == nil)
    }

    @Test func durationNilWhenZero() {
        let date = Date(timeIntervalSince1970: 1000)
        let summary = WorkoutSummary(
            heartRateCount: 0,
            heartRateMin: nil,
            heartRateMax: nil,
            heartRateAvg: nil,
            gpsCount: 0,
            maxSpeed: nil,
            accelerometerCount: 0,
            deviceMotionCount: 0,
            firstTimestamp: date,
            lastTimestamp: date
        )
        #expect(summary.duration == nil)
    }
}

@MainActor
struct TimeseriesAccumulatorTests {

    @Test func processHeartRate() {
        var acc = TimeseriesAccumulator()
        acc.process(key: 0, sample: [1000.0, 80.0])
        acc.process(key: 0, sample: [1001.0, 120.0])

        let ts = acc.makeTimeseries()
        #expect(ts.heartRate.count == 2)
        #expect(ts.heartRate[0].value == 80.0)
        #expect(ts.heartRate[1].value == 120.0)
        #expect(ts.heartRate[0].id == 0)
        #expect(ts.heartRate[1].id == 1)
    }

    @Test func processSpeedConvertsToKmh() {
        var acc = TimeseriesAccumulator()
        // GPS sample: [ts, lat, lon, alt, h_acc, v_acc, speed_m_s, course]
        acc.process(key: 1, sample: [1000.0, 0, 0, 0, 0, 0, 10.0, 0])

        let ts = acc.makeTimeseries()
        #expect(ts.speed.count == 1)
        #expect(ts.speed[0].value == 36.0) // 10 m/s * 3.6 = 36 km/h
    }

    @Test func processNegativeSpeedIgnored() {
        var acc = TimeseriesAccumulator()
        acc.process(key: 1, sample: [1000.0, 0, 0, 0, 0, 0, -1.0, 0])

        let ts = acc.makeTimeseries()
        #expect(ts.speed.isEmpty)
    }

    @Test func processEmptySampleIgnored() {
        var acc = TimeseriesAccumulator()
        acc.process(key: 0, sample: [])

        let ts = acc.makeTimeseries()
        #expect(ts.heartRate.isEmpty)
    }

    @Test func processHRSampleTooShortIgnored() {
        var acc = TimeseriesAccumulator()
        acc.process(key: 0, sample: [1000.0])

        let ts = acc.makeTimeseries()
        #expect(ts.heartRate.isEmpty)
    }

    @Test func processGPSSampleTooShortIgnored() {
        var acc = TimeseriesAccumulator()
        acc.process(key: 1, sample: [1000.0, 0, 0])

        let ts = acc.makeTimeseries()
        #expect(ts.speed.isEmpty)
    }

    @Test func processUnknownKeyIgnored() {
        var acc = TimeseriesAccumulator()
        acc.process(key: 2, sample: [1000.0, 0.1, 0.2, 0.3])
        acc.process(key: 3, sample: [1000.0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
        acc.process(key: 99, sample: [1000.0])

        let ts = acc.makeTimeseries()
        #expect(ts.heartRate.isEmpty)
        #expect(ts.speed.isEmpty)
    }
}

@MainActor
struct DecodeWorkoutTests {

    private func buildTestCBOR() -> Data {
        var enc = CBOREncoder()
        enc.encodeMapHeader(count: 4)
        enc.encodeUInt(0)
        enc.encodeIndefiniteArrayHeader()
        enc.encodeFloat64Array([1000.0, 80.0])
        enc.encodeFloat64Array([1001.0, 120.0])
        enc.encodeBreak()
        enc.encodeUInt(1)
        enc.encodeIndefiniteArrayHeader()
        enc.encodeFloat64Array([1000.0, 0, 0, 0, 0, 0, 5.0, 0])
        enc.encodeBreak()
        enc.encodeUInt(2)
        enc.encodeIndefiniteArrayHeader()
        enc.encodeFloat64Array([1000.0, 0.1, 0.2, 9.8])
        enc.encodeBreak()
        enc.encodeUInt(3)
        enc.encodeIndefiniteArrayHeader()
        enc.encodeBreak()
        return enc.data
    }

    private func cleanUp(_ manager: WatchConnectivityManager, workoutId: String) {
        manager.decodedSummaries.removeValue(forKey: workoutId)
        manager.decodedTimeseries.removeValue(forKey: workoutId)
        manager.decodingProgress.removeValue(forKey: workoutId)
        manager.decodingErrors.removeValue(forKey: workoutId)
        manager.workouts.removeAll { $0.workoutId == workoutId }
    }

    @Test func decodeWorkoutEndToEnd() async throws {
        let manager = WatchConnectivityManager.shared
        let workoutId = "decode_e2e_\(UUID().uuidString)"
        let fileName = "decode_test_\(UUID().uuidString).cbor"

        let documentsDir = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!
        let docURL = documentsDir.appendingPathComponent(fileName)
        try buildTestCBOR().write(to: docURL)
        defer { try? FileManager.default.removeItem(at: docURL) }

        var record = WatchConnectivityManager.WorkoutRecord(
            workoutId: workoutId,
            startDate: Date(timeIntervalSince1970: 1000),
            totalSampleCount: 4,
            totalChunks: 1
        )
        record.mergedFileName = fileName
        manager.workouts.append(record)
        defer { cleanUp(manager, workoutId: workoutId) }

        manager.decodeWorkout(record)

        for _ in 0..<50 {
            try await Task.sleep(for: .milliseconds(100))
            if manager.decodedSummaries[workoutId] != nil,
               manager.decodingProgress[workoutId] == nil { break }
        }

        let summary = manager.decodedSummaries[workoutId]
        #expect(summary?.heartRateCount == 2)
        #expect(summary?.heartRateMin == 80.0)
        #expect(summary?.heartRateMax == 120.0)
        #expect(summary?.gpsCount == 1)
        #expect(summary?.accelerometerCount == 1)
        #expect(summary?.deviceMotionCount == 0)

        let timeseries = manager.decodedTimeseries[workoutId]
        #expect(timeseries?.heartRate.count == 2)
        #expect(timeseries?.speed.count == 1)
        #expect(timeseries?.speed.first?.value == 18.0)
    }
}
