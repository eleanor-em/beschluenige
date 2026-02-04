import SwiftUI

@main
struct BeschluenigeWatchApp: App {
    init() {
        if !CommandLine.arguments.contains("--ui-testing") {
            PhoneConnectivityManager.shared.activate()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
