import Foundation

protocol MotionProvider: Sendable {
    func startMonitoring(
        accelerometerHandler: @escaping @Sendable ([AccelerometerSample]) -> Void,
        deviceMotionHandler: @escaping @Sendable ([DeviceMotionSample]) -> Void
    ) throws
    func stopMonitoring()
}
