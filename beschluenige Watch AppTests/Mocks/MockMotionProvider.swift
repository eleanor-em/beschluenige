import Foundation
import os
@testable import beschluenige_Watch_App

final class MockMotionProvider: MotionProvider, @unchecked Sendable {
    private var realProvider: (any MotionProvider)?
    private let realProviderFactory: @Sendable () -> any MotionProvider
    private let timeoutInterval: TimeInterval
    private var sampleHandler: (@Sendable ([AccelerometerSample]) -> Void)?
    private var fallbackTimer: Timer?
    private var timeoutTimer: Timer?
    private var receivedRealSample = false
    var onFallbackActivated: (@Sendable () -> Void)?
    private let logger = Logger(
        subsystem: "net.lnor.beschluenige.watchkitapp",
        category: "MockMotion"
    )

    init(
        realProviderFactory: @escaping @Sendable () -> any MotionProvider,
        timeoutInterval: TimeInterval = 10
    ) {
        self.realProviderFactory = realProviderFactory
        self.timeoutInterval = timeoutInterval
    }

    func startMonitoring(
        handler: @escaping @Sendable ([AccelerometerSample]) -> Void
    ) throws {
        sampleHandler = handler
        receivedRealSample = false

        let provider = realProviderFactory()
        realProvider = provider

        do {
            try provider.startMonitoring { [weak self] samples in
                guard let self else { return }
                receivedRealSample = true
                handler(samples)
            }
        } catch {
            logger.warning(
                "Real accelerometer failed: \(error.localizedDescription) -- will use fallback"
            )
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
        assertionFailure(
            "No accelerometer samples received after 10s on a real device")
        #endif

        logger.warning(
            "No accelerometer samples received after 10s -- falling back to simulated data"
        )
        onFallbackActivated?()

        // Generate batches of 100 samples (1 second at 100 Hz) every second
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let handler = sampleHandler else { return }
            let now = Date()
            var samples: [AccelerometerSample] = []
            for i in 0..<100 {
                let t = now.addingTimeInterval(Double(i) * 0.01)
                samples.append(
                    AccelerometerSample(
                        timestamp: t,
                        x: Double.random(in: -2...2),
                        y: Double.random(in: -2...2),
                        z: Double.random(in: -1...1) + 1.0
                    ))
            }
            handler(samples)
        }
        RunLoop.main.add(timer, forMode: .common)
        fallbackTimer = timer
    }

    func sendSamples(_ samples: [AccelerometerSample]) {
        sampleHandler?(samples)
    }
}
