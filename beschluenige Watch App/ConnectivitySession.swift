// This file exists only to wrap WCSession thinly for code coverage reasons (simulator limitations).

import Foundation
import WatchConnectivity

protocol ConnectivitySession: AnyObject {
    var activationState: WCSessionActivationState { get }
    var isDeviceSupported: Bool { get }
    func setDelegate(_ delegate: any WCSessionDelegate)
    func activate()
    func sendFile(_ file: URL, metadata: [String: Any])
}

extension WCSession: ConnectivitySession {
    var isDeviceSupported: Bool { WCSession.isSupported() }
    func setDelegate(_ delegate: any WCSessionDelegate) { self.delegate = delegate }
    // Use a different name to avoid infinite recursion.
    func sendFile(_ file: URL, metadata: [String: Any]) { transferFile(file, metadata: metadata) }
}
