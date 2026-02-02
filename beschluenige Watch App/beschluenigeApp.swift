import SwiftUI

@main
struct BeschluenigeWatchApp: App {
    init() {
        PhoneConnectivityManager.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
