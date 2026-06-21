enum AppStorageKey {
    static let hasSeenLaunch         = "hasSeenLaunch"
    static let launchLastSeenAt      = "launchLastSeenAt"
    static let launchLastSeenVersion = "launchLastSeenVersion"
    static let watchRadius           = "watchRadius"
    static let urgentAlerts          = "urgentAlerts"
    static let communityAlerts       = "communityAlerts"
    static let useApproximateLocation = "useApproximateLocation"
    static let lastKnownLatitude      = "lastKnownLatitude"
    static let lastKnownLongitude     = "lastKnownLongitude"
    static let lightModeEnabled       = "lightModeEnabled"
    /// Opt-in: seed the feed via the scalable H3 callable (query_incidents_h3) on
    /// region change, in addition to the live geohash listener. Off by default so the
    /// real-time listener stays the primary path. See SafetyIncidentRemoteStore.
    static let useH3FeedCallable      = "useH3FeedCallable"
}
