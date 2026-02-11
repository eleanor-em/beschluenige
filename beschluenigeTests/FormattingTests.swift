import CoreLocation
import Foundation
import HealthKit
import Testing
@testable import beschluenige

@MainActor
struct FormattingTests {

    // MARK: - Int64.formattedFileSize

    @Test func fileSizeBytes() {
        #expect(Int64(0).formattedFileSize == "0 B")
        #expect(Int64(512).formattedFileSize == "512 B")
        #expect(Int64(1023).formattedFileSize == "1023 B")
    }

    @Test func fileSizeKB() {
        #expect(Int64(1024).formattedFileSize == "1.0 KB")
        #expect(Int64(1536).formattedFileSize == "1.5 KB")
        #expect(Int64(1_048_575).formattedFileSize == "1024.0 KB")
    }

    @Test func fileSizeMB() {
        #expect(Int64(1_048_576).formattedFileSize == "1.0 MB")
        #expect(Int64(10_485_760).formattedFileSize == "10.0 MB")
    }

    // MARK: - Int.roundedWithAbbreviations

    @Test func abbreviationsPlain() {
        #expect(0.roundedWithAbbreviations == "0")
        #expect(42.roundedWithAbbreviations == "42")
        #expect(999.roundedWithAbbreviations == "999")
    }

    @Test func abbreviationsK() {
        #expect(1000.roundedWithAbbreviations == "1.0k")
        #expect(1500.roundedWithAbbreviations == "1.5k")
        #expect(999_999.roundedWithAbbreviations == "1000.0k")
    }

    @Test func abbreviationsM() {
        #expect(1_000_000.roundedWithAbbreviations == "1.0m")
        #expect(2_345_678.roundedWithAbbreviations == "2.3m")
    }

    // MARK: - Date.secondsOrMinutesSince

    @Test func elapsedSeconds() {
        let start = Date(timeIntervalSince1970: 1000)
        let end = Date(timeIntervalSince1970: 1030)
        #expect(end.secondsOrMinutesSince(start) == "30s")
    }

    @Test func elapsedZero() {
        let now = Date()
        #expect(now.secondsOrMinutesSince(now) == "0s")
    }

    @Test func elapsedJustUnderMinute() {
        let start = Date(timeIntervalSince1970: 1000)
        let end = Date(timeIntervalSince1970: 1059)
        #expect(end.secondsOrMinutesSince(start) == "59s")
    }

    @Test func elapsedExactlyOneMinute() {
        let start = Date(timeIntervalSince1970: 1000)
        let end = Date(timeIntervalSince1970: 1060)
        #expect(end.secondsOrMinutesSince(start) == "1m")
    }

    @Test func elapsedSeveralMinutes() {
        let start = Date(timeIntervalSince1970: 1000)
        let end = Date(timeIntervalSince1970: 1300)
        #expect(end.secondsOrMinutesSince(start) == "5m")
    }

    @Test func elapsedMinutesTruncate() {
        let start = Date(timeIntervalSince1970: 1000)
        let end = Date(timeIntervalSince1970: 1090)
        #expect(end.secondsOrMinutesSince(start) == "1m")
    }

    // MARK: - CLAuthorizationStatus.description

    @Test func clAuthStatuses() {
        #expect(CLAuthorizationStatus.notDetermined.description == "notDetermined")
        #expect(CLAuthorizationStatus.restricted.description == "restricted")
        #expect(CLAuthorizationStatus.denied.description == "denied")
        #expect(CLAuthorizationStatus.authorizedAlways.description == "authorizedAlways")
        #expect(CLAuthorizationStatus.authorizedWhenInUse.description == "authorizedWhenInUse")
    }

    @Test func clAuthUnknown() {
        let unknown = CLAuthorizationStatus(rawValue: 99)!
        #expect(unknown.description == "unknown")
    }

    // MARK: - HKAuthorizationStatus.description

    @Test func hkAuthStatuses() {
        #expect(HKAuthorizationStatus.notDetermined.description == "notDetermined")
        #expect(HKAuthorizationStatus.sharingAuthorized.description == "sharingAuthorized")
        #expect(HKAuthorizationStatus.sharingDenied.description == "sharingDenied")
    }

    @Test func hkAuthUnknown() {
        let unknown = HKAuthorizationStatus(rawValue: 99)!
        #expect(unknown.description == "unknown")
    }

    // MARK: - HKWorkoutSessionState.description

    @Test func wkSessionStates() {
        #expect(HKWorkoutSessionState.notStarted.description == "notStarted")
        #expect(HKWorkoutSessionState.running.description == "running")
        #expect(HKWorkoutSessionState.ended.description == "ended")
        #expect(HKWorkoutSessionState.paused.description == "paused")
        #expect(HKWorkoutSessionState.prepared.description == "prepared")
        #expect(HKWorkoutSessionState.stopped.description == "stopped")
    }

    @Test func wkSessionStateUnknown() {
        let unknown = HKWorkoutSessionState(rawValue: 99)!
        #expect(unknown.description == "unknown")
    }
}
