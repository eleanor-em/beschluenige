import Foundation

protocol LocationProvider: Sendable {
    func requestAuthorization() async throws
    func startMonitoring(handler: @escaping @Sendable ([LocationSample]) -> Void) async throws
    func stopMonitoring()
}
