import Foundation
import Testing
@testable import beschluenige_Watch_App

private let testDMSample = DeviceMotionSample(
    timestamp: Date(), roll: 0.1, pitch: 0.2, yaw: 0.3,
    rotationRateX: 1.0, rotationRateY: 2.0, rotationRateZ: 3.0,
    userAccelerationX: 0.01, userAccelerationY: 0.02, userAccelerationZ: 0.03,
    heading: 90.0
)

struct WorkoutTests {

    @Test func sampleCount() {
        var workout = Workout(startDate: Date())
        #expect(workout.sampleCount == 0)

        workout.heartRateSamples.append(HeartRateSample(timestamp: Date(), beatsPerMinute: 120))
        workout.heartRateSamples.append(HeartRateSample(timestamp: Date(), beatsPerMinute: 130))
        #expect(workout.sampleCount == 2)
    }

    @Test func totalSampleCount() {
        var workout = Workout(startDate: Date())
        #expect(workout.totalSampleCount == 0)

        workout.heartRateSamples.append(HeartRateSample(timestamp: Date(), beatsPerMinute: 120))
        workout.locationSamples.append(LocationSample(
            timestamp: Date(), latitude: 43.0, longitude: -79.0,
            altitude: 76.0, horizontalAccuracy: 5.0, verticalAccuracy: 8.0,
            speed: 3.0, course: 90.0
        ))
        workout.accelerometerSamples.append(AccelerometerSample(
            timestamp: Date(), x: 0.1, y: -0.2, z: 0.98
        ))
        workout.deviceMotionSamples.append(testDMSample)
        #expect(workout.totalSampleCount == 4)
    }

    @Test func cborEmptyWorkout() throws {
        let workout = Workout(startDate: Date())
        let data = workout.cborData()
        var dec = CBORDecoder(data: data)
        let mapCount = try dec.decodeMapHeader()
        #expect(mapCount == 4)
        for key in 0..<4 {
            #expect(try dec.decodeUInt() == UInt64(key))
            let count = try dec.decodeArrayHeader()
            #expect(count == 0)
        }
        #expect(dec.isAtEnd)
    }

    @Test func cborContainsHeartRateSamples() throws {
        let t1 = Date(timeIntervalSince1970: 1000)
        let t2 = Date(timeIntervalSince1970: 1005)

        var workout = Workout(startDate: t1)
        workout.heartRateSamples = [
            HeartRateSample(timestamp: t1, beatsPerMinute: 72),
            HeartRateSample(timestamp: t2, beatsPerMinute: 148),
        ]

        let data = workout.cborData()
        var dec = CBORDecoder(data: data)
        let mapCount = try dec.decodeMapHeader()
        #expect(mapCount == 4)

        // Key 0: HR
        #expect(try dec.decodeUInt() == 0)
        let hrCount = try dec.decodeArrayHeader()
        #expect(hrCount == 2)
        let hr0 = try dec.decodeFloat64Array()
        #expect(hr0.count == 2)
        #expect(hr0[0] == 1000.0)
        #expect(hr0[1] == 72.0)
        let hr1 = try dec.decodeFloat64Array()
        #expect(hr1[0] == 1005.0)
        #expect(hr1[1] == 148.0)

        // Skip remaining keys
        for _ in 1..<4 {
            _ = try dec.decodeUInt()
            let count = try dec.decodeArrayHeader()
            #expect(count == 0)
        }
        #expect(dec.isAtEnd)
    }

    @Test func cborContainsLocationSamples() throws {
        let t = Date(timeIntervalSince1970: 2000)

        var workout = Workout(startDate: t)
        workout.locationSamples = [
            LocationSample(
                timestamp: t, latitude: 43.65, longitude: -79.38,
                altitude: 76.0, horizontalAccuracy: 5.0, verticalAccuracy: 8.0,
                speed: 3.5, course: 180.0
            ),
        ]

        let data = workout.cborData()
        var dec = CBORDecoder(data: data)
        _ = try dec.decodeMapHeader()

        // Key 0: HR (empty)
        _ = try dec.decodeUInt()
        #expect(try dec.decodeArrayHeader() == 0)

        // Key 1: GPS
        #expect(try dec.decodeUInt() == 1)
        #expect(try dec.decodeArrayHeader() == 1)
        let gps = try dec.decodeFloat64Array()
        #expect(gps.count == 8)
        #expect(gps[0] == 2000.0)
        #expect(gps[1] == 43.65)
        #expect(gps[2] == -79.38)
        #expect(gps[3] == 76.0)
        #expect(gps[4] == 5.0)
        #expect(gps[5] == 8.0)
        #expect(gps[6] == 3.5)
        #expect(gps[7] == 180.0)
    }

    @Test func cborContainsAccelerometerSamples() throws {
        let t = Date(timeIntervalSince1970: 3000)

        var workout = Workout(startDate: t)
        workout.accelerometerSamples = [
            AccelerometerSample(timestamp: t, x: 0.01, y: -0.02, z: 0.98),
        ]

        let data = workout.cborData()
        var dec = CBORDecoder(data: data)
        _ = try dec.decodeMapHeader()

        // Skip keys 0, 1
        for _ in 0..<2 {
            _ = try dec.decodeUInt()
            #expect(try dec.decodeArrayHeader() == 0)
        }

        // Key 2: accel
        #expect(try dec.decodeUInt() == 2)
        #expect(try dec.decodeArrayHeader() == 1)
        let accel = try dec.decodeFloat64Array()
        #expect(accel.count == 4)
        #expect(accel[0] == 3000.0)
        #expect(accel[1] == 0.01)
        #expect(accel[2] == -0.02)
        #expect(accel[3] == 0.98)
    }

    @Test func cborContainsDeviceMotionSamples() throws {
        let t = Date(timeIntervalSince1970: 4000)

        var workout = Workout(startDate: t)
        workout.deviceMotionSamples = [
            DeviceMotionSample(
                timestamp: t, roll: 0.1, pitch: 0.2, yaw: 0.3,
                rotationRateX: 1.0, rotationRateY: 2.0, rotationRateZ: 3.0,
                userAccelerationX: 0.01, userAccelerationY: 0.02, userAccelerationZ: 0.03,
                heading: 90.0
            ),
        ]

        let data = workout.cborData()
        var dec = CBORDecoder(data: data)
        _ = try dec.decodeMapHeader()

        // Skip keys 0, 1, 2
        for _ in 0..<3 {
            _ = try dec.decodeUInt()
            #expect(try dec.decodeArrayHeader() == 0)
        }

        // Key 3: device motion
        #expect(try dec.decodeUInt() == 3)
        #expect(try dec.decodeArrayHeader() == 1)
        let dm = try dec.decodeFloat64Array()
        #expect(dm.count == 11)
        #expect(dm[0] == 4000.0)
        #expect(dm[1] == 0.1)   // roll
        #expect(dm[2] == 0.2)   // pitch
        #expect(dm[3] == 0.3)   // yaw
        #expect(dm[4] == 1.0)   // rotationRateX
        #expect(dm[5] == 2.0)   // rotationRateY
        #expect(dm[6] == 3.0)   // rotationRateZ
        #expect(dm[7] == 0.01)  // userAccelerationX
        #expect(dm[8] == 0.02)  // userAccelerationY
        #expect(dm[9] == 0.03)  // userAccelerationZ
        #expect(dm[10] == 90.0) // heading
    }

    @Test func cborTimestampPrecision() throws {
        let t = Date(timeIntervalSince1970: 1706812345.678)
        var workout = Workout(startDate: t)
        workout.heartRateSamples = [
            HeartRateSample(timestamp: t, beatsPerMinute: 90),
        ]

        let data = workout.cborData()
        var dec = CBORDecoder(data: data)
        _ = try dec.decodeMapHeader()
        _ = try dec.decodeUInt()
        _ = try dec.decodeArrayHeader()
        let hr = try dec.decodeFloat64Array()
        #expect(abs(hr[0] - 1706812345.678) < 0.001)
    }

    @Test func cborAllSensorTypes() throws {
        let t1 = Date(timeIntervalSince1970: 1000)
        let t2 = Date(timeIntervalSince1970: 1001)
        let t3 = Date(timeIntervalSince1970: 1002)

        var workout = Workout(startDate: t1)
        workout.heartRateSamples = [
            HeartRateSample(timestamp: t1, beatsPerMinute: 100),
        ]
        workout.locationSamples = [
            LocationSample(
                timestamp: t2, latitude: 43.0, longitude: -79.0,
                altitude: 76.0, horizontalAccuracy: 5.0, verticalAccuracy: 8.0,
                speed: 2.0, course: 90.0
            ),
        ]
        workout.accelerometerSamples = [
            AccelerometerSample(timestamp: t3, x: 0.1, y: 0.2, z: 0.3),
        ]

        let data = workout.cborData()
        var dec = CBORDecoder(data: data)
        let mapCount = try dec.decodeMapHeader()
        #expect(mapCount == 4)

        // Key 0: 1 HR sample
        #expect(try dec.decodeUInt() == 0)
        #expect(try dec.decodeArrayHeader() == 1)
        _ = try dec.decodeFloat64Array()

        // Key 1: 1 GPS sample
        #expect(try dec.decodeUInt() == 1)
        #expect(try dec.decodeArrayHeader() == 1)
        _ = try dec.decodeFloat64Array()

        // Key 2: 1 accel sample
        #expect(try dec.decodeUInt() == 2)
        #expect(try dec.decodeArrayHeader() == 1)
        _ = try dec.decodeFloat64Array()

        // Key 3: 0 DM samples
        #expect(try dec.decodeUInt() == 3)
        #expect(try dec.decodeArrayHeader() == 0)

        #expect(dec.isAtEnd)
    }

    @Test func endDateTracked() {
        var workout = Workout(startDate: Date())
        #expect(workout.endDate == nil)

        let end = Date()
        workout.endDate = end
        #expect(workout.endDate == end)
    }

    @Test func workoutIdDerivedFromStartDate() {
        let t = Date(timeIntervalSince1970: 1706812345)
        let workout = Workout(startDate: t)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        #expect(workout.workoutId == formatter.string(from: t))
    }

    @Test func flushChunkWritesCborAndClearsArrays() throws {
        let t = Date(timeIntervalSince1970: 1706812345)
        var workout = Workout(startDate: t)
        workout.heartRateSamples = [
            HeartRateSample(timestamp: t, beatsPerMinute: 100),
        ]
        workout.accelerometerSamples = [
            AccelerometerSample(timestamp: t, x: 0.1, y: 0.2, z: 0.3),
        ]

        let url = try workout.flushChunk()

        #expect(url != nil)
        #expect(workout.heartRateSamples.isEmpty)
        #expect(workout.accelerometerSamples.isEmpty)
        #expect(workout.locationSamples.isEmpty)
        #expect(workout.deviceMotionSamples.isEmpty)
        #expect(workout.nextChunkIndex == 1)
        #expect(workout.chunkURLs.count == 1)

        // Verify the file is valid CBOR with expected structure
        let fileData = try Data(contentsOf: url!)
        var dec = CBORDecoder(data: fileData)
        let mapCount = try dec.decodeMapHeader()
        #expect(mapCount == 4)
        #expect(url!.lastPathComponent.contains("_0.cbor"))

        try FileManager.default.removeItem(at: url!)
    }

    @Test func flushChunkReturnsNilWhenEmpty() throws {
        var workout = Workout(startDate: Date())

        let url = try workout.flushChunk()

        #expect(url == nil)
        #expect(workout.nextChunkIndex == 0)
        #expect(workout.chunkURLs.isEmpty)
    }

    @Test func flushChunkIncrementsIndex() throws {
        let t = Date(timeIntervalSince1970: 1706899999)
        var workout = Workout(startDate: t)

        workout.heartRateSamples = [
            HeartRateSample(timestamp: t, beatsPerMinute: 80),
        ]
        let url0 = try workout.flushChunk()

        workout.heartRateSamples = [
            HeartRateSample(timestamp: t, beatsPerMinute: 90),
        ]
        let url1 = try workout.flushChunk()

        #expect(url0!.lastPathComponent.contains("_0.cbor"))
        #expect(url1!.lastPathComponent.contains("_1.cbor"))
        #expect(workout.nextChunkIndex == 2)
        #expect(workout.chunkURLs.count == 2)

        try FileManager.default.removeItem(at: url0!)
        try FileManager.default.removeItem(at: url1!)
    }

    @Test func finalizeChunksFlushesRemaining() throws {
        let t = Date(timeIntervalSince1970: 1706800000)
        var workout = Workout(startDate: t)

        // First chunk
        workout.heartRateSamples = [
            HeartRateSample(timestamp: t, beatsPerMinute: 80),
        ]
        _ = try workout.flushChunk()

        // Remaining samples
        workout.heartRateSamples = [
            HeartRateSample(timestamp: t, beatsPerMinute: 90),
        ]

        let urls = try workout.finalizeChunks()

        #expect(urls.count == 2)
        #expect(workout.heartRateSamples.isEmpty)

        for url in urls {
            try FileManager.default.removeItem(at: url)
        }
    }
}

@MainActor
struct WorkoutManagerTests {

    @Test func stateIsIdleByDefault() {
        let manager = WorkoutManager(
            provider: StubHeartRateProvider(),
            locationProvider: StubLocationProvider(),
            motionProvider: StubMotionProvider()
        )
        #expect(manager.state == .idle)
        #expect(manager.currentWorkout == nil)
    }

    @Test func finishExportingResetsToIdle() async throws {
        let manager = WorkoutManager(
            provider: StubHeartRateProvider(),
            locationProvider: StubLocationProvider(),
            motionProvider: StubMotionProvider()
        )
        try await manager.startRecording()
        manager.stopRecording()
        #expect(manager.state == .exporting)
        #expect(manager.currentWorkout != nil)

        manager.finishExporting()
        #expect(manager.state == .idle)
        #expect(manager.currentWorkout == nil)
    }

    @Test func finishExportingFromIdleLogsError() {
        let manager = WorkoutManager(
            provider: StubHeartRateProvider(),
            locationProvider: StubLocationProvider(),
            motionProvider: StubMotionProvider()
        )
        // Should not crash; logs an error internally
        manager.finishExporting()
        #expect(manager.state == .idle)
    }

    @Test func startRecordingCreatesWorkout() async throws {
        let stub = StubHeartRateProvider()
        let stubLocation = StubLocationProvider()
        let stubMotion = StubMotionProvider()
        let manager = WorkoutManager(
            provider: stub,
            locationProvider: stubLocation,
            motionProvider: stubMotion
        )

        try await manager.startRecording()

        #expect(manager.state == .recording)
        #expect(manager.currentWorkout != nil)
        #expect(manager.currentWorkout?.sampleCount == 0)

        manager.stopRecording()
    }

    @Test func stopRecordingSetsEndDate() async throws {
        let stub = StubHeartRateProvider()
        let stubLocation = StubLocationProvider()
        let stubMotion = StubMotionProvider()
        let manager = WorkoutManager(
            provider: stub,
            locationProvider: stubLocation,
            motionProvider: stubMotion
        )

        try await manager.startRecording()
        manager.stopRecording()

        #expect(manager.state == .exporting)
        #expect(manager.currentWorkout?.endDate != nil)
    }

    @Test func samplesFlowThroughProvider() async throws {
        let stub = StubHeartRateProvider()
        let stubLocation = StubLocationProvider()
        let stubMotion = StubMotionProvider()
        let manager = WorkoutManager(
            provider: stub,
            locationProvider: stubLocation,
            motionProvider: stubMotion
        )

        try await manager.startRecording()

        let t = Date()
        stub.sendSamples([
            HeartRateSample(timestamp: t, beatsPerMinute: 120),
            HeartRateSample(timestamp: t.addingTimeInterval(1), beatsPerMinute: 130),
        ])

        await Task.yield()

        #expect(manager.currentWorkout?.sampleCount == 2)
        #expect(manager.currentHeartRate == 130)
        #expect(manager.lastSampleDate() == nil)

        manager.stopRecording()
    }

    @Test func locationSamplesFlowThroughProvider() async throws {
        let stub = StubHeartRateProvider()
        let stubLocation = StubLocationProvider()
        let stubMotion = StubMotionProvider()
        let manager = WorkoutManager(
            provider: stub,
            locationProvider: stubLocation,
            motionProvider: stubMotion
        )

        try await manager.startRecording()

        stubLocation.sendSamples([
            LocationSample(
                timestamp: Date(), latitude: 43.65, longitude: -79.38,
                altitude: 76.0, horizontalAccuracy: 5.0, verticalAccuracy: 8.0,
                speed: 3.0, course: 90.0
            ),
        ])

        await Task.yield()

        #expect(manager.currentWorkout?.locationSamples.count == 1)
        #expect(manager.locationSampleCount == 1)

        manager.stopRecording()
    }

    @Test func accelerometerSamplesFlowThroughProvider() async throws {
        let stub = StubHeartRateProvider()
        let stubLocation = StubLocationProvider()
        let stubMotion = StubMotionProvider()
        let manager = WorkoutManager(
            provider: stub,
            locationProvider: stubLocation,
            motionProvider: stubMotion
        )

        try await manager.startRecording()

        stubMotion.sendAccelSamples([
            AccelerometerSample(timestamp: Date(), x: 0.1, y: -0.2, z: 0.98),
            AccelerometerSample(timestamp: Date(), x: 0.2, y: -0.1, z: 0.97),
        ])

        await Task.yield()

        #expect(manager.currentWorkout?.accelerometerSamples.count == 2)
        #expect(manager.accelerometerSampleCount == 2)

        manager.stopRecording()
    }

    @Test func deviceMotionSamplesFlowThroughProvider() async throws {
        let stub = StubHeartRateProvider()
        let stubLocation = StubLocationProvider()
        let stubMotion = StubMotionProvider()
        let manager = WorkoutManager(
            provider: stub,
            locationProvider: stubLocation,
            motionProvider: stubMotion
        )

        try await manager.startRecording()

        stubMotion.sendDMSamples([testDMSample, testDMSample])

        await Task.yield()

        #expect(manager.currentWorkout?.deviceMotionSamples.count == 2)
        #expect(manager.deviceMotionSampleCount == 2)

        manager.stopRecording()
    }

    @Test func emptySampleArrayDoesNotUpdateHeartRate() async throws {
        let stub = StubHeartRateProvider()
        let stubLocation = StubLocationProvider()
        let stubMotion = StubMotionProvider()
        let manager = WorkoutManager(
            provider: stub,
            locationProvider: stubLocation,
            motionProvider: stubMotion
        )

        try await manager.startRecording()
        stub.sendSamples([])
        await Task.yield()

        #expect(manager.currentHeartRate == 0)
        #expect(manager.lastSampleDate() == nil)

        manager.stopRecording()
    }

    @Test func lateSamplesPreservedAfterStopHR() async throws {
        let stub = StubHeartRateProvider()
        let stubLocation = StubLocationProvider()
        let stubMotion = StubMotionProvider()
        let manager = WorkoutManager(
            provider: stub,
            locationProvider: stubLocation,
            motionProvider: stubMotion
        )

        try await manager.startRecording()

        stub.sendSamples([
            HeartRateSample(timestamp: Date(), beatsPerMinute: 99),
        ])

        manager.stopRecording()

        await Task.yield()

        // Late-arriving sample is captured in-memory (will be flushed during export)
        #expect(manager.currentWorkout?.sampleCount == 1)
    }

    @Test func lateSamplesPreservedAfterStopLocation() async throws {
        let stub = StubHeartRateProvider()
        let stubLocation = StubLocationProvider()
        let stubMotion = StubMotionProvider()
        let manager = WorkoutManager(
            provider: stub,
            locationProvider: stubLocation,
            motionProvider: stubMotion
        )

        try await manager.startRecording()

        stubLocation.sendSamples([
            LocationSample(
                timestamp: Date(), latitude: 43.65, longitude: -79.38,
                altitude: 76.0, horizontalAccuracy: 5.0, verticalAccuracy: 8.0,
                speed: 3.0, course: 90.0
            ),
        ])

        manager.stopRecording()

        await Task.yield()

        // Late-arriving sample is captured in-memory (will be flushed during export)
        #expect(manager.locationSampleCount == 1)
    }

    @Test func lateSamplesPreservedAfterStopAccelerometer() async throws {
        let stub = StubHeartRateProvider()
        let stubLocation = StubLocationProvider()
        let stubMotion = StubMotionProvider()
        let manager = WorkoutManager(
            provider: stub,
            locationProvider: stubLocation,
            motionProvider: stubMotion
        )

        try await manager.startRecording()

        stubMotion.sendAccelSamples([
            AccelerometerSample(timestamp: Date(), x: 0.1, y: -0.2, z: 0.98),
        ])

        manager.stopRecording()

        await Task.yield()

        // Late-arriving sample is captured in-memory (will be flushed during export)
        #expect(manager.accelerometerSampleCount == 1)
    }

    @Test func lateSamplesPreservedAfterStopDeviceMotion() async throws {
        let stub = StubHeartRateProvider()
        let stubLocation = StubLocationProvider()
        let stubMotion = StubMotionProvider()
        let manager = WorkoutManager(
            provider: stub,
            locationProvider: stubLocation,
            motionProvider: stubMotion
        )

        try await manager.startRecording()

        stubMotion.sendDMSamples([testDMSample])

        manager.stopRecording()

        await Task.yield()

        // Late-arriving sample is captured in-memory (will be flushed during export)
        #expect(manager.deviceMotionSampleCount == 1)
    }

    @Test func flushCurrentChunkPreservesCumulativeCounts() async throws {
        let stub = StubHeartRateProvider()
        let stubLocation = StubLocationProvider()
        let stubMotion = StubMotionProvider()
        let manager = WorkoutManager(
            provider: stub,
            locationProvider: stubLocation,
            motionProvider: stubMotion
        )
        manager.flushInterval = 0.1

        try await manager.startRecording()

        // Add first batch
        stub.sendSamples([
            HeartRateSample(timestamp: Date(), beatsPerMinute: 120),
        ])
        stubLocation.sendSamples([
            LocationSample(
                timestamp: Date(), latitude: 43.0, longitude: -79.0,
                altitude: 76.0, horizontalAccuracy: 5.0, verticalAccuracy: 8.0,
                speed: 3.0, course: 90.0
            ),
        ])
        stubMotion.sendAccelSamples([
            AccelerometerSample(timestamp: Date(), x: 0.1, y: 0.2, z: 0.3),
        ])
        stubMotion.sendDMSamples([testDMSample])
        await Task.yield()

        // Flush
        manager.flushCurrentChunk()

        // In-memory arrays should be empty
        #expect(manager.currentWorkout?.heartRateSamples.isEmpty == true)
        #expect(manager.currentWorkout?.locationSamples.isEmpty == true)
        #expect(manager.currentWorkout?.accelerometerSamples.isEmpty == true)
        #expect(manager.currentWorkout?.deviceMotionSamples.isEmpty == true)

        // But cumulative counts are preserved
        #expect(manager.heartRateSampleCount == 1)
        #expect(manager.locationSampleCount == 1)
        #expect(manager.accelerometerSampleCount == 1)
        #expect(manager.deviceMotionSampleCount == 1)

        // Add second batch
        stub.sendSamples([
            HeartRateSample(timestamp: Date(), beatsPerMinute: 130),
            HeartRateSample(timestamp: Date(), beatsPerMinute: 140),
        ])
        await Task.yield()

        // Cumulative + new
        #expect(manager.heartRateSampleCount == 3)

        manager.stopRecording()

        // Clean up chunk files
        if let workout = manager.currentWorkout {
            for url in workout.chunkURLs {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    @Test func handleFlushTimerCallsFlush() async throws {
        let stub = StubHeartRateProvider()
        let stubLocation = StubLocationProvider()
        let stubMotion = StubMotionProvider()
        let manager = WorkoutManager(
            provider: stub,
            locationProvider: stubLocation,
            motionProvider: stubMotion
        )
        manager.flushInterval = 0.01

        try await manager.startRecording()

        stub.sendSamples([
            HeartRateSample(timestamp: Date(), beatsPerMinute: 80),
        ])
        await Task.yield()

        // Let the timer fire so the Timer closure is covered
        try await Task.sleep(for: .milliseconds(100))

        #expect(manager.currentWorkout?.chunkURLs.count ?? 0 >= 1)

        manager.stopRecording()

        if let workout = manager.currentWorkout {
            for url in workout.chunkURLs {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    @Test func flushCurrentChunkAfterStopCoversGuard() async throws {
        let stub = StubHeartRateProvider()
        let stubLocation = StubLocationProvider()
        let stubMotion = StubMotionProvider()
        let manager = WorkoutManager(
            provider: stub,
            locationProvider: stubLocation,
            motionProvider: stubMotion
        )
        manager.flushInterval = 0.1

        try await manager.startRecording()

        stub.sendSamples([
            HeartRateSample(timestamp: Date(), beatsPerMinute: 90),
        ])
        await Task.yield()

        manager.stopRecording()

        #expect(manager.state == .exporting)
        #expect(manager.currentWorkout != nil)
        manager.flushCurrentChunk()

        if let workout = manager.currentWorkout {
            for url in workout.chunkURLs {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    @Test func flushCurrentChunkLogsErrorOnWriteFailure() async throws {
        let stub = StubHeartRateProvider()
        let stubLocation = StubLocationProvider()
        let stubMotion = StubMotionProvider()
        let manager = WorkoutManager(
            provider: stub,
            locationProvider: stubLocation,
            motionProvider: stubMotion
        )
        try await manager.startRecording()
        manager.currentWorkout!.workoutId = "write-failure-\(UUID())"

        stub.sendSamples([
            HeartRateSample(timestamp: Date(), beatsPerMinute: 110),
        ])
        await Task.yield()

        // Create a directory at the chunk file path to block the write.
        // Data.write(to:) throws when the target is a directory.
        let documentsDir = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!
        let workoutId = manager.currentWorkout!.workoutId
        let chunkIndex = manager.currentWorkout!.nextChunkIndex
        let blocker = documentsDir.appendingPathComponent(
            "TEST_workout_\(workoutId)_\(chunkIndex).cbor"
        )
        // Create a subdirectory inside so the path is a directory, not a file
        let sub = blocker.appendingPathComponent("x")
        try FileManager.default.createDirectory(
            at: sub, withIntermediateDirectories: true
        )

        manager.flushCurrentChunk()

        // Clean up
        try? FileManager.default.removeItem(at: blocker)
        manager.stopRecording()
        if let workout = manager.currentWorkout {
            for url in workout.chunkURLs {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    @Test func stopRecordingFlushesRemainingChunk() async throws {
        let stub = StubHeartRateProvider()
        let stubLocation = StubLocationProvider()
        let stubMotion = StubMotionProvider()
        let manager = WorkoutManager(
            provider: stub,
            locationProvider: stubLocation,
            motionProvider: stubMotion
        )
        manager.flushInterval = 0.1

        try await manager.startRecording()

        stub.sendSamples([
            HeartRateSample(timestamp: Date(), beatsPerMinute: 100),
        ])
        await Task.yield()

        manager.stopRecording()

        #expect(manager.currentWorkout?.chunkURLs.isEmpty == false)

        // Clean up chunk files
        if let workout = manager.currentWorkout {
            for url in workout.chunkURLs {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    @Test func lateArrivingSamplesNotLostAfterStop() async throws {
        let stub = StubHeartRateProvider()
        let stubLocation = StubLocationProvider()
        let stubMotion = StubMotionProvider()
        let manager = WorkoutManager(
            provider: stub,
            locationProvider: stubLocation,
            motionProvider: stubMotion
        )

        try await manager.startRecording()

        // Send initial samples and confirm they arrive
        let t = Date()
        stub.sendSamples([
            HeartRateSample(timestamp: t, beatsPerMinute: 100),
        ])
        await Task.yield()
        #expect(manager.heartRateSampleCount == 1)

        // Send more samples (enqueued as Task { @MainActor } but not yet executed)
        stub.sendSamples([
            HeartRateSample(timestamp: t.addingTimeInterval(1), beatsPerMinute: 110),
        ])
        stubLocation.sendSamples([
            LocationSample(
                timestamp: t.addingTimeInterval(1), latitude: 43.0, longitude: -79.0,
                altitude: 76.0, horizontalAccuracy: 5.0, verticalAccuracy: 8.0,
                speed: 3.0, course: 90.0
            ),
        ])
        stubMotion.sendAccelSamples([
            AccelerometerSample(timestamp: t.addingTimeInterval(1), x: 0.1, y: 0.2, z: 0.3),
        ])

        // Stop immediately in the same synchronous frame
        manager.stopRecording()

        // Let in-flight tasks drain
        await Task.yield()

        // Late-arriving samples should be captured in the workout's in-memory arrays
        // (they will be flushed during export via finalizeChunks)
        #expect(manager.currentWorkout?.heartRateSamples.count == 1, "Late HR sample was lost")
        #expect(manager.currentWorkout?.locationSamples.count == 1, "Late location sample was lost")
        #expect(
            manager.currentWorkout?.accelerometerSamples.count == 1,
            "Late accelerometer sample was lost"
        )

        if let workout = manager.currentWorkout {
            for url in workout.chunkURLs {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

}
