import Foundation

protocol MotionProvider: Sendable {
    func startMonitoring(handler: @escaping @Sendable ([AccelerometerSample]) -> Void) throws
    func stopMonitoring()
}
