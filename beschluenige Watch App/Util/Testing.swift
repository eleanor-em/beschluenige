import Foundation

let isRunningTests = ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil

nonisolated enum SampleGenerators {
    static func generateAccelBatch(
        at now: Date, count: Int = 100
    ) -> [AccelerometerSample] {
        (0..<count).map { i in
            AccelerometerSample(
                timestamp: now.addingTimeInterval(Double(i) * 0.01),
                x: Double.random(in: -2...2),
                y: Double.random(in: -2...2),
                z: Double.random(in: -1...1) + 1.0
            )
        }
    }

    static func generateDeviceMotionBatch(
        at now: Date, count: Int = 100
    ) -> [DeviceMotionSample] {
        (0..<count).map { i in
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
}

final class UITestHeartRateProvider: HeartRateProvider {
    private var timer: Timer?

    func requestAuthorization() async throws {}

    func startMonitoring(
        handler: @escaping @Sendable ([HeartRateSample]) -> Void
    ) async throws {
        let timer = Timer(timeInterval: 1, repeats: true) { _ in
            let sample = HeartRateSample(
                timestamp: Date(),
                beatsPerMinute: Double.random(in: 90...170)
            )
            handler([sample])
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
}

final class UITestLocationProvider: LocationProvider {
    private var timer: Timer?

    func requestAuthorization() async throws {}

    func startMonitoring(
        handler: @escaping @Sendable ([LocationSample]) -> Void
    ) async throws {
        let timer = Timer(timeInterval: 1, repeats: true) { _ in
            let sample = LocationSample(
                timestamp: Date(),
                latitude: 43.65 + Double.random(in: -0.001...0.001),
                longitude: -79.38 + Double.random(in: -0.001...0.001),
                altitude: 76.0,
                horizontalAccuracy: 5.0,
                verticalAccuracy: 8.0,
                speed: Double.random(in: 0...8),
                course: Double.random(in: 0...360)
            )
            handler([sample])
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
}

final class UITestMotionProvider: DeviceMotionProvider {
    private var timer: Timer?

    func startMonitoring(
        accelerometerHandler: @escaping @Sendable ([AccelerometerSample]) -> Void,
        deviceMotionHandler: @escaping @Sendable ([DeviceMotionSample]) -> Void
    ) throws {
        let timer = Timer(timeInterval: 1, repeats: true) { _ in
            let now = Date()
            accelerometerHandler(SampleGenerators.generateAccelBatch(at: now))
            deviceMotionHandler(SampleGenerators.generateDeviceMotionBatch(at: now))
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
}
