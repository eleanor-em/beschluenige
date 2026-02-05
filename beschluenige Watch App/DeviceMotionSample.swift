import Foundation

struct DeviceMotionSample: Sendable {
    let timestamp: Date
    let roll: Double
    let pitch: Double
    let yaw: Double
    let rotationRateX: Double
    let rotationRateY: Double
    let rotationRateZ: Double
    let userAccelerationX: Double
    let userAccelerationY: Double
    let userAccelerationZ: Double
    let heading: Double
}
