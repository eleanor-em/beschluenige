import Foundation

struct AccelerometerSample: Sendable {
    let timestamp: Date
    let x: Double
    let y: Double
    let z: Double
}
