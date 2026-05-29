#if canImport(MapboxMaps)
import Foundation
import MapboxMaps

enum MapboxBootstrap {
    @discardableResult
    static func configureFromBundle() -> Bool {
        guard
            let rawToken = Bundle.main.object(forInfoDictionaryKey: "MBXAccessToken") as? String
        else {
#if DEBUG
            assertionFailure("Missing MBXAccessToken. Add a public Mapbox token to ~/.mapbox before running the app.")
#endif
            return false
        }

        let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard token.hasPrefix("pk.") else {
#if DEBUG
            assertionFailure("MBXAccessToken must be a public Mapbox runtime token that starts with pk.")
#endif
            return false
        }

        MapboxOptions.accessToken = token
        return true
    }
}
#else
enum MapboxBootstrap {
    @discardableResult
    static func configureFromBundle() -> Bool {
        true
    }
}
#endif
