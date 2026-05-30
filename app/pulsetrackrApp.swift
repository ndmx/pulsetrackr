import SwiftUI

@main
struct pulsetrackrApp: App {
    init() {
        MapboxBootstrap.configureFromBundle()
        FirebaseBootstrap.configureIfAvailable()
        PulseAppearance.apply()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
