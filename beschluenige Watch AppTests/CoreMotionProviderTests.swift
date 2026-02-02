import Foundation
import Testing
@testable import beschluenige_Watch_App

@MainActor
struct CoreMotionProviderTests {

    @Test func startMonitoringThrowsWhenAccelerometerUnavailable() {
        let provider = CoreMotionProvider()
        #expect(throws: MotionError.accelerometerUnavailable) {
            try provider.startMonitoring { _ in }
        }
    }

    @Test func stopMonitoringWhenNotStartedIsHarmless() {
        let provider = CoreMotionProvider()
        provider.stopMonitoring()
    }
}
