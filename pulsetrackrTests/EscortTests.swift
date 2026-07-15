import CoreLocation
import Foundation
import Testing
@testable import pulsetrackr

@Suite("Escort sessions")
struct EscortTests {

    // MARK: - Activation payload

    @Test func escortActivationPayloadCarriesKindRelationshipAndEmptyContacts() throws {
        let location = try #require(SOSLocationSnapshot(latitude: 6.5244, longitude: 3.3792))
        let payload = SOSActivationPayload(
            lastKnownLocation: location,
            trustedContactsToNotify: [],
            sessionKind: .escort,
            escortRelationshipId: "rel_walk_1"
        )

        let encoded = payload.functionPayload
        #expect(encoded["sessionKind"] as? String == "escort")
        #expect(encoded["escortRelationshipId"] as? String == "rel_walk_1")
        #expect(encoded["session_kind"] == nil)
        #expect(encoded["escort_relationship_id"] == nil)

        let contacts = try #require(encoded["trusted_contacts_to_notify"] as? [[String: Any]])
        #expect(contacts.isEmpty)
    }

    @Test func defaultActivationPayloadOmitsEscortFields() throws {
        let location = try #require(SOSLocationSnapshot(latitude: 6.5, longitude: 3.3))
        let payload = SOSActivationPayload(lastKnownLocation: location)

        let encoded = payload.functionPayload
        #expect(encoded["sessionKind"] == nil)
        #expect(encoded["escortRelationshipId"] == nil)
        #expect(payload.sessionKind == nil)
        #expect(payload.escortRelationshipId == nil)
    }

    // MARK: - Store entry points

    @Test @MainActor func plainStartSessionDefaultsToSOSKind() {
        let store = SOSStore(remoteFactory: { nil })
        let location = CLLocation(latitude: 6.5244, longitude: 3.3792)
        store.startSession(from: location)

        #expect(store.session?.kind == .sos)
        #expect(store.session?.escortRelationshipId == nil)
        #expect(store.session?.isActive == true)
    }

    @Test @MainActor func escortStartSessionStoresKindAndRelationship() throws {
        let store = SOSStore(remoteFactory: { nil })
        let relationship = try #require(try? SOSAppTrustedContactRelationship(resultData: [
            "relationship_id": "rel_abc",
            "owner_uid": "owner_1",
            "trusted_contact_uid": "tc_1",
            "owner_display_name": "Walker",
            "trusted_contact_display_name": "Friend",
            "status": "accepted"
        ]))
        let location = CLLocation(latitude: 6.5244, longitude: 3.3792)

        store.startSession(from: location, kind: .escort, escortRelationship: relationship)

        #expect(store.session?.kind == .escort)
        #expect(store.session?.escortRelationshipId == "rel_abc")
        #expect(store.isActive)
    }

    @Test @MainActor func arrivedSafelyResolutionStopsSession() throws {
        let store = SOSStore(remoteFactory: { nil })
        let relationship = try #require(try? SOSAppTrustedContactRelationship(resultData: [
            "relationship_id": "rel_arrive",
            "owner_uid": "owner_1",
            "owner_display_name": "Walker",
            "trusted_contact_display_name": "Friend",
            "status": "accepted"
        ]))
        store.startSession(
            from: CLLocation(latitude: 6.52, longitude: 3.37),
            kind: .escort,
            escortRelationship: relationship
        )
        #expect(store.session?.isActive == true)

        store.markArrivedSafely()

        #expect(store.session?.state == .stopped)
        #expect(store.session?.isActive == false)
        #expect(store.session?.endedAt != nil)
        #expect(store.queuedEvents.contains { $0.kind == .stopped })
    }

    // MARK: - Outbox durability / legacy decode

    @Test func legacyActivateOutboxPayloadDecodesWithoutNewFields() throws {
        let location = try #require(SOSLocationSnapshot(
            latitude: 6.5,
            longitude: 3.3,
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000)
        ))
        let policy = SOSPrivacyPolicy()
        let legacyPayload = SOSActivateOutboxPayload(
            localSessionID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            activatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastKnownLocation: location,
            recentTrail: [location],
            trustedContacts: [],
            privacyPolicy: policy
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var encodedObject = try JSONSerialization.jsonObject(
            with: try encoder.encode(legacyPayload)
        ) as! [String: Any]
        // Simulate an older client that never wrote the escort keys.
        encodedObject.removeValue(forKey: "sessionKind")
        encodedObject.removeValue(forKey: "escortRelationshipId")
        let legacyData = try JSONSerialization.data(withJSONObject: encodedObject)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SOSActivateOutboxPayload.self, from: legacyData)

        #expect(decoded.sessionKind == nil)
        #expect(decoded.escortRelationshipId == nil)
        #expect(decoded.localSessionID.uuidString == "11111111-1111-1111-1111-111111111111")
        #expect(decoded.trustedContacts.isEmpty)
        // Consumers treat absent kind as SOS.
        #expect((decoded.sessionKind ?? .sos) == .sos)
    }

    @Test func escortActivateOutboxPayloadRoundTripsNewFields() throws {
        let location = try #require(SOSLocationSnapshot(latitude: 6.51, longitude: 3.35))
        let payload = SOSActivateOutboxPayload(
            localSessionID: UUID(),
            activatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            lastKnownLocation: location,
            recentTrail: [],
            trustedContacts: [],
            privacyPolicy: .default,
            sessionKind: .escort,
            escortRelationshipId: "rel_roundtrip"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(
            SOSActivateOutboxPayload.self,
            from: try encoder.encode(payload)
        )
        #expect(decoded.sessionKind == .escort)
        #expect(decoded.escortRelationshipId == "rel_roundtrip")
        #expect(decoded.trustedContacts.isEmpty)
    }

    // MARK: - Follow-view trail accumulation

    @Test @MainActor func followTrailAccumulatesUniquePointsInOrder() throws {
        let trailStore = EscortFollowTrailStore()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let t1 = t0.addingTimeInterval(30)
        let t2 = t1.addingTimeInterval(30)

        let first = SOSAppAlert(
            id: "a1",
            sessionID: "session_escort",
            ownerUID: "owner",
            ownerDisplayName: "Ada",
            status: "active",
            lastKnownLocation: SOSLocationSnapshot(latitude: 6.5000, longitude: 3.3000, capturedAt: t0),
            updatedAt: t0,
            kind: .escort
        )
        let second = SOSAppAlert(
            id: "a1",
            sessionID: "session_escort",
            ownerUID: "owner",
            ownerDisplayName: "Ada",
            status: "active",
            lastKnownLocation: SOSLocationSnapshot(latitude: 6.5005, longitude: 3.3005, capturedAt: t1),
            updatedAt: t1,
            kind: .escort
        )
        // Duplicate of second — same timestamp + coordinate must not append again.
        let duplicate = SOSAppAlert(
            id: "a1",
            sessionID: "session_escort",
            ownerUID: "owner",
            ownerDisplayName: "Ada",
            status: "active",
            lastKnownLocation: SOSLocationSnapshot(latitude: 6.5005, longitude: 3.3005, capturedAt: t1),
            updatedAt: t1,
            kind: .escort
        )
        let third = SOSAppAlert(
            id: "a1",
            sessionID: "session_escort",
            ownerUID: "owner",
            ownerDisplayName: "Ada",
            status: "active",
            lastKnownLocation: SOSLocationSnapshot(latitude: 6.5010, longitude: 3.3010, capturedAt: t2),
            updatedAt: t2,
            kind: .escort
        )

        trailStore.apply(alert: first)
        trailStore.apply(alert: second)
        trailStore.apply(alert: duplicate)
        trailStore.apply(alert: third)

        #expect(trailStore.trail.count == 3)
        #expect(trailStore.trail.map(\.coordinate.latitude) == [6.5000, 6.5005, 6.5010])
        #expect(trailStore.ownerDisplayName == "Ada")
        #expect(trailStore.isArrivedSafely == false)
    }

    @Test @MainActor func resolvedEscortAlertFlipsTerminalState() throws {
        let trailStore = EscortFollowTrailStore()
        let active = SOSAppAlert(
            id: "a2",
            sessionID: "session_done",
            ownerUID: "owner",
            ownerDisplayName: "Chioma",
            status: "active",
            lastKnownLocation: SOSLocationSnapshot(latitude: 6.52, longitude: 3.38, capturedAt: .now),
            updatedAt: .now,
            kind: .escort
        )
        let resolved = SOSAppAlert(
            id: "a2",
            sessionID: "session_done",
            ownerUID: "owner",
            ownerDisplayName: "Chioma",
            status: "resolved",
            lastKnownLocation: SOSLocationSnapshot(latitude: 6.521, longitude: 3.381, capturedAt: .now),
            updatedAt: .now,
            kind: .escort
        )

        trailStore.apply(alert: active)
        #expect(trailStore.isArrivedSafely == false)

        trailStore.apply(alert: resolved)
        #expect(trailStore.isArrivedSafely == true)
        #expect(trailStore.status == "resolved")
        #expect(trailStore.trail.count >= 1)
    }

    @Test func sosAppAlertDefaultsKindToSOSWhenAbsent() {
        // Memberwise path used by tests / UI; Firestore path defaults via sessionKind helper.
        let alert = SOSAppAlert(
            id: "legacy",
            sessionID: "s",
            ownerUID: "o",
            ownerDisplayName: "Legacy",
            status: "active",
            lastKnownLocation: nil,
            updatedAt: .now
        )
        #expect(alert.kind == .sos)
    }

    @Test func arrivedSafelyResolutionReasonWireValue() {
        #expect(SOSResolutionReason.arrivedSafely.rawValue == "arrived_safely")
        #expect(ContractDTO.ResolutionReason(rawValue: "arrived_safely") == .arrivedSafely)
    }
}
