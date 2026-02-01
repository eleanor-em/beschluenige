import Foundation

protocol HeartRateProvider: Sendable {
    func requestAuthorization() async throws
    func startMonitoring(handler: @escaping @Sendable ([HeartRateSample]) -> Void) async throws
    func stopMonitoring()
}
