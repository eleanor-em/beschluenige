import Foundation
import Testing
@testable import beschluenige_Watch_App

struct RecordingSessionTests {

    @Test func sampleCount() {
        var session = RecordingSession(startDate: Date())
        #expect(session.sampleCount == 0)

        session.samples.append(HeartRateSample(timestamp: Date(), beatsPerMinute: 120))
        session.samples.append(HeartRateSample(timestamp: Date(), beatsPerMinute: 130))
        #expect(session.sampleCount == 2)
    }

    @Test func csvHeader() {
        let session = RecordingSession(startDate: Date())
        let csv = String(data: session.csvData(), encoding: .utf8)!
        #expect(csv == "timestamp,bpm\n")
    }

    @Test func csvContainsSamples() {
        let t1 = Date(timeIntervalSince1970: 1000)
        let t2 = Date(timeIntervalSince1970: 1005)

        var session = RecordingSession(startDate: t1)
        session.samples = [
            HeartRateSample(timestamp: t1, beatsPerMinute: 72),
            HeartRateSample(timestamp: t2, beatsPerMinute: 148),
        ]

        let csv = String(data: session.csvData(), encoding: .utf8)!
        let lines = csv.split(separator: "\n")

        #expect(lines.count == 3)
        #expect(lines[0] == "timestamp,bpm")
        #expect(lines[1] == "1000.0,72.0")
        #expect(lines[2] == "1005.0,148.0")
    }

    @Test func csvTimestampPrecision() {
        let t = Date(timeIntervalSince1970: 1706812345.678)
        var session = RecordingSession(startDate: t)
        session.samples = [
            HeartRateSample(timestamp: t, beatsPerMinute: 90),
        ]

        let csv = String(data: session.csvData(), encoding: .utf8)!
        let lines = csv.split(separator: "\n")
        let fields = lines[1].split(separator: ",")

        let timestamp = Double(fields[0])!
        #expect(abs(timestamp - 1706812345.678) < 0.001)
    }

    @Test func csvEmptySession() {
        let session = RecordingSession(startDate: Date())
        let csv = String(data: session.csvData(), encoding: .utf8)!
        #expect(csv.split(separator: "\n").count == 1)
    }

    @Test func endDateTracked() {
        var session = RecordingSession(startDate: Date())
        #expect(session.endDate == nil)

        let end = Date()
        session.endDate = end
        #expect(session.endDate == end)
    }
}

@MainActor
struct WorkoutManagerTests {

    @Test func startRecordingCreatesSession() async throws {
        let mock = MockHeartRateProvider()
        let manager = WorkoutManager(provider: mock)

        try await manager.startRecording()

        #expect(manager.isRecording)
        #expect(manager.currentSession != nil)
        #expect(manager.currentSession?.sampleCount == 0)
    }

    @Test func stopRecordingSetsEndDate() async throws {
        let mock = MockHeartRateProvider()
        let manager = WorkoutManager(provider: mock)

        try await manager.startRecording()
        manager.stopRecording()

        #expect(!manager.isRecording)
        #expect(manager.currentSession?.endDate != nil)
    }

    @Test func samplesFlowThroughProvider() async throws {
        let mock = MockHeartRateProvider()
        let manager = WorkoutManager(provider: mock)

        try await manager.startRecording()

        let t = Date()
        mock.sendSamples([
            HeartRateSample(timestamp: t, beatsPerMinute: 120),
            HeartRateSample(timestamp: t.addingTimeInterval(1), beatsPerMinute: 130),
        ])

        // Give the MainActor task a chance to run
        try await Task.sleep(for: .milliseconds(50))

        #expect(manager.currentSession?.sampleCount == 2)
        #expect(manager.currentHeartRate == 130)
        #expect(manager.lastSampleDate == t.addingTimeInterval(1))
    }

    @Test func stopClearsSampleDelivery() async throws {
        let mock = MockHeartRateProvider()
        let manager = WorkoutManager(provider: mock)

        try await manager.startRecording()
        manager.stopRecording()

        mock.sendSamples([
            HeartRateSample(timestamp: Date(), beatsPerMinute: 99),
        ])

        try await Task.sleep(for: .milliseconds(50))

        // Samples after stop should not be delivered
        #expect(manager.currentSession?.sampleCount == 0)
    }
}
