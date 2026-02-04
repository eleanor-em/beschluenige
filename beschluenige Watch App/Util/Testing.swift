import Foundation

let isRunningTests = ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil

final class UITestHeartRateProvider: HeartRateProvider, @unchecked Sendable {
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

final class UITestLocationProvider: LocationProvider, @unchecked Sendable {
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

final class UITestMotionProvider: MotionProvider, @unchecked Sendable {
    private var timer: Timer?

    func startMonitoring(
        handler: @escaping @Sendable ([AccelerometerSample]) -> Void
    ) throws {
        let timer = Timer(timeInterval: 1, repeats: true) { _ in
            let now = Date()
            var samples: [AccelerometerSample] = []
            for i in 0..<100 {
                samples.append(AccelerometerSample(
                    timestamp: now.addingTimeInterval(Double(i) * 0.01),
                    x: Double.random(in: -2...2),
                    y: Double.random(in: -2...2),
                    z: Double.random(in: -1...1) + 1.0
                ))
            }
            handler(samples)
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
}
