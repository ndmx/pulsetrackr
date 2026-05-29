import Foundation
import Testing
@testable import pulsetrackr

@Suite("SOS Payload Privacy")
struct SOSPayloadPrivacyTests {
    @Test func activationPayloadLimitsRecentTrailByAgeAndPointCount() throws {
        let activatedAt = Date(timeIntervalSince1970: 1_000)
        let trail = (0..<6).map { index in
            SOSLocationSnapshot(
                latitude: 6.50 + Double(index) / 1_000,
                longitude: 3.30,
                capturedAt: activatedAt.addingTimeInterval(Double(index - 5) * 60)
            )!
        }
        let lastKnownLocation = try #require(trail.last)
        let payload = SOSActivationPayload(
            activatedAt: activatedAt,
            lastKnownLocation: lastKnownLocation,
            recentTrail: trail,
            deviceMetadata: SOSDeviceMetadata(batteryLevelPercent: 54, lowPowerModeEnabled: false),
            privacyPolicy: SOSPrivacyPolicy(recentTrailMaxPoints: 2, recentTrailMaxAgeSeconds: 180)
        )

        let encodedTrail = try #require(payload.functionPayload["recent_trail"] as? [[String: Any]])

        #expect(encodedTrail.count == 2)
        #expect(encodedTrail.compactMap { $0["latitude"] as? Double } == [6.504, 6.505])
    }

    @Test func privacyPolicyCanDisableRecentTrail() throws {
        let activatedAt = Date(timeIntervalSince1970: 1_000)
        let first = SOSLocationSnapshot(latitude: 6.5, longitude: 3.3, capturedAt: activatedAt.addingTimeInterval(-60))!
        let latest = SOSLocationSnapshot(latitude: 6.6, longitude: 3.4, capturedAt: activatedAt)!
        let payload = SOSActivationPayload(
            activatedAt: activatedAt,
            lastKnownLocation: latest,
            recentTrail: [first, latest],
            privacyPolicy: SOSPrivacyPolicy(includeRecentTrail: false)
        )

        let encodedTrail = try #require(payload.functionPayload["recent_trail"] as? [[String: Any]])

        #expect(encodedTrail.isEmpty)
    }

    @Test func redactedDiagnosticsPayloadDoesNotExposeContactDestinations() throws {
        let contact = SOSTrustedContact(
            displayName: "  Ada  ",
            phoneNumber: "+2348012345678",
            emailAddress: "ADA@EXAMPLE.COM",
            notificationChannels: [.sms, .email]
        )
        let target = try #require(contact.notificationTarget)
        let location = SOSLocationSnapshot(latitude: 6.5244, longitude: 3.3792)!
        let payload = SOSActivationPayload(
            lastKnownLocation: location,
            trustedContactsToNotify: [target]
        )

        let redacted = try #require(payload.redactedDiagnosticsPayload["trusted_contacts_to_notify"] as? [[String: Any]])
        let firstContact = try #require(redacted.first)

        #expect(firstContact["phone_number"] == nil)
        #expect(firstContact["email_address"] == nil)
        #expect(firstContact["phone_last4"] as? String == "5678")
        #expect(firstContact["has_email_address"] as? Bool == true)
    }

    @Test func trustedContactOnlyUsesDeliverableChannels() throws {
        let contact = SOSTrustedContact(
            displayName: "Tunde",
            emailAddress: "tunde@example.com",
            notificationChannels: [.sms, .email, .phoneCall]
        )
        let target = try #require(contact.notificationTarget)

        #expect(target.channels == [.email])
        #expect(contact.emailAddress == "tunde@example.com")
    }

    @Test func directionOfTravelComputesBearingFromTrail() throws {
        let start = SOSLocationSnapshot(latitude: 6.5, longitude: 3.3, capturedAt: Date(timeIntervalSince1970: 1))!
        let end = SOSLocationSnapshot(latitude: 6.5, longitude: 3.4, capturedAt: Date(timeIntervalSince1970: 2))!
        let direction = try #require(SOSDirectionOfTravel(recentTrail: [start, end]))

        #expect(direction.bearingDegrees > 89)
        #expect(direction.bearingDegrees < 91)
        #expect(direction.computedFromPointCount == 2)
    }
}

