import Foundation
import os
@testable import beschluenige_Watch_App

final class MockHeartRateProvider: HeartRateProvider, @unchecked Sendable {
    private let realProvider: any HeartRateProvider
    private let timeoutInterval: TimeInterval
    private var sampleHandler: (@Sendable ([HeartRateSample]) -> Void)?
    private var fallbackTimer: Timer?
    private var timeoutTimer: Timer?
    private var receivedRealSample = false
    var onFallbackActivated: (@Sendable () -> Void)?
    private let logger = Logger(
        subsystem: "net.lnor.beschluenige.watchkitapp",
        category: "MockHR"
    )

    init(
        realProvider: any HeartRateProvider,
        timeoutInterval: TimeInterval = 10
    ) {
        self.realProvider = realProvider
        self.timeoutInterval = timeoutInterval
    }

    func requestAuthorization() async throws {
        try await realProvider.requestAuthorization()
    }

    func startMonitoring(handler: @escaping @Sendable ([HeartRateSample]) -> Void) async throws {
        sampleHandler = handler
        receivedRealSample = false

        try await realProvider.startMonitoring { [weak self] samples in
            guard let self else { return }
            receivedRealSample = true
            handler(samples)
        }

        let timer = Timer(timeInterval: timeoutInterval, repeats: false) { [weak self] _ in
            self?.startFallback()
        }
        RunLoop.main.add(timer, forMode: .common)
        timeoutTimer = timer
    }

    func stopMonitoring() {
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        fallbackTimer?.invalidate()
        fallbackTimer = nil
        realProvider.stopMonitoring()
        sampleHandler = nil
    }

    private func startFallback() {
        guard !receivedRealSample else { return }

        #if !targetEnvironment(simulator)
        assertionFailure("No heart rate samples received after 10s on a real device")
        #endif

        logger.warning("No heart rate samples received after 10s -- falling back to simulated data")
        onFallbackActivated?()

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let handler = sampleHandler else { return }
            let bpm = Double.random(in: 90...170)
            let sample = HeartRateSample(timestamp: Date(), beatsPerMinute: bpm)
            handler([sample])
        }
        RunLoop.main.add(timer, forMode: .common)
        fallbackTimer = timer
    }

    func sendSamples(_ samples: [HeartRateSample]) {
        sampleHandler?(samples)
    }
}
