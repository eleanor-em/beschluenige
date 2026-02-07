import Foundation
import Testing
@testable import beschluenige_Watch_App

private let testDMSample = DeviceMotionSample(
    timestamp: Date(), roll: 0.1, pitch: 0.2, yaw: 0.3,
    rotationRateX: 1.0, rotationRateY: 2.0, rotationRateZ: 3.0,
    userAccelerationX: 0.01, userAccelerationY: 0.02, userAccelerationZ: 0.03,
    heading: 90.0
)

@MainActor
struct WorkoutManagerEdgeCaseTests {

    @Test func samplesIgnoredWhenNoWorkoutHR() async throws {
        let stub = StubHeartRateProvider()
        let stubLocation = StubLocationProvider()
        let stubMotion = StubMotionProvider()
        let manager = WorkoutManager(
            provider: stub,
            locationProvider: stubLocation,
            motionProvider: stubMotion
        )
        try await manager.startRecording()
        manager.currentWorkout = nil

        stub.sendSamples([
            HeartRateSample(timestamp: Date(), beatsPerMinute: 80),
        ])
        await Task.yield()

        #expect(manager.heartRateSampleCount == 0)
        manager.state = .idle
    }

    @Test func samplesIgnoredWhenNoWorkoutLocation() async throws {
        let stub = StubHeartRateProvider()
        let stubLocation = StubLocationProvider()
        let stubMotion = StubMotionProvider()
        let manager = WorkoutManager(
            provider: stub,
            locationProvider: stubLocation,
            motionProvider: stubMotion
        )
        try await manager.startRecording()
        manager.currentWorkout = nil

        stubLocation.sendSamples([
            LocationSample(
                timestamp: Date(), latitude: 43.0, longitude: -79.0,
                altitude: 76.0, horizontalAccuracy: 5.0, verticalAccuracy: 8.0,
                speed: 3.0, course: 90.0
            ),
        ])
        await Task.yield()

        #expect(manager.locationSampleCount == 0)
        manager.state = .idle
    }

    @Test func samplesIgnoredWhenNoWorkoutAccelerometer() async throws {
        let stub = StubHeartRateProvider()
        let stubLocation = StubLocationProvider()
        let stubMotion = StubMotionProvider()
        let manager = WorkoutManager(
            provider: stub,
            locationProvider: stubLocation,
            motionProvider: stubMotion
        )
        try await manager.startRecording()
        manager.currentWorkout = nil

        stubMotion.sendAccelSamples([
            AccelerometerSample(timestamp: Date(), x: 0.1, y: -0.2, z: 0.98),
        ])
        await Task.yield()

        #expect(manager.accelerometerSampleCount == 0)
        manager.state = .idle
    }

    @Test func samplesIgnoredWhenNoWorkoutDeviceMotion() async throws {
        let stub = StubHeartRateProvider()
        let stubLocation = StubLocationProvider()
        let stubMotion = StubMotionProvider()
        let manager = WorkoutManager(
            provider: stub,
            locationProvider: stubLocation,
            motionProvider: stubMotion
        )
        try await manager.startRecording()
        manager.currentWorkout = nil

        stubMotion.sendDMSamples([testDMSample])
        await Task.yield()

        #expect(manager.deviceMotionSampleCount == 0)
        manager.state = .idle
    }

    @Test func flushCurrentChunkNoOpWhenNoWorkout() {
        let manager = WorkoutManager(
            provider: StubHeartRateProvider(),
            locationProvider: StubLocationProvider(),
            motionProvider: StubMotionProvider()
        )
        // state is .idle, currentWorkout is nil -- should return early
        manager.flushCurrentChunk()
        #expect(manager.chunkCount == 0)
    }

    @Test func flushCurrentChunkLogsErrorInUnexpectedState() {
        let manager = WorkoutManager(
            provider: StubHeartRateProvider(),
            locationProvider: StubLocationProvider(),
            motionProvider: StubMotionProvider()
        )
        // Set currentWorkout but leave state as .idle to trigger the error log
        manager.currentWorkout = Workout(startDate: Date())
        manager.flushCurrentChunk()
        // Should not crash; the error is logged internally
        #expect(manager.state == .idle)
    }

    @Test func startRecordingLogsErrorIfNotIdle() async throws {
        let manager = WorkoutManager(
            provider: StubHeartRateProvider(),
            locationProvider: StubLocationProvider(),
            motionProvider: StubMotionProvider()
        )
        try await manager.startRecording()
        // Call startRecording again while already recording -- should log error
        try await manager.startRecording()
        #expect(manager.state == .recording)
        manager.stopRecording()
    }

    @Test func stopRecordingLogsErrorIfNotRecording() {
        let manager = WorkoutManager(
            provider: StubHeartRateProvider(),
            locationProvider: StubLocationProvider(),
            motionProvider: StubMotionProvider()
        )
        // Call stopRecording while idle -- should log error
        manager.stopRecording()
        #expect(manager.state == .exporting)
    }

    @Test func emptyFlushDoesNotIncrementChunkCount() async throws {
        let stub = StubHeartRateProvider()
        let stubLocation = StubLocationProvider()
        let stubMotion = StubMotionProvider()
        let manager = WorkoutManager(
            provider: stub,
            locationProvider: stubLocation,
            motionProvider: stubMotion
        )

        try await manager.startRecording()

        // Flush with no samples -- should NOT increment chunkCount
        manager.flushCurrentChunk()

        #expect(manager.chunkCount == 0, "Empty flush should not increment chunkCount")

        manager.stopRecording()
    }
}
