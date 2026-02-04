import Foundation
import os
@testable import beschluenige_Watch_App

final class MockLocationProvider: LocationProvider, @unchecked Sendable {
    private var realProvider: (any LocationProvider)?
    private let realProviderFactory: @Sendable () -> any LocationProvider
    private let timeoutInterval: TimeInterval
    private var sampleHandler: (@Sendable ([LocationSample]) -> Void)?
    private var fallbackTimer: Timer?
    private var timeoutTimer: Timer?
    private var receivedRealSample = false
    var onFallbackActivated: (@Sendable () -> Void)?
    private let logger = Logger(
        subsystem: "net.lnor.beschluenige.watchkitapp",
        category: "MockGPS"
    )

    init(
        realProviderFactory: @escaping @Sendable () -> any LocationProvider,
        timeoutInterval: TimeInterval = 15
    ) {
        self.realProviderFactory = realProviderFactory
        self.timeoutInterval = timeoutInterval
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
        receivedRealSample = false

        if realProvider == nil {
            realProvider = realProviderFactory()
        }

        try await realProvider!.startMonitoring { [weak self] samples in
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
        realProvider?.stopMonitoring()
        sampleHandler = nil
    }

    private func startFallback() {
        guard !receivedRealSample else { return }

        #if !targetEnvironment(simulator)
        if !isRunningTests {
            assertionFailure("No GPS samples received after 15s on a real device")
        }
        #endif

        logger.warning(
            "No GPS samples received after 15s -- falling back to simulated data")
        onFallbackActivated?()

        var lat = 43.6532
        var lon = -79.3832

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let handler = sampleHandler else { return }
            lat += Double.random(in: -0.0001...0.0001)
            lon += Double.random(in: -0.0001...0.0001)
            let sample = LocationSample(
                timestamp: Date(),
                latitude: lat,
                longitude: lon,
                altitude: 76.0,
                horizontalAccuracy: 5.0,
                verticalAccuracy: 8.0,
                speed: Double.random(in: 0...8),
                course: Double.random(in: 0..<360)
            )
            handler([sample])
        }
        RunLoop.main.add(timer, forMode: .common)
        fallbackTimer = timer
    }

    func sendSamples(_ samples: [LocationSample]) {
        sampleHandler?(samples)
    }
}
