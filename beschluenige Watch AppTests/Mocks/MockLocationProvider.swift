import Foundation
import os
@testable import beschluenige_Watch_App

@MainActor final class MockLocationProvider: LocationProvider {
    private var realProvider: (any LocationProvider)?
    private let realProviderFactory: @Sendable () -> any LocationProvider
    private var sampleHandler: (@Sendable ([LocationSample]) -> Void)?
    private let fallbackManager: FallbackTimerManager
    private var lat = 43.6532
    private var lon = -79.3832

    var onFallbackActivated: (@Sendable () -> Void)? {
        get { fallbackManager.onFallbackActivated }
        set { fallbackManager.onFallbackActivated = newValue }
    }

    init(
        realProviderFactory: @escaping @Sendable () -> any LocationProvider,
        timeoutInterval: TimeInterval = 15
    ) {
        self.realProviderFactory = realProviderFactory
        self.fallbackManager = FallbackTimerManager(
            sensorName: "GPS",
            timeoutInterval: timeoutInterval
        )
    }

    func requestAuthorization() async throws {
        let provider = realProviderFactory()
        realProvider = provider
        try await provider.requestAuthorization()
    }

    func startMonitoring(
        handler: @escaping @Sendable ([LocationSample]) -> Void
    ) async throws {
        sampleHandler = handler
        fallbackManager.reset()

        if realProvider == nil {
            realProvider = realProviderFactory()
        }

        try await realProvider!.startMonitoring { [weak self] samples in
            MainActor.assumeIsolated {
                self?.fallbackManager.markRealSampleReceived()
            }
            handler(samples)
        }

        fallbackManager.startTimeout { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let handler = self.sampleHandler else { return }
                self.lat += Double.random(in: -0.0001...0.0001)
                self.lon += Double.random(in: -0.0001...0.0001)
                let sample = LocationSample(
                    timestamp: Date(),
                    latitude: self.lat,
                    longitude: self.lon,
                    altitude: 76.0,
                    horizontalAccuracy: 5.0,
                    verticalAccuracy: 8.0,
                    speed: Double.random(in: 0...8),
                    course: Double.random(in: 0..<360)
                )
                handler([sample])
            }
        }
    }

    func stopMonitoring() {
        fallbackManager.stop()
        realProvider?.stopMonitoring()
        sampleHandler = nil
    }

    func sendSamples(_ samples: [LocationSample]) {
        sampleHandler?(samples)
    }
}
