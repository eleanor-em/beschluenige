import Foundation
import os
@testable import beschluenige_Watch_App

@MainActor final class MockHeartRateProvider: HeartRateProvider {
    private let realProvider: any HeartRateProvider
    private var sampleHandler: (@Sendable ([HeartRateSample]) -> Void)?
    private let fallbackManager: FallbackTimerManager

    var onFallbackActivated: (@Sendable () -> Void)? {
        get { fallbackManager.onFallbackActivated }
        set { fallbackManager.onFallbackActivated = newValue }
    }

    init(
        realProvider: any HeartRateProvider,
        timeoutInterval: TimeInterval = 15
    ) {
        self.realProvider = realProvider
        self.fallbackManager = FallbackTimerManager(
            sensorName: "heart rate",
            timeoutInterval: timeoutInterval
        )
    }

    func requestAuthorization() async throws {
        try await realProvider.requestAuthorization()
    }

    func startMonitoring(handler: @escaping @Sendable ([HeartRateSample]) -> Void) async throws {
        sampleHandler = handler
        fallbackManager.reset()

        try await realProvider.startMonitoring { [weak self] samples in
            MainActor.assumeIsolated {
                self?.fallbackManager.markRealSampleReceived()
            }
            handler(samples)
        }

        fallbackManager.startTimeout { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let handler = self.sampleHandler else { return }
                let bpm = Double.random(in: 90...170)
                let sample = HeartRateSample(timestamp: Date(), beatsPerMinute: bpm)
                handler([sample])
            }
        }
    }

    func stopMonitoring() {
        fallbackManager.stop()
        realProvider.stopMonitoring()
        sampleHandler = nil
    }

    func sendSamples(_ samples: [HeartRateSample]) {
        sampleHandler?(samples)
    }
}
