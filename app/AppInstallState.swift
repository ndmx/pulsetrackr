import Foundation

enum AppInstallState {
    typealias CleanupAction = () throws -> Void
    typealias IDGenerator = () -> String

    static func reconcileTrustedContactStorage(
        defaults: UserDefaults = .standard,
        cleanupManualTrustedContacts: CleanupAction = { try SOSTrustedContactStore().deleteAll() },
        makeInstallID: IDGenerator = { UUID().uuidString }
    ) {
        guard defaults.string(forKey: AppStorageKey.installMarker) == nil else { return }

        if hasExistingInstallEvidence(in: defaults) {
            defaults.set(makeInstallID(), forKey: AppStorageKey.installMarker)
            return
        }

        try? cleanupManualTrustedContacts()
        defaults.set(makeInstallID(), forKey: AppStorageKey.installMarker)
    }

    static func hasExistingInstallEvidence(in defaults: UserDefaults) -> Bool {
        existingInstallEvidenceKeys.contains { defaults.object(forKey: $0) != nil }
    }

    private static let existingInstallEvidenceKeys = [
        AppStorageKey.hasSeenLaunch,
        AppStorageKey.launchLastSeenAt,
        AppStorageKey.launchLastSeenVersion,
        AppStorageKey.lastKnownLatitude,
        AppStorageKey.lastKnownLongitude,
        AppStorageKey.sosOwnerDisplayName
    ]
}
