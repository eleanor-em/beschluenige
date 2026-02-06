import Foundation
import os
@testable import beschluenige_Watch_App

final class MockMotionProvider: DeviceMotionProvider, @unchecked Sendable {
    private var realProvider: (any DeviceMotionProvider)?
    private let realProviderFactory: @Sendable () -> any DeviceMotionProvider
    private let timeoutInterval: TimeInterval
    private var accelHandler: (@Sendable ([AccelerometerSample]) -> Void)?
    private var dmHandler: (@Sendable ([DeviceMotionSample]) -> Void)?
    private var fallbackTimer: Timer?
    private var timeoutTimer: Timer?
    private var receivedRealSample = false
    var onFallbackActivated: (@Sendable () -> Void)?
    private let logger = Logger(
        subsystem: "net.lnor.beschluenige.watchkitapp",
        category: "MockMotion"
    )

    init(
        realProviderFactory: @escaping @Sendable () -> any DeviceMotionProvider,
        timeoutInterval: TimeInterval = 15
    ) {
        self.realProviderFactory = realProviderFactory
        self.timeoutInterval = timeoutInterval
    }

    func startMonitoring(
        accelerometerHandler: @escaping @Sendable ([AccelerometerSample]) -> Void,
        deviceMotionHandler: @escaping @Sendable ([DeviceMotionSample]) -> Void
    ) throws {
        accelHandler = accelerometerHandler
        dmHandler = deviceMotionHandler
        receivedRealSample = false

        let provider = realProviderFactory()
        realProvider = provider

        do {
            try provider.startMonitoring(
                accelerometerHandler: { [weak self] samples in
                    guard let self else { return }
                    receivedRealSample = true
                    accelerometerHandler(samples)
                },
                deviceMotionHandler: { [weak self] samples in
                    guard let self else { return }
                    receivedRealSample = true
                    deviceMotionHandler(samples)
                }
            )
        } catch {
            logger.warning(
                "Real motion provider failed: \(error.localizedDescription) -- will use fallback"
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
        accelHandler = nil
        dmHandler = nil
    }

    private func startFallback() {
        guard !receivedRealSample else { return }

        #if !targetEnvironment(simulator)
        if !isRunningTests {
            assertionFailure(
                "No motion samples received after 15s on a real device")
        }
        #endif

        logger.warning(
            "No motion samples received after 15s -- falling back to simulated data"
        )
        onFallbackActivated?()

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = Date()
            if let accelHandler {
                accelHandler(Self.generateAccelBatch(at: now))
            }
            if let dmHandler {
                dmHandler(Self.generateDMBatch(at: now))
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        fallbackTimer = timer
    }

    private static func generateAccelBatch(at now: Date) -> [AccelerometerSample] {
        (0..<100).map { i in
            AccelerometerSample(
                timestamp: now.addingTimeInterval(Double(i) * 0.01),
                x: Double.random(in: -2...2),
                y: Double.random(in: -2...2),
                z: Double.random(in: -1...1) + 1.0
            )
        }
    }

    private static func generateDMBatch(at now: Date) -> [DeviceMotionSample] {
        (0..<100).map { i in
            DeviceMotionSample(
                timestamp: now.addingTimeInterval(Double(i) * 0.01),
                roll: Double.random(in: -.pi...(.pi)),
                pitch: Double.random(in: -.pi / 2...(.pi / 2)),
                yaw: Double.random(in: -.pi...(.pi)),
                rotationRateX: Double.random(in: -5...5),
                rotationRateY: Double.random(in: -5...5),
                rotationRateZ: Double.random(in: -5...5),
                userAccelerationX: Double.random(in: -2...2),
                userAccelerationY: Double.random(in: -2...2),
                userAccelerationZ: Double.random(in: -2...2),
                heading: Double.random(in: 0...360)
            )
        }
    }

    func sendAccelSamples(_ samples: [AccelerometerSample]) {
        accelHandler?(samples)
    }

    func sendDMSamples(_ samples: [DeviceMotionSample]) {
        dmHandler?(samples)
    }
}
