import Foundation
import Testing
@testable import beschluenige_Watch_App

struct FormattingTests {

    // MARK: - roundedWithAbbreviations

    @Test func zeroReturnsPlainNumber() {
        #expect(0.roundedWithAbbreviations == "0")
    }

    @Test func smallNumberReturnsPlainNumber() {
        #expect(42.roundedWithAbbreviations == "42")
    }

    @Test func justBelowThousandReturnsPlainNumber() {
        #expect(999.roundedWithAbbreviations == "999")
    }

    @Test func exactlyOneThousandReturnsK() {
        #expect(1000.roundedWithAbbreviations == "1.0k")
    }

    @Test func thousandsRoundToOneTenth() {
        #expect(1500.roundedWithAbbreviations == "1.5k")
        #expect(2345.roundedWithAbbreviations == "2.3k")
        #expect(9999.roundedWithAbbreviations == "10.0k")
    }

    @Test func largeThousands() {
        #expect(500_000.roundedWithAbbreviations == "500.0k")
        #expect(999_999.roundedWithAbbreviations == "1000.0k")
    }

    @Test func exactlyOneMillionReturnsM() {
        #expect(1_000_000.roundedWithAbbreviations == "1.0m")
    }

    @Test func millionsRoundToOneTenth() {
        #expect(1_500_000.roundedWithAbbreviations == "1.5m")
        #expect(2_345_678.roundedWithAbbreviations == "2.3m")
        #expect(10_000_000.roundedWithAbbreviations == "10.0m")
    }

    @Test func negativeSmallNumber() {
        // Negative values below 1000 return plain representation
        #expect((-5).roundedWithAbbreviations == "-5")
    }

    // MARK: - secondsOrMinutesSince

    @Test func zeroElapsedReturnsZeroSeconds() {
        let now = Date()
        #expect(now.secondsOrMinutesSince(now) == "0s")
    }

    @Test func fewSecondsElapsed() {
        let start = Date(timeIntervalSince1970: 1000)
        let end = Date(timeIntervalSince1970: 1030)
        #expect(end.secondsOrMinutesSince(start) == "30s")
    }

    @Test func justUnderOneMinuteReturnsSeconds() {
        let start = Date(timeIntervalSince1970: 1000)
        let end = Date(timeIntervalSince1970: 1059)
        #expect(end.secondsOrMinutesSince(start) == "59s")
    }

    @Test func exactlyOneMinuteReturnsMinutes() {
        let start = Date(timeIntervalSince1970: 1000)
        let end = Date(timeIntervalSince1970: 1060)
        #expect(end.secondsOrMinutesSince(start) == "1m")
    }

    @Test func severalMinutesElapsed() {
        let start = Date(timeIntervalSince1970: 1000)
        let end = Date(timeIntervalSince1970: 1300)
        #expect(end.secondsOrMinutesSince(start) == "5m")
    }

    @Test func minutesTruncateNotRound() {
        // 90 seconds = 1.5 minutes, should truncate to 1m
        let start = Date(timeIntervalSince1970: 1000)
        let end = Date(timeIntervalSince1970: 1090)
        #expect(end.secondsOrMinutesSince(start) == "1m")
    }
}
