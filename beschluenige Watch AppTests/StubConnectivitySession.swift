import Foundation
import WatchConnectivity
@testable import beschluenige_Watch_App

final class StubConnectivitySession: ConnectivitySession {
    var activationState: WCSessionActivationState = .notActivated
    var isDeviceSupported: Bool = true
    var activateCalled = false
    var delegateSet = false
    var sentFiles: [(URL, [String: Any])] = []

    func setDelegate(_ delegate: any WCSessionDelegate) { delegateSet = true }
    func activate() { activateCalled = true }
    func sendFile(_ file: URL, metadata: [String: Any]) { sentFiles.append((file, metadata)) }
}
