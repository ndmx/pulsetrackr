import FirebaseAppCheck
import FirebaseCore
import Foundation

enum FirebaseBootstrap {
    @discardableResult
    static func configureIfAvailable() -> Bool {
        if FirebaseApp.app() != nil {
            return true
        }

        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            return false
        }

        configureAppCheckProvider()
        FirebaseApp.configure()
        return true
    }

    private static func configureAppCheckProvider() {
#if DEBUG
        AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
#else
        AppCheck.setAppCheckProviderFactory(PulseTrackrAppCheckProviderFactory())
#endif
    }
}

private final class PulseTrackrAppCheckProviderFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        if #available(iOS 14.0, *) {
            return AppAttestProvider(app: app)
        } else {
            return DeviceCheckProvider(app: app)
        }
    }
}
