import SwiftUI

@main
struct pulsetrackrApp: App {
    init() {
        MapboxBootstrap.configureFromBundle()
        FirebaseBootstrap.configureIfAvailable()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
