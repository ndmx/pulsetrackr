import Foundation

struct SOSPrivacyPolicy: Codable, Equatable {
    var includeRecentTrail: Bool
    var recentTrailMaxPoints: Int
    var recentTrailMaxAgeSeconds: TimeInterval
    var liveLocationUpdateIntervalSeconds: TimeInterval
    var shareExactLocationWithTrustedContacts: Bool
    var adminAccessExpiresAfterSeconds: TimeInterval
    var lawEnforcementAccessRequiresActiveSession: Bool
    var auditPrivilegedAccess: Bool

    init(
        includeRecentTrail: Bool = true,
        recentTrailMaxPoints: Int = 12,
        recentTrailMaxAgeSeconds: TimeInterval = 15 * 60,
        liveLocationUpdateIntervalSeconds: TimeInterval = 30,
        shareExactLocationWithTrustedContacts: Bool = true,
        adminAccessExpiresAfterSeconds: TimeInterval = 60 * 60,
        lawEnforcementAccessRequiresActiveSession: Bool = true,
        auditPrivilegedAccess: Bool = true
    ) {
        self.includeRecentTrail = includeRecentTrail
        self.recentTrailMaxPoints = max(0, recentTrailMaxPoints)
        self.recentTrailMaxAgeSeconds = max(0, recentTrailMaxAgeSeconds)
        self.liveLocationUpdateIntervalSeconds = max(5, liveLocationUpdateIntervalSeconds)
        self.shareExactLocationWithTrustedContacts = shareExactLocationWithTrustedContacts
        self.adminAccessExpiresAfterSeconds = max(60, adminAccessExpiresAfterSeconds)
        self.lawEnforcementAccessRequiresActiveSession = lawEnforcementAccessRequiresActiveSession
        self.auditPrivilegedAccess = auditPrivilegedAccess
    }

    static let `default` = SOSPrivacyPolicy()

    var functionPayload: [String: Any] {
        [
            "include_recent_trail": includeRecentTrail,
            "recent_trail_max_points": recentTrailMaxPoints,
            "recent_trail_max_age_seconds": Int(recentTrailMaxAgeSeconds),
            "live_location_update_interval_seconds": Int(liveLocationUpdateIntervalSeconds),
            "share_exact_location_with_trusted_contacts": shareExactLocationWithTrustedContacts,
            "admin_access_expires_after_seconds": Int(adminAccessExpiresAfterSeconds),
            "law_enforcement_access_requires_active_session": lawEnforcementAccessRequiresActiveSession,
            "audit_privileged_access": auditPrivilegedAccess
        ]
    }
}

enum SOSPayloadCoding {
    static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    static func date(from value: Any?) -> Date? {
        if let date = value as? Date {
            return date
        }

        guard let string = value as? String else {
            return nil
        }

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: string) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

