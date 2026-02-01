import SwiftUI

@main
struct beschluenige_Watch_AppApp: App {
    init() {
        PhoneConnectivityManager.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
