import Foundation

struct LocationSample: Sendable {
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let altitude: Double
    let horizontalAccuracy: Double
    let verticalAccuracy: Double
    let speed: Double
    let course: Double
}
