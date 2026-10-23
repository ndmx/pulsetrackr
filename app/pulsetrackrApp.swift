import SwiftUI

@main
struct pulsetrackrApp: App {
    @UIApplicationDelegateAdaptor(SOSPushRegistration.self) private var pushRegistration
    init() {
        AppInstallState.reconcileTrustedContactStorage()
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
