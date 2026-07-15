import CoreLocation
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import FirebaseFunctions
import Foundation
#if canImport(Network)
import Network
#endif
#if canImport(UIKit)
import UIKit
#endif

final class SOSRemoteStore {
    private let db: Firestore
    private let functions: Functions

    static func makeIfConfigured() -> SOSRemoteStore? {
        guard FirebaseBootstrap.configureIfAvailable() else { return nil }
        return SOSRemoteStore()
    }

    private init(db: Firestore = Firestore.firestore(), functions: Functions = Functions.functions()) {
        self.db = db
        self.functions = functions
    }

    func activateSOS(payload: SOSActivationPayload) async throws -> SOSActivationResponse {
        try await ensureSignedIn()
        let result = try await callFunction(named: "activate_sos", data: payload.functionPayload)
        return try SOSActivationResponse(resultData: result.data)
    }

    func appendSOSLocation(sessionID: String, update: SOSLocationUpdatePayload) async throws {
        try await ensureSignedIn()
        var payload = update.functionPayload
        payload["session_id"] = sessionID
        _ = try await callFunction(named: "append_sos_location", data: payload)
    }

    func fetchNotificationStatus(sessionID: String) async throws -> SOSNotificationStatus {
        try await ensureSignedIn()
        let result = try await callFunction(named: "get_sos_notification_status", data: ["session_id": sessionID])
        return try SOSNotificationStatus(resultData: result.data)
    }

    func resolveSOS(
        sessionID: String,
        resolution: SOSResolutionReason,
        finalLocation: SOSLocationSnapshot? = nil,
        resolvedAt: Date = Date()
    ) async throws {
        try await ensureSignedIn()
        let payload = SOSResolutionPayload(
            sessionID: sessionID,
            reason: resolution,
            finalLocation: finalLocation,
            resolvedAt: resolvedAt
        )
        _ = try await callFunction(named: "resolve_sos", data: payload.functionPayload)
    }

    func createAppTrustedContactInvite(ownerDisplayName: String) async throws -> SOSAppTrustedContactInvite {
        try await ensureSignedIn()
        let result = try await callFunction(
            named: "create_app_trusted_contact_invite",
            data: ["owner_display_name": ownerDisplayName]
        )
        return try SOSAppTrustedContactInvite(resultData: result.data)
    }

    func acceptAppTrustedContactInvite(
        inviteCode: String,
        trustedContactDisplayName: String
    ) async throws -> SOSAppTrustedContactRelationship {
        try await ensureSignedIn()
        let result = try await callFunction(named: "accept_app_trusted_contact_invite", data: [
            "invite_code": inviteCode,
            "trusted_contact_display_name": trustedContactDisplayName
        ])
        return try SOSAppTrustedContactRelationship(resultData: result.data)
    }

    func listAppTrustedContacts() async throws -> SOSAppTrustedContactList {
        try await ensureSignedIn()
        let result = try await callFunction(named: "list_app_trusted_contacts", data: [:])
        return SOSAppTrustedContactList(resultData: result.data)
    }

    func observeAppSOSAlerts(onChange: @escaping ([SOSAppAlert]) -> Void) async throws -> SOSAppAlertObservation {
        try await ensureSignedIn()
        guard let uid = Auth.auth().currentUser?.uid else {
            throw SOSRemoteStoreError.invalidResponse
        }

        let registration = db.collection("sos_app_alerts_private")
            .whereField("recipientUid", isEqualTo: uid)
            .addSnapshotListener { snapshot, error in
                guard error == nil, let snapshot else { return }
                let alerts = snapshot.documents
                    .compactMap(SOSAppAlert.init(document:))
                    .sorted { $0.updatedAt > $1.updatedAt }
                onChange(alerts)
            }
        return SOSAppAlertObservation(registration: registration)
    }

    private func ensureSignedIn() async throws {
        if Auth.auth().currentUser != nil { return }
        do {
            try await Auth.auth().signInAnonymously()
        } catch {
            // App Check / anonymous-auth failures surface here, before any callable runs.
            // Wrap them so the SOS panel can classify them instead of falling through to
            // the generic "server returned an error" message.
            throw SOSRemoteCallError(functionName: "auth.signInAnonymously", error: error as NSError)
        }
    }

    private func callFunction(named name: String, data: [String: Any]) async throws -> HTTPSCallableResult {
        do {
            return try await functions.httpsCallable(name).call(data)
        } catch {
            throw SOSRemoteCallError(functionName: name, error: error as NSError)
        }
    }
}

/// Wraps a failed Cloud Functions call so the UI can show *why* an SOS upload failed
/// (App Check, not-deployed, offline, server error) instead of one catch-all string.
struct SOSRemoteCallError: LocalizedError {
    enum Reason {
        case appCheckOrAuth
        case notDeployed
        case offline
        case server
        case rateLimited
        case unknown
    }

    let functionName: String
    let reason: Reason
    let underlying: NSError

    init(functionName: String, error: NSError) {
        self.functionName = functionName
        self.underlying = error
        self.reason = Self.classify(error)
    }

    private static func classify(_ error: NSError) -> Reason {
        if error.domain == FunctionsErrorDomain, let code = FunctionsErrorCode(rawValue: error.code) {
            switch code {
            case .unauthenticated, .permissionDenied:
                return .appCheckOrAuth
            case .notFound, .unimplemented:
                return .notDeployed
            case .unavailable, .deadlineExceeded, .cancelled:
                return .offline
            case .resourceExhausted:
                return .rateLimited
            case .internal, .dataLoss, .aborted, .unknown:
                return .server
            default:
                return .unknown
            }
        }
        // App Check and Firebase Auth failures (e.g. unregistered debug token, App Attest
        // misconfig, anonymous sign-in disabled) come through their own domains before any
        // callable runs — treat them as a device-verification problem.
        if error.domain.localizedCaseInsensitiveContains("appcheck")
            || error.domain == "FIRAuthErrorDomain"
            || error.domain == AuthErrorDomain {
            return .appCheckOrAuth
        }
        if error.domain == NSURLErrorDomain {
            return .offline
        }
        return .unknown
    }

    /// Short, calm, user-facing explanation shown on the SOS panel.
    var userMessage: String {
        switch reason {
        case .appCheckOrAuth:
            return "Couldn’t verify this device with the SOS server (App Check). Your location is saved on this device and will retry."
        case .notDeployed:
            return "The SOS service isn’t reachable for this app build. Your location is saved on this device."
        case .offline:
            return "You appear to be offline. Emergency updates are queued and will send automatically when you reconnect."
        case .rateLimited:
            return "Too many SOS attempts in a short time. Please wait a moment before trying again."
        case .server, .unknown:
            return "The SOS server returned an error. Your location is saved on this device and PulseTrackr will keep retrying."
        }
    }

    /// Verbose detail for logs / DEBUG builds — domain, code, message.
    var diagnosticMessage: String {
        "[\(functionName)] \(underlying.domain) #\(underlying.code): \(underlying.localizedDescription)"
    }

    var isClosedSessionPrecondition: Bool {
        guard underlying.domain == FunctionsErrorDomain,
              let code = FunctionsErrorCode(rawValue: underlying.code),
              code == .failedPrecondition || code == .notFound
        else {
            return false
        }
        return underlying.localizedDescription.localizedCaseInsensitiveContains("session")
    }

    var errorDescription: String? { userMessage }
}

struct SOSActivationPayload: Equatable {
    var clientSessionID: UUID
    var activatedAt: Date
    var lastKnownLocation: SOSLocationSnapshot
    var recentTrail: [SOSLocationSnapshot]
    var directionOfTravel: SOSDirectionOfTravel?
    var trustedContactsToNotify: [SOSTrustedContactNotificationTarget]
    var deviceMetadata: SOSDeviceMetadata
    var privacyPolicy: SOSPrivacyPolicy
    var source: String
    /// Defaults to nil (backend treats absent as `sos`).
    var sessionKind: SOSSessionKind?
    /// Required when `sessionKind == .escort`; must be an accepted app relationship id.
    var escortRelationshipId: String?

    init(
        clientSessionID: UUID = UUID(),
        activatedAt: Date = Date(),
        lastKnownLocation: SOSLocationSnapshot,
        recentTrail: [SOSLocationSnapshot] = [],
        directionOfTravel: SOSDirectionOfTravel? = nil,
        trustedContactsToNotify: [SOSTrustedContactNotificationTarget] = [],
        deviceMetadata: SOSDeviceMetadata = .current(),
        privacyPolicy: SOSPrivacyPolicy = .default,
        source: String = "ios",
        sessionKind: SOSSessionKind? = nil,
        escortRelationshipId: String? = nil
    ) {
        self.clientSessionID = clientSessionID
        self.activatedAt = activatedAt
        self.lastKnownLocation = lastKnownLocation
        self.recentTrail = recentTrail
        self.directionOfTravel = directionOfTravel
        self.trustedContactsToNotify = trustedContactsToNotify
        self.deviceMetadata = deviceMetadata
        self.privacyPolicy = privacyPolicy
        self.source = source
        self.sessionKind = sessionKind
        self.escortRelationshipId = escortRelationshipId
    }

    var functionPayload: [String: Any] {
        let dto = contractPayload
        // Existing SOS fields stay snake_case for the callable. New escort fields use
        // ContractDTO coding-key names (camelCase) on the wire: sessionKind / escortRelationshipId.
        return [
            "client_session_id": dto.clientSessionID,
            "activated_at": SOSPayloadCoding.string(from: dto.activatedAt),
            "source": dto.source,
            "last_known_location": dto.lastKnownLocation.functionPayload,
            "recent_trail": dto.recentTrail.map(\.functionPayload),
            "direction_of_travel": dto.directionOfTravel?.functionPayload as Any,
            "trusted_contacts_to_notify": dto.trustedContacts.map(\.functionPayload),
            "device": dto.device.functionPayload,
            "privacy": dto.privacy.functionPayload,
            "sessionKind": dto.sessionKind?.rawValue as Any,
            "escortRelationshipId": dto.escortRelationshipID as Any
        ].compactingNilValuesForSOS
    }

    var redactedDiagnosticsPayload: [String: Any] {
        [
            "client_session_id": clientSessionID.uuidString,
            "activated_at": SOSPayloadCoding.string(from: activatedAt),
            "source": source,
            "last_known_location": lastKnownLocation.redactedPayload,
            "recent_trail_count": privacyScopedTrail.count,
            "direction_of_travel": resolvedDirectionOfTravel?.functionPayload as Any,
            "trusted_contacts_to_notify": trustedContactsToNotify.map(\.redactedPayload),
            "device": deviceMetadata.functionPayload,
            "privacy": privacyPolicy.functionPayload,
            "sessionKind": sessionKind?.rawValue as Any,
            "escortRelationshipId": escortRelationshipId as Any
        ].compactingNilValuesForSOS
    }

    private var privacyScopedTrail: [SOSLocationSnapshot] {
        guard privacyPolicy.includeRecentTrail else {
            return []
        }

        let oldestAllowed = activatedAt.addingTimeInterval(-privacyPolicy.recentTrailMaxAgeSeconds)
        let filtered = recentTrail
            .filter { $0.capturedAt >= oldestAllowed && $0.capturedAt <= activatedAt }
            .sorted { $0.capturedAt < $1.capturedAt }

        return Array(filtered.suffix(privacyPolicy.recentTrailMaxPoints))
    }

    private var resolvedDirectionOfTravel: SOSDirectionOfTravel? {
        directionOfTravel ?? SOSDirectionOfTravel(recentTrail: privacyScopedTrail + [lastKnownLocation])
    }

    private var contractPayload: ContractDTO.ActivationPayload {
        let contractKind: ContractDTO.SessionKind? = {
            guard let sessionKind else { return nil }
            return ContractDTO.SessionKind(rawValue: sessionKind.rawValue)
        }()
        return ContractDTO.ActivationPayload(
            activatedAt: activatedAt,
            clientSessionID: clientSessionID.uuidString,
            device: deviceMetadata.contractDTO,
            directionOfTravel: resolvedDirectionOfTravel?.contractDTO,
            escortRelationshipID: escortRelationshipId,
            lastKnownLocation: lastKnownLocation.contractDTO,
            privacy: privacyPolicy.contractDTO,
            recentTrail: privacyScopedTrail.map(\.contractDTO),
            sessionKind: contractKind,
            source: source,
            trustedContacts: trustedContactsToNotify.map(\.contractDTO)
        )
    }
}

struct SOSLocationUpdatePayload: Equatable {
    var location: SOSLocationSnapshot
    var sequenceNumber: Int
    var directionOfTravel: SOSDirectionOfTravel?
    var deviceMetadata: SOSDeviceMetadata

    init(
        location: SOSLocationSnapshot,
        sequenceNumber: Int,
        directionOfTravel: SOSDirectionOfTravel? = nil,
        deviceMetadata: SOSDeviceMetadata = .current()
    ) {
        self.location = location
        self.sequenceNumber = max(0, sequenceNumber)
        self.directionOfTravel = directionOfTravel
        self.deviceMetadata = deviceMetadata
    }

    var functionPayload: [String: Any] {
        let dto = contractPayload(sessionID: "")
        return [
            "location": dto.location.functionPayload,
            "sequence_number": dto.sequenceNumber,
            "captured_at": SOSPayloadCoding.string(from: dto.capturedAt),
            "direction_of_travel": dto.directionOfTravel?.functionPayload as Any,
            "device": dto.device.functionPayload
        ].compactingNilValuesForSOS
    }

    func contractPayload(sessionID: String) -> ContractDTO.LocationUpdatePayload {
        ContractDTO.LocationUpdatePayload(
            capturedAt: location.capturedAt,
            device: deviceMetadata.contractDTO,
            directionOfTravel: directionOfTravel?.contractDTO,
            location: location.contractDTO,
            sequenceNumber: sequenceNumber,
            sessionID: sessionID
        )
    }
}

struct SOSResolutionPayload: Equatable {
    var sessionID: String
    var reason: SOSResolutionReason
    var finalLocation: SOSLocationSnapshot?
    var resolvedAt: Date

    var functionPayload: [String: Any] {
        let dto = contractPayload
        return [
            "session_id": dto.sessionID,
            "resolution_reason": dto.reason.rawValue,
            "resolved_at": SOSPayloadCoding.string(from: dto.resolvedAt),
            "final_location": dto.finalLocation?.functionPayload as Any
        ].compactingNilValuesForSOS
    }

    private var contractPayload: ContractDTO.ResolutionPayload {
        ContractDTO.ResolutionPayload(
            finalLocation: finalLocation?.contractDTO,
            reason: reason.contractDTO,
            resolvedAt: resolvedAt,
            sessionID: sessionID
        )
    }
}

enum SOSResolutionReason: String, Codable, CaseIterable, Equatable {
    case userResolved = "user_resolved"
    case falseAlarm = "false_alarm"
    case timedOut = "timed_out"
    case transferredToCareTeam = "transferred_to_care_team"
    case arrivedSafely = "arrived_safely"
}

struct SOSActivationResponse {
    var sessionID: String
    var trustedContactsNotified: [UUID]
    var trustedContactsOptedOut: [UUID]
    var appTrustedContactsNotified: [String]
    var notificationSummary: SOSNotificationSummary
    var expiresAt: Date?

    init(resultData: Any) throws {
        guard
            let body = resultData as? [String: Any],
            let sessionID = body["session_id"] as? String
        else {
            throw SOSRemoteStoreError.invalidResponse
        }

        self.sessionID = sessionID
        self.trustedContactsNotified = (body["trusted_contacts_notified"] as? [String] ?? [])
            .compactMap(UUID.init(uuidString:))
        self.trustedContactsOptedOut = (body["trusted_contacts_opted_out"] as? [String] ?? [])
            .compactMap(UUID.init(uuidString:))
        self.appTrustedContactsNotified = body["app_trusted_contacts_notified"] as? [String] ?? []
        self.notificationSummary = SOSNotificationSummary(resultData: body["notification_summary"])
        self.expiresAt = SOSPayloadCoding.date(from: body["expires_at"])
    }
}

struct SOSNotificationStatus {
    var sessionID: String
    var status: String
    var sagaStatus: String
    var trustedContactsNotified: [UUID]
    var trustedContactsOptedOut: [UUID]
    var appTrustedContactsNotified: [String]
    var notificationSummary: SOSNotificationSummary

    /// True once the backend notification saga has finished (or failed) so the client
    /// can stop polling for delivery results.
    var isSettled: Bool {
        sagaStatus == "completed" || sagaStatus == "failed"
    }

    init(resultData: Any) throws {
        guard let body = resultData as? [String: Any] else {
            throw SOSRemoteStoreError.invalidResponse
        }

        self.sessionID = body["session_id"] as? String ?? ""
        self.status = body["status"] as? String ?? "active"
        self.sagaStatus = body["notification_saga_status"] as? String ?? "pending"
        self.trustedContactsNotified = (body["trusted_contacts_notified"] as? [String] ?? [])
            .compactMap(UUID.init(uuidString:))
        self.trustedContactsOptedOut = (body["trusted_contacts_opted_out"] as? [String] ?? [])
            .compactMap(UUID.init(uuidString:))
        self.appTrustedContactsNotified = body["app_trusted_contacts_notified"] as? [String] ?? []
        self.notificationSummary = SOSNotificationSummary(resultData: body["notification_summary"])
    }
}

struct SOSAppTrustedContactInvite: Equatable {
    var inviteID: String
    var inviteCode: String
    var expiresAt: Date?

    init(resultData: Any) throws {
        guard
            let body = resultData as? [String: Any],
            let inviteID = body["invite_id"] as? String,
            let inviteCode = body["invite_code"] as? String
        else {
            throw SOSRemoteStoreError.invalidResponse
        }

        self.inviteID = inviteID
        self.inviteCode = inviteCode
        self.expiresAt = SOSPayloadCoding.date(from: body["expires_at"])
    }
}

struct SOSAppTrustedContactRelationship: Identifiable, Equatable {
    var id: String
    var ownerUID: String
    var trustedContactUID: String?
    var ownerDisplayName: String
    var trustedContactDisplayName: String
    var status: String

    init(resultData: Any) throws {
        guard
            let body = resultData as? [String: Any],
            let relationshipID = body["relationship_id"] as? String,
            let ownerUID = body["owner_uid"] as? String
        else {
            throw SOSRemoteStoreError.invalidResponse
        }

        self.id = relationshipID
        self.ownerUID = ownerUID
        self.trustedContactUID = body["trusted_contact_uid"] as? String
        self.ownerDisplayName = body["owner_display_name"] as? String ?? "PulseTrackr user"
        self.trustedContactDisplayName = body["trusted_contact_display_name"] as? String ?? "Trusted contact"
        self.status = body["status"] as? String ?? "accepted"
    }
}

struct SOSAppTrustedContactList: Equatable {
    var outgoing: [SOSAppTrustedContactRelationship]
    var incoming: [SOSAppTrustedContactRelationship]

    init(resultData: Any) {
        let body = resultData as? [String: Any] ?? [:]
        self.outgoing = Self.relationships(from: body["outgoing"])
        self.incoming = Self.relationships(from: body["incoming"])
    }

    private static func relationships(from value: Any?) -> [SOSAppTrustedContactRelationship] {
        guard let rows = value as? [[String: Any]] else { return [] }
        return rows.compactMap { try? SOSAppTrustedContactRelationship(resultData: $0) }
    }
}

struct SOSAppAlert: Identifiable, Equatable {
    var id: String
    var sessionID: String
    var ownerUID: String
    var ownerDisplayName: String
    var status: String
    var lastKnownLocation: SOSLocationSnapshot?
    var updatedAt: Date
    /// Defaults to `.sos` when absent (legacy alert docs predate escort).
    var kind: SOSSessionKind

    init?(document: QueryDocumentSnapshot) {
        let data = document.data()
        guard
            let sessionID = data["sessionId"] as? String,
            let ownerUID = data["ownerUid"] as? String
        else {
            return nil
        }

        self.id = document.documentID
        self.sessionID = sessionID
        self.ownerUID = ownerUID
        self.ownerDisplayName = data["ownerDisplayName"] as? String ?? "PulseTrackr user"
        self.status = data["status"] as? String ?? "active"
        self.lastKnownLocation = Self.location(from: data["lastKnownLocation"])
        self.updatedAt = Self.date(from: data["updatedAt"]) ?? Self.date(from: data["createdAt"]) ?? Date.distantPast
        self.kind = Self.sessionKind(from: data)
    }

    /// Test and in-memory construction path (Firestore documents use `init?(document:)`).
    init(
        id: String,
        sessionID: String,
        ownerUID: String,
        ownerDisplayName: String,
        status: String,
        lastKnownLocation: SOSLocationSnapshot?,
        updatedAt: Date,
        kind: SOSSessionKind = .sos
    ) {
        self.id = id
        self.sessionID = sessionID
        self.ownerUID = ownerUID
        self.ownerDisplayName = ownerDisplayName
        self.status = status
        self.lastKnownLocation = lastKnownLocation
        self.updatedAt = updatedAt
        self.kind = kind
    }

    private static func sessionKind(from data: [String: Any]) -> SOSSessionKind {
        let raw = (data["kind"] as? String)
            ?? (data["sessionKind"] as? String)
            ?? (data["session_kind"] as? String)
        return raw.flatMap(SOSSessionKind.init(rawValue:)) ?? .sos
    }

    private static func location(from value: Any?) -> SOSLocationSnapshot? {
        guard let data = value as? [String: Any] else { return nil }
        guard
            let latitude = data["latitude"] as? Double,
            let longitude = data["longitude"] as? Double
        else {
            return nil
        }

        return SOSLocationSnapshot(
            latitude: latitude,
            longitude: longitude,
            horizontalAccuracyMeters: data["horizontalAccuracyMeters"] as? Double,
            altitudeMeters: data["altitudeMeters"] as? Double,
            speedMetersPerSecond: data["speedMetersPerSecond"] as? Double,
            courseDegrees: data["courseDegrees"] as? Double,
            capturedAt: date(from: data["capturedAt"]) ?? Date()
        )
    }

    private static func date(from value: Any?) -> Date? {
        if let timestamp = value as? Timestamp {
            return timestamp.dateValue()
        }
        return SOSPayloadCoding.date(from: value)
    }
}

final class SOSAppAlertObservation {
    private let registration: ListenerRegistration

    init(registration: ListenerRegistration) {
        self.registration = registration
    }

    deinit {
        registration.remove()
    }
}

struct SOSNotificationSummary: Equatable {
    var queued: Int
    var sent: Int
    var failed: Int
    var skipped: Int
    var optedOut: Int

    init(queued: Int = 0, sent: Int = 0, failed: Int = 0, skipped: Int = 0, optedOut: Int = 0) {
        self.queued = queued
        self.sent = sent
        self.failed = failed
        self.skipped = skipped
        self.optedOut = optedOut
    }

    init(resultData: Any?) {
        guard let body = resultData as? [String: Any] else {
            self.init()
            return
        }

        self.init(
            queued: Self.int(body["queued"]),
            sent: Self.int(body["sent"]),
            failed: Self.int(body["failed"]),
            skipped: Self.int(body["skipped"]),
            optedOut: Self.int(body["optedOut"] ?? body["opted_out"])
        )
    }

    private static func int(_ value: Any?) -> Int {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return 0
    }
}

private extension SOSLocationSnapshot {
    var contractDTO: ContractDTO.SOSLocation {
        ContractDTO.SOSLocation(
            altitudeMeters: altitudeMeters,
            capturedAt: capturedAt,
            courseDegrees: courseDegrees,
            horizontalAccuracyMeters: horizontalAccuracyMeters,
            latitude: latitude,
            longitude: longitude,
            speedMetersPerSecond: speedMetersPerSecond
        )
    }
}

private extension SOSDirectionOfTravel {
    var contractDTO: ContractDTO.DirectionOfTravel {
        ContractDTO.DirectionOfTravel(
            bearingDegrees: bearingDegrees,
            computedFromPointCount: computedFromPointCount,
            speedMetersPerSecond: speedMetersPerSecond
        )
    }
}

private extension SOSDeviceMetadata {
    var contractDTO: ContractDTO.SOSDevice {
        ContractDTO.SOSDevice(
            appVersion: appVersion,
            batteryLevelPercent: batteryLevelPercent,
            batteryState: batteryState,
            buildNumber: buildNumber,
            deviceModel: deviceModel,
            lowPowerModeEnabled: lowPowerModeEnabled ? true : nil,
            networkInterfaceTypes: networkInterfaceTypes.isEmpty ? nil : networkInterfaceTypes,
            networkStatus: networkStatus,
            systemVersion: systemVersion
        )
    }
}

private extension SOSPrivacyPolicy {
    var contractDTO: ContractDTO.PrivacyPolicy {
        ContractDTO.PrivacyPolicy(
            adminAccessExpiresAfterSeconds: Int(adminAccessExpiresAfterSeconds),
            auditPrivilegedAccess: auditPrivilegedAccess,
            includeRecentTrail: includeRecentTrail,
            lawEnforcementAccessRequiresActiveSession: lawEnforcementAccessRequiresActiveSession,
            liveLocationUpdateIntervalSeconds: Int(liveLocationUpdateIntervalSeconds),
            recentTrailMaxAgeSeconds: Int(recentTrailMaxAgeSeconds),
            recentTrailMaxPoints: recentTrailMaxPoints,
            shareExactLocationWithTrustedContacts: shareExactLocationWithTrustedContacts
        )
    }
}

private extension SOSTrustedContactNotificationTarget {
    var contractDTO: ContractDTO.TrustedContact {
        ContractDTO.TrustedContact(
            appRelationshipID: appRelationshipID,
            appUserUid: appUserUID,
            channels: channels.compactMap(\.contractDTO),
            consentedAt: consentedAt,
            contactID: contactID.uuidString,
            displayName: displayName,
            emailAddress: emailAddress,
            phoneNumber: phoneNumber,
            relationshipLabel: relationshipLabel
        )
    }
}

private extension SOSTrustedContactChannel {
    var contractDTO: ContractDTO.NotificationChannel? {
        ContractDTO.NotificationChannel(rawValue: rawValue)
    }
}

private extension SOSResolutionReason {
    var contractDTO: ContractDTO.ResolutionReason {
        ContractDTO.ResolutionReason(rawValue: rawValue) ?? .userResolved
    }
}

private extension ContractDTO.SOSLocation {
    var functionPayload: [String: Any] {
        [
            "latitude": latitude,
            "longitude": longitude,
            "horizontal_accuracy_meters": horizontalAccuracyMeters as Any,
            "altitude_meters": altitudeMeters as Any,
            "speed_meters_per_second": speedMetersPerSecond as Any,
            "course_degrees": courseDegrees as Any,
            "captured_at": SOSPayloadCoding.string(from: capturedAt)
        ].compactingNilValuesForSOS
    }
}

private extension ContractDTO.DirectionOfTravel {
    var functionPayload: [String: Any] {
        [
            "bearing_degrees": bearingDegrees as Any,
            "speed_meters_per_second": speedMetersPerSecond as Any,
            "computed_from_point_count": computedFromPointCount as Any
        ].compactingNilValuesForSOS
    }
}

private extension ContractDTO.SOSDevice {
    var functionPayload: [String: Any] {
        [
            "battery_level_percent": batteryLevelPercent as Any,
            "battery_state": batteryState as Any,
            "low_power_mode_enabled": lowPowerModeEnabled as Any,
            "network_status": networkStatus as Any,
            "network_interface_types": networkInterfaceTypes as Any,
            "app_version": appVersion as Any,
            "build_number": buildNumber as Any,
            "device_model": deviceModel as Any,
            "system_version": systemVersion as Any
        ].compactingNilValuesForSOS
    }
}

private extension ContractDTO.PrivacyPolicy {
    var functionPayload: [String: Any] {
        [
            "include_recent_trail": includeRecentTrail,
            "recent_trail_max_points": recentTrailMaxPoints,
            "recent_trail_max_age_seconds": recentTrailMaxAgeSeconds,
            "live_location_update_interval_seconds": liveLocationUpdateIntervalSeconds,
            "share_exact_location_with_trusted_contacts": shareExactLocationWithTrustedContacts,
            "admin_access_expires_after_seconds": adminAccessExpiresAfterSeconds,
            "law_enforcement_access_requires_active_session": lawEnforcementAccessRequiresActiveSession,
            "audit_privileged_access": auditPrivilegedAccess
        ]
    }
}

private extension ContractDTO.TrustedContact {
    var functionPayload: [String: Any] {
        [
            "contact_id": contactID,
            "display_name": displayName,
            "relationship_label": relationshipLabel as Any,
            "phone_number": phoneNumber as Any,
            "email_address": emailAddress as Any,
            "app_user_uid": appUserUid as Any,
            "app_relationship_id": appRelationshipID as Any,
            "channels": channels.map(\.rawValue),
            "consented_at": consentedAt.map(SOSPayloadCoding.string(from:)) as Any
        ].compactingNilValuesForSOS
    }
}

enum SOSRemoteStoreError: Error, Equatable {
    case invalidResponse
}

struct SOSLocationSnapshot: Codable, Equatable {
    var latitude: Double
    var longitude: Double
    var horizontalAccuracyMeters: Double?
    var altitudeMeters: Double?
    var speedMetersPerSecond: Double?
    var courseDegrees: Double?
    var capturedAt: Date

    init?(
        latitude: Double,
        longitude: Double,
        horizontalAccuracyMeters: Double? = nil,
        altitudeMeters: Double? = nil,
        speedMetersPerSecond: Double? = nil,
        courseDegrees: Double? = nil,
        capturedAt: Date = Date()
    ) {
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        guard CLLocationCoordinate2DIsValid(coordinate) else {
            return nil
        }

        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracyMeters = horizontalAccuracyMeters?.nonNegativeForSOS
        self.altitudeMeters = altitudeMeters
        self.speedMetersPerSecond = speedMetersPerSecond?.nonNegativeForSOS
        self.courseDegrees = courseDegrees?.normalizedDegreesForSOS
        self.capturedAt = capturedAt
    }

    init?(location: CLLocation, capturedAt: Date? = nil) {
        self.init(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            horizontalAccuracyMeters: location.horizontalAccuracy,
            altitudeMeters: location.verticalAccuracy >= 0 ? location.altitude : nil,
            speedMetersPerSecond: location.speed >= 0 ? location.speed : nil,
            courseDegrees: location.course >= 0 ? location.course : nil,
            capturedAt: capturedAt ?? location.timestamp
        )
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var functionPayload: [String: Any] {
        [
            "latitude": latitude,
            "longitude": longitude,
            "horizontal_accuracy_meters": horizontalAccuracyMeters as Any,
            "altitude_meters": altitudeMeters as Any,
            "speed_meters_per_second": speedMetersPerSecond as Any,
            "course_degrees": courseDegrees as Any,
            "captured_at": SOSPayloadCoding.string(from: capturedAt)
        ].compactingNilValuesForSOS
    }

    var redactedPayload: [String: Any] {
        [
            "latitude": (latitude * 100).rounded() / 100,
            "longitude": (longitude * 100).rounded() / 100,
            "captured_at": SOSPayloadCoding.string(from: capturedAt)
        ]
    }
}

struct SOSDirectionOfTravel: Codable, Equatable {
    var bearingDegrees: Double
    var speedMetersPerSecond: Double?
    var computedFromPointCount: Int

    init?(bearingDegrees: Double?, speedMetersPerSecond: Double? = nil, computedFromPointCount: Int = 0) {
        guard let bearingDegrees else {
            return nil
        }

        self.bearingDegrees = bearingDegrees.normalizedDegreesForSOS
        self.speedMetersPerSecond = speedMetersPerSecond?.nonNegativeForSOS
        self.computedFromPointCount = max(0, computedFromPointCount)
    }

    init?(recentTrail: [SOSLocationSnapshot]) {
        let sortedTrail = recentTrail.sorted { $0.capturedAt < $1.capturedAt }
        guard
            let previous = sortedTrail.dropLast().last,
            let latest = sortedTrail.last
        else {
            return nil
        }

        self.init(
            bearingDegrees: Self.bearingDegrees(from: previous, to: latest),
            speedMetersPerSecond: latest.speedMetersPerSecond,
            computedFromPointCount: sortedTrail.count
        )
    }

    var functionPayload: [String: Any] {
        [
            "bearing_degrees": bearingDegrees,
            "speed_meters_per_second": speedMetersPerSecond as Any,
            "computed_from_point_count": computedFromPointCount
        ].compactingNilValuesForSOS
    }

    static func bearingDegrees(from start: SOSLocationSnapshot, to end: SOSLocationSnapshot) -> Double? {
        guard start.latitude != end.latitude || start.longitude != end.longitude else {
            return nil
        }

        let startLatitude = start.latitude * .pi / 180
        let endLatitude = end.latitude * .pi / 180
        let longitudeDelta = (end.longitude - start.longitude) * .pi / 180
        let y = sin(longitudeDelta) * cos(endLatitude)
        let x = cos(startLatitude) * sin(endLatitude) -
            sin(startLatitude) * cos(endLatitude) * cos(longitudeDelta)

        return (atan2(y, x) * 180 / .pi).normalizedDegreesForSOS
    }
}

struct SOSDeviceMetadata: Codable, Equatable {
    var batteryLevelPercent: Int?
    var batteryState: String?
    var lowPowerModeEnabled: Bool
    var networkStatus: String?
    var networkInterfaceTypes: [String]
    var appVersion: String?
    var buildNumber: String?
    var deviceModel: String?
    var systemVersion: String?

    init(
        batteryLevelPercent: Int? = nil,
        batteryState: String? = nil,
        lowPowerModeEnabled: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled,
        networkStatus: String? = nil,
        networkInterfaceTypes: [String] = [],
        appVersion: String? = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
        buildNumber: String? = Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
        deviceModel: String? = SOSDeviceMetadata.currentDeviceModel,
        systemVersion: String? = SOSDeviceMetadata.currentSystemVersion
    ) {
        self.batteryLevelPercent = batteryLevelPercent.map { min(100, max(0, $0)) }
        self.batteryState = batteryState
        self.lowPowerModeEnabled = lowPowerModeEnabled
        self.networkStatus = networkStatus
        self.networkInterfaceTypes = networkInterfaceTypes
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.deviceModel = deviceModel
        self.systemVersion = systemVersion
    }

    static func current(
        networkStatus: String? = nil,
        networkInterfaceTypes: [String] = []
    ) -> SOSDeviceMetadata {
        SOSDeviceMetadata(
            batteryLevelPercent: currentBatteryLevelPercent,
            batteryState: currentBatteryState,
            networkStatus: networkStatus,
            networkInterfaceTypes: networkInterfaceTypes
        )
    }

    var functionPayload: [String: Any] {
        [
            "battery_level_percent": batteryLevelPercent as Any,
            "battery_state": batteryState as Any,
            "low_power_mode_enabled": lowPowerModeEnabled,
            "network_status": networkStatus as Any,
            "network_interface_types": networkInterfaceTypes,
            "app_version": appVersion as Any,
            "build_number": buildNumber as Any,
            "device_model": deviceModel as Any,
            "system_version": systemVersion as Any
        ].compactingNilValuesForSOS
    }

    private static var currentBatteryLevelPercent: Int? {
        #if canImport(UIKit)
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        guard level >= 0 else { return nil }
        return Int((level * 100).rounded())
        #else
        return nil
        #endif
    }

    private static var currentBatteryState: String? {
        #if canImport(UIKit)
        switch UIDevice.current.batteryState {
        case .unknown: return nil
        case .unplugged: return "unplugged"
        case .charging: return "charging"
        case .full: return "full"
        @unknown default: return nil
        }
        #else
        return nil
        #endif
    }

    private static var currentDeviceModel: String? {
        #if canImport(UIKit)
        return UIDevice.current.model
        #else
        return nil
        #endif
    }

    private static var currentSystemVersion: String? {
        #if canImport(UIKit)
        return UIDevice.current.systemVersion
        #else
        return ProcessInfo.processInfo.operatingSystemVersionString
        #endif
    }
}

#if canImport(Network)
extension SOSDeviceMetadata {
    static func current(path: NWPath) -> SOSDeviceMetadata {
        current(
            networkStatus: path.status.sosDescription,
            networkInterfaceTypes: NWInterface.InterfaceType.sosCommonTypes
                .filter { path.usesInterfaceType($0) }
                .map(\.sosDescription)
        )
    }
}

private extension NWPath.Status {
    var sosDescription: String {
        switch self {
        case .satisfied: "satisfied"
        case .unsatisfied: "unsatisfied"
        case .requiresConnection: "requires_connection"
        @unknown default: "unknown"
        }
    }
}

private extension NWInterface.InterfaceType {
    static var sosCommonTypes: [NWInterface.InterfaceType] {
        [.wifi, .cellular, .wiredEthernet, .loopback, .other]
    }

    var sosDescription: String {
        switch self {
        case .wifi: "wifi"
        case .cellular: "cellular"
        case .wiredEthernet: "wired_ethernet"
        case .loopback: "loopback"
        case .other: "other"
        @unknown default: "unknown"
        }
    }
}
#endif

private extension Dictionary where Key == String, Value == Any {
    var compactingNilValuesForSOS: [String: Any] {
        compactMapValues { value in
            if isNilForSOS(value) {
                return nil
            }
            return value
        }
    }
}

private func isNilForSOS(_ value: Any) -> Bool {
    let mirror = Mirror(reflecting: value)
    return mirror.displayStyle == .optional && mirror.children.isEmpty
}

private extension Double {
    var nonNegativeForSOS: Double {
        max(0, self)
    }

    var normalizedDegreesForSOS: Double {
        let value = truncatingRemainder(dividingBy: 360)
        return value >= 0 ? value : value + 360
    }
}
