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

    @Test func csvHeader() {
        let workout = Workout(startDate: Date())
        let csv = String(data: workout.csvData(), encoding: .utf8)!
        let lines = csv.split(separator: "\n")
        #expect(lines.count == 1)
        #expect(
            lines[0]
                == "type,timestamp,bpm,"
                + "lat,lon,alt,h_acc,v_acc,speed,course,"
                + "ax,ay,az,"
                + "roll,pitch,yaw,rot_x,rot_y,rot_z,user_ax,user_ay,user_az,heading"
        )
    }

    @Test func csvContainsHeartRateSamples() {
        let t1 = Date(timeIntervalSince1970: 1000)
        let t2 = Date(timeIntervalSince1970: 1005)

        var workout = Workout(startDate: t1)
        workout.heartRateSamples = [
            HeartRateSample(timestamp: t1, beatsPerMinute: 72),
            HeartRateSample(timestamp: t2, beatsPerMinute: 148),
        ]

        let csv = String(data: workout.csvData(), encoding: .utf8)!
        let lines = csv.split(separator: "\n")

        #expect(lines.count == 3)
        // 23 columns: type,ts,bpm + 20 empty = 22 commas
        #expect(lines[1].hasPrefix("H,1000.0,72.0,"))
        #expect(lines[1].split(separator: ",", omittingEmptySubsequences: false).count == 23)
    }

    @Test func csvContainsLocationSamples() {
        let t = Date(timeIntervalSince1970: 2000)

        var workout = Workout(startDate: t)
        workout.locationSamples = [
            LocationSample(
                timestamp: t, latitude: 43.65, longitude: -79.38,
                altitude: 76.0, horizontalAccuracy: 5.0, verticalAccuracy: 8.0,
                speed: 3.5, course: 180.0
            ),
        ]

        let csv = String(data: workout.csvData(), encoding: .utf8)!
        let lines = csv.split(separator: "\n")

        #expect(lines.count == 2)
        #expect(lines[1].hasPrefix("G,2000.0,,43.65,-79.38,76.0,5.0,8.0,3.5,180.0,"))
        #expect(lines[1].split(separator: ",", omittingEmptySubsequences: false).count == 23)
    }

    @Test func csvContainsAccelerometerSamples() {
        let t = Date(timeIntervalSince1970: 3000)

        var workout = Workout(startDate: t)
        workout.accelerometerSamples = [
            AccelerometerSample(timestamp: t, x: 0.01, y: -0.02, z: 0.98),
        ]

        let csv = String(data: workout.csvData(), encoding: .utf8)!
        let lines = csv.split(separator: "\n")
        let fields = lines[1].split(separator: ",", omittingEmptySubsequences: false)

        #expect(lines.count == 2)
        #expect(fields.count == 23)
        #expect(fields[0] == "A")
        #expect(fields[10] == "0.01")
        #expect(fields[11] == "-0.02")
        #expect(fields[12] == "0.98")
    }

    @Test func csvContainsDeviceMotionSamples() {
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

        let csv = String(data: workout.csvData(), encoding: .utf8)!
        let lines = csv.split(separator: "\n")
        let fields = lines[1].split(separator: ",", omittingEmptySubsequences: false)

        #expect(lines.count == 2)
        #expect(fields.count == 23)
        #expect(fields[0] == "M")
        #expect(fields[13] == "0.1")   // roll
        #expect(fields[14] == "0.2")   // pitch
        #expect(fields[15] == "0.3")   // yaw
        #expect(fields[16] == "1.0")   // rot_x
        #expect(fields[19] == "0.01")  // user_ax
        #expect(fields[22] == "90.0")  // heading
    }

    @Test func csvSortsByTimestamp() {
        let t1 = Date(timeIntervalSince1970: 1000)
        let t2 = Date(timeIntervalSince1970: 1001)
        let t3 = Date(timeIntervalSince1970: 1002)

        var workout = Workout(startDate: t1)
        workout.accelerometerSamples = [
            AccelerometerSample(timestamp: t3, x: 0.1, y: 0.2, z: 0.3),
        ]
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

        let csv = String(data: workout.csvData(), encoding: .utf8)!
        let lines = csv.split(separator: "\n")

        #expect(lines.count == 4)
        #expect(lines[1].hasPrefix("H,1000.0"))
        #expect(lines[2].hasPrefix("G,1001.0"))
        #expect(lines[3].hasPrefix("A,1002.0"))
    }

    @Test func csvTimestampPrecision() {
        let t = Date(timeIntervalSince1970: 1706812345.678)
        var workout = Workout(startDate: t)
        workout.heartRateSamples = [
            HeartRateSample(timestamp: t, beatsPerMinute: 90),
        ]

        let csv = String(data: workout.csvData(), encoding: .utf8)!
        let lines = csv.split(separator: "\n")
        let fields = lines[1].split(separator: ",", omittingEmptySubsequences: false)

        let timestamp = Double(fields[1])!
        #expect(abs(timestamp - 1706812345.678) < 0.001)
    }

    @Test func csvEmptyWorkout() {
        let workout = Workout(startDate: Date())
        let csv = String(data: workout.csvData(), encoding: .utf8)!
        #expect(csv.split(separator: "\n").count == 1)
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

    @Test func flushChunkWritesCsvAndClearsArrays() throws {
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

        let content = try String(contentsOf: url!, encoding: .utf8)
        #expect(content.contains("H,"))
        #expect(content.contains("A,"))
        #expect(url!.lastPathComponent.contains("_0.csv"))

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

        #expect(url0!.lastPathComponent.contains("_0.csv"))
        #expect(url1!.lastPathComponent.contains("_1.csv"))
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

        #expect(manager.isRecording)
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

        #expect(!manager.isRecording)
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
        #expect(manager.lastSampleDate() == t.addingTimeInterval(1))

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

    @Test func stopClearsSampleDelivery() async throws {
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

        // After stop, samples are flushed to disk, so in-memory count is 0
        #expect(manager.currentWorkout?.sampleCount == 0)
    }

    @Test func stopClearsLocationSampleDelivery() async throws {
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

        #expect(manager.locationSampleCount == 0)
    }

    @Test func stopClearsAccelerometerSampleDelivery() async throws {
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

        #expect(manager.accelerometerSampleCount == 0)
    }

    @Test func stopClearsDeviceMotionSampleDelivery() async throws {
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

        #expect(manager.deviceMotionSampleCount == 0)
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

        // isRecording is now false, but currentWorkout is non-nil.
        // This covers the right side of the || guard in flushCurrentChunk.
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
            "TEST_workout_\(workoutId)_\(chunkIndex).csv"
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
}
