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

        FirebaseApp.configure()
        return true
    }
}
