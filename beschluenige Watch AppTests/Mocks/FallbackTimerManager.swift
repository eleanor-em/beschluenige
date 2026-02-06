import Foundation
import os
@testable import beschluenige_Watch_App

final class FallbackTimerManager: @unchecked Sendable {
    var onFallbackActivated: (@Sendable () -> Void)?
    private var timeoutTimer: Timer?
    private var fallbackTimer: Timer?
    private(set) var receivedRealSample = false
    private let timeoutInterval: TimeInterval
    private let sensorName: String
    private let logger: Logger

    init(sensorName: String, timeoutInterval: TimeInterval = 15) {
        self.sensorName = sensorName
        self.timeoutInterval = timeoutInterval
        self.logger = Logger(
            subsystem: "net.lnor.beschluenige.watchkitapp",
            category: "Mock\(sensorName)"
        )
    }

    func markRealSampleReceived() {
        receivedRealSample = true
    }

    func reset() {
        receivedRealSample = false
    }

    func startTimeout(fallbackBlock: @escaping @Sendable () -> Void) {
        let timer = Timer(
            timeInterval: timeoutInterval, repeats: false
        ) { [weak self] _ in
            self?.activateFallback(fallbackBlock: fallbackBlock)
        }
        RunLoop.main.add(timer, forMode: .common)
        timeoutTimer = timer
    }

    func stop() {
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        fallbackTimer?.invalidate()
        fallbackTimer = nil
    }

    private func activateFallback(
        fallbackBlock: @escaping @Sendable () -> Void
    ) {
        guard !receivedRealSample else { return }

        let name = self.sensorName
        let timeout = Int(self.timeoutInterval)

        #if !targetEnvironment(simulator)
        if !isRunningTests {
            assertionFailure(
                "No \(name) samples received after \(timeout)s on a real device"
            )
        }
        #endif

        logger.warning(
            "No \(name) samples received after \(timeout)s -- falling back to simulated data"
        )
        onFallbackActivated?()

        let timer = Timer(timeInterval: 1, repeats: true) { _ in
            fallbackBlock()
        }
        RunLoop.main.add(timer, forMode: .common)
        fallbackTimer = timer
    }
}
