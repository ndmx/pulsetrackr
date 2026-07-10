import Foundation
import Testing
@testable import pulsetrackr

@Suite("App Install State")
struct AppInstallStateTests {
    @Test func freshInstallClearsPersistedManualTrustedContacts() {
        let defaults = isolatedDefaults()
        var cleanupCount = 0

        AppInstallState.reconcileTrustedContactStorage(
            defaults: defaults,
            cleanupManualTrustedContacts: { cleanupCount += 1 },
            makeInstallID: { "install-1" }
        )

        #expect(cleanupCount == 1)
        #expect(defaults.string(forKey: AppStorageKey.installMarker) == "install-1")
    }

    @Test func appUpdateKeepsExistingManualTrustedContacts() {
        let defaults = isolatedDefaults()
        defaults.set(true, forKey: AppStorageKey.hasSeenLaunch)
        var cleanupCount = 0

        AppInstallState.reconcileTrustedContactStorage(
            defaults: defaults,
            cleanupManualTrustedContacts: { cleanupCount += 1 },
            makeInstallID: { "install-2" }
        )

        #expect(cleanupCount == 0)
        #expect(defaults.string(forKey: AppStorageKey.installMarker) == "install-2")
    }

    @Test func reconciledInstallDoesNothingOnLaterLaunches() {
        let defaults = isolatedDefaults()
        defaults.set("install-existing", forKey: AppStorageKey.installMarker)
        var cleanupCount = 0

        AppInstallState.reconcileTrustedContactStorage(
            defaults: defaults,
            cleanupManualTrustedContacts: { cleanupCount += 1 },
            makeInstallID: { "install-new" }
        )

        #expect(cleanupCount == 0)
        #expect(defaults.string(forKey: AppStorageKey.installMarker) == "install-existing")
    }

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "pulsetrackr.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
