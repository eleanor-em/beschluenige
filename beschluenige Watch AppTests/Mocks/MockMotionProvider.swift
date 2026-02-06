import Foundation
import os
@testable import beschluenige_Watch_App

final class MockMotionProvider: DeviceMotionProvider, @unchecked Sendable {
    private var realProvider: (any DeviceMotionProvider)?
    private let realProviderFactory: @Sendable () -> any DeviceMotionProvider
    private var accelHandler: (@Sendable ([AccelerometerSample]) -> Void)?
    private var dmHandler: (@Sendable ([DeviceMotionSample]) -> Void)?
    private let fallbackManager: FallbackTimerManager

    var onFallbackActivated: (@Sendable () -> Void)? {
        get { fallbackManager.onFallbackActivated }
        set { fallbackManager.onFallbackActivated = newValue }
    }

    init(
        realProviderFactory: @escaping @Sendable () -> any DeviceMotionProvider,
        timeoutInterval: TimeInterval = 15
    ) {
        self.realProviderFactory = realProviderFactory
        self.fallbackManager = FallbackTimerManager(
            sensorName: "motion",
            timeoutInterval: timeoutInterval
        )
    }

    func startMonitoring(
        accelerometerHandler: @escaping @Sendable ([AccelerometerSample]) -> Void,
        deviceMotionHandler: @escaping @Sendable ([DeviceMotionSample]) -> Void
    ) throws {
        accelHandler = accelerometerHandler
        dmHandler = deviceMotionHandler
        fallbackManager.reset()

        let provider = realProviderFactory()
        realProvider = provider

        do {
            try provider.startMonitoring(
                accelerometerHandler: { [weak self] samples in
                    guard let self else { return }
                    fallbackManager.markRealSampleReceived()
                    accelerometerHandler(samples)
                },
                deviceMotionHandler: { [weak self] samples in
                    guard let self else { return }
                    fallbackManager.markRealSampleReceived()
                    deviceMotionHandler(samples)
                }
            )
        } catch {
            Logger(
                subsystem: "net.lnor.beschluenige.watchkitapp",
                category: "MockMotion"
            ).warning(
                "Real motion provider failed: \(error.localizedDescription) -- will use fallback"
            )
        }

        fallbackManager.startTimeout { [weak self] in
            guard let self else { return }
            let now = Date()
            accelHandler?(SampleGenerators.generateAccelBatch(at: now))
            dmHandler?(SampleGenerators.generateDeviceMotionBatch(at: now))
        }
    }

    func stopMonitoring() {
        fallbackManager.stop()
        realProvider?.stopMonitoring()
        accelHandler = nil
        dmHandler = nil
    }

    func sendAccelSamples(_ samples: [AccelerometerSample]) {
        accelHandler?(samples)
    }

    func sendDMSamples(_ samples: [DeviceMotionSample]) {
        dmHandler?(samples)
    }
}
