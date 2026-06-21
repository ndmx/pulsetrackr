import CoreLocation
import CryptoKit
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import FirebaseFunctions
import FirebaseStorage
import Foundation

final class SafetyIncidentRemoteStore {
    private let db: Firestore
    private let functions: Functions
    private let storage: Storage

    // Geo-bounded incident feed: one listener per covering geohash prefix, each
    // owning a bucket of documents. Buckets are merged, distance-filtered, and
    // emitted whenever any listener fires. Firestore delivers listener callbacks on
    // the main thread by default, so the shared state below is accessed serially.
    private var geoListeners: [ListenerRegistration] = []
    private var geoBuckets: [Int: [String: Incident]] = [:]
    /// Per-document upper bound on a single prefix range, before client filtering.
    private let perPrefixLimit = 200

    static let activeStatuses: Set<IncidentStatus> = [.active, .watching]

    static func makeIfConfigured() -> SafetyIncidentRemoteStore? {
        // Never attach a live Firebase-backed store under XCTest: unit tests must not
        // make network calls (they would block the MainActor and starve parallel tests).
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return nil }
        guard FirebaseBootstrap.configureIfAvailable() else { return nil }
        return SafetyIncidentRemoteStore()
    }

    private init(
        db: Firestore = Firestore.firestore(),
        functions: Functions = Functions.functions(),
        storage: Storage = Storage.storage()
    ) {
        self.db = db
        self.functions = functions
        self.storage = storage
    }

    deinit {
        stopObservingIncidents()
    }

    func stopObservingIncidents() {
        geoListeners.forEach { $0.remove() }
        geoListeners.removeAll()
        geoBuckets.removeAll()
    }

    /// Observe active incidents within `radiusMeters` of `center`. Instead of
    /// streaming every incident worldwide, this queries only the geohash cells that
    /// cover the circle, then filters to the exact radius and active statuses on the
    /// client. Re-call this when the user moves or changes their radius.
    func observeIncidents(
        near center: CLLocationCoordinate2D,
        radiusMeters: Double,
        onChange: @escaping ([Incident]) -> Void
    ) {
        stopObservingIncidents()
        guard center.isValid else { return }

        let prefixes = Geohash.coveringPrefixes(
            latitude: center.latitude,
            longitude: center.longitude,
            radiusMeters: radiusMeters
        )

        geoListeners = prefixes.enumerated().map { index, prefix in
            db.collection("safety_incidents_public")
                .order(by: "geohash")
                .start(at: [prefix])
                .end(before: [Geohash.rangeEnd(for: prefix)])
                .limit(to: perPrefixLimit)
                .addSnapshotListener { [weak self] snapshot, error in
                    guard let self, error == nil, let snapshot else { return }
                    var bucket: [String: Incident] = [:]
                    for document in snapshot.documents {
                        if let incident = Self.incident(from: document) {
                            bucket[document.documentID] = incident
                        }
                    }
                    self.geoBuckets[index] = bucket
                    onChange(self.mergedIncidents(near: center, radiusMeters: radiusMeters))
                }
        }
    }

    private func mergedIncidents(near center: CLLocationCoordinate2D, radiusMeters: Double) -> [Incident] {
        var merged: [String: Incident] = [:]
        for bucket in geoBuckets.values {
            for (id, incident) in bucket { merged[id] = incident }
        }
        return merged.values
            .filter { incident in
                guard Self.activeStatuses.contains(incident.status),
                      let coordinate = incident.coordinate else { return false }
                return coordinate.distance(to: center) <= radiusMeters
            }
            .sorted { $0.reportedAt > $1.reportedAt }
    }

    /// One-shot scalable feed read via the backend H3 callable. The backend expands the
    /// covering H3 cells and filters expiry/status/privacy server-side, returning
    /// contract-shaped public incidents. Used as a complement to the live geohash
    /// listener (cold start / manual refresh), not a replacement for it.
    func queryIncidentsH3(
        near center: CLLocationCoordinate2D,
        radiusMeters: Double,
        limit: Int = 100
    ) async throws -> [Incident] {
        try await ensureSignedIn()
        let result = try await callFunction(named: "query_incidents_h3", data: [
            "latitude": center.latitude,
            "longitude": center.longitude,
            "radius_meters": radiusMeters,
            "limit": limit
        ])
        guard let body = result.data as? [String: Any] else {
            throw SafetyIncidentRemoteStoreError.invalidResponse
        }
        return Self.decodeCallableIncidents(body)
    }

    func submitIncident(
        title: String,
        summary: String,
        category: IncidentCategory,
        subtype: IncidentSubtype,
        severity: IncidentSeverity,
        status: IncidentStatus,
        neighborhood: String,
        reporterCoordinate: CLLocationCoordinate2D?,
        useApproximateLocation: Bool,
        clientRef: String,
        evidence: [UploadedIncidentEvidence] = []
    ) async throws -> String {
        try await ensureSignedIn()

        // Build the request from the shared contract type (ContractDTO, generated from
        // @pulsetrackr/contract) so the wire shape is enforced by the compiler — a single
        // source of truth shared with the Cloud Function. The app's domain enums share
        // rawValues with the generated ContractDTO enums, so they bridge by rawValue.
        guard
            let dtoCategory = ContractDTO.IncidentCategory(rawValue: category.rawValue),
            let dtoSubtype = ContractDTO.IncidentSubtype(rawValue: subtype.rawValue),
            let dtoSeverity = ContractDTO.IncidentSeverity(rawValue: severity.rawValue),
            let dtoStatus = ContractDTO.IncidentStatus(rawValue: status.rawValue)
        else {
            throw SafetyIncidentRemoteStoreError.invalidResponse
        }

        let dtoEvidence = evidence.map { item in
            ContractDTO.IncidentEvidence(
                contentType: item.contentType,
                durationSeconds: item.durationSeconds,
                kind: ContractDTO.IncidentEvidenceKind(rawValue: item.kind.rawValue) ?? .photo,
                sizeBytes: item.sizeBytes,
                storagePath: item.storagePath
            )
        }

        let request = ContractDTO.SubmitIncidentPayload(
            category: dtoCategory,
            clientRef: clientRef,
            evidence: dtoEvidence,
            latitude: reporterCoordinate?.latitude,
            longitude: reporterCoordinate?.longitude,
            neighborhood: neighborhood,
            severity: dtoSeverity,
            source: "ios",
            status: dtoStatus,
            subtype: dtoSubtype,
            summary: summary,
            title: title,
            useApproximateLocation: useApproximateLocation
        )
        let payload = try Self.callablePayload(from: request)

        let result = try await callFunction(named: "submit_incident", data: payload)
        guard
            let body = result.data as? [String: Any],
            let incidentID = body["incident_id"] as? String
        else {
            throw SafetyIncidentRemoteStoreError.invalidResponse
        }
        return incidentID
    }

    func uploadIncidentEvidence(
        _ attachments: [IncidentEvidenceAttachment],
        clientRef: String
    ) async throws -> [UploadedIncidentEvidence] {
        guard !attachments.isEmpty else { return [] }
        try await ensureSignedIn()
        guard let uid = Auth.auth().currentUser?.uid else {
            throw SafetyIncidentRemoteStoreError.invalidResponse
        }

        var uploaded: [UploadedIncidentEvidence] = []
        for attachment in attachments {
            let safeName = attachment.filename
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
            let path = "incident_reports/\(uid)/\(clientRef)/\(UUID().uuidString)-\(safeName)"
            let metadata = StorageMetadata()
            metadata.contentType = attachment.contentType
            metadata.customMetadata = [
                "kind": attachment.kind.rawValue,
                "client_ref": clientRef
            ]

            let ref = storage.reference(withPath: path)
            _ = try await putData(attachment.data, metadata: metadata, at: ref)
            uploaded.append(UploadedIncidentEvidence(
                kind: attachment.kind,
                storagePath: path,
                contentType: attachment.contentType,
                sizeBytes: attachment.data.count,
                durationSeconds: attachment.durationSeconds
            ))
        }
        return uploaded
    }

    /// Records a community signal through the `record_incident_signal` callable.
    /// The public feed is read-only to clients (see firestore.rules); the server
    /// owns the counter increment and the derived status/severity, so the client
    /// no longer sends those — it cannot be trusted to set them.
    func recordSignal(
        _ signal: CommunitySignal,
        forIncidentWithID id: String
    ) async throws {
        try await ensureSignedIn()

        _ = try await callFunction(
            named: "record_incident_signal",
            data: [
                "incident_id": id,
                "signal": signal.rawValue
            ]
        )
    }

    /// Reports objectionable or unsafe user-generated incident content for review.
    /// The local app hides the report immediately; the backend keeps a private,
    /// rate-limited moderation record tied to the anonymous reporter.
    func recordConcern(
        _ reason: IncidentConcernReason,
        forIncidentWithID id: String
    ) async throws {
        try await ensureSignedIn()

        _ = try await callFunction(
            named: "record_incident_concern",
            data: [
                "incident_id": id,
                "reason": reason.rawValue
            ]
        )
    }

    private func ensureSignedIn() async throws {
        if Auth.auth().currentUser != nil { return }
        try await Auth.auth().signInAnonymously()
    }

    private func callFunction(named name: String, data: [String: Any]) async throws -> HTTPSCallableResult {
        try await functions.httpsCallable(name).call(data)
    }

    /// Encodes a Codable contract request into the `[String: Any]` dictionary that
    /// Firebase callables expect, preserving the contract's snake_case wire keys
    /// (e.g. `client_ref`). Optional fields encode via `encodeIfPresent`, so absent
    /// values are simply omitted — matching the previous hand-built payload.
    private static func callablePayload<T: Encodable>(from value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        guard let dictionary = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SafetyIncidentRemoteStoreError.invalidResponse
        }
        return dictionary
    }

    private func putData(
        _ data: Data,
        metadata: StorageMetadata,
        at ref: StorageReference
    ) async throws -> StorageMetadata {
        try await withCheckedThrowingContinuation { continuation in
            ref.putData(data, metadata: metadata) { metadata, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let metadata {
                    continuation.resume(returning: metadata)
                } else {
                    continuation.resume(throwing: SafetyIncidentRemoteStoreError.invalidResponse)
                }
            }
        }
    }

    private static func incident(from document: QueryDocumentSnapshot) -> Incident? {
        guard let dto = publicIncidentDTO(from: document.data()) else { return nil }
        return incident(fromDTO: dto, documentID: document.documentID)
    }

    /// Maps a decoded contract public-incident DTO to the app's domain model. Shared
    /// by the Firestore listener path and the H3 callable path so both produce
    /// identical `Incident` values from the same contract type.
    private static func incident(fromDTO dto: ContractDTO.PublicIncident, documentID: String) -> Incident {
        let id = stableIncidentID(for: documentID)
        let category = IncidentCategory(rawValue: dto.category.rawValue) ?? .community
        let subtype = IncidentSubtype(rawValue: dto.subtype.rawValue) ?? IncidentSubtype.defaultSubtype(for: category)
        let severity = IncidentSeverity(rawValue: dto.severity.rawValue) ?? .medium
        let status = IncidentStatus(rawValue: dto.status.rawValue) ?? .active
        let coordinate: CLLocationCoordinate2D?
        if let latitude = dto.latitude, let longitude = dto.longitude {
            coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        } else {
            coordinate = nil
        }

        return Incident(
            id: id,
            remoteDocumentID: documentID,
            title: dto.title.isEmpty ? subtype.label : dto.title,
            summary: dto.summary.isEmpty ? "Community incident report." : dto.summary,
            category: category,
            subtype: subtype.category == category ? subtype : IncidentSubtype.defaultSubtype(for: category),
            severity: severity,
            status: status,
            reporterCoordinate: nil,
            coordinate: coordinate,
            neighborhood: dto.neighborhood,
            reportedAt: dto.reportedAt,
            confirmations: dto.confirmations,
            disputes: dto.disputes,
            unsafeReports: dto.unsafeReports,
            blockedReports: dto.blockedReports,
            clearedReports: dto.clearedReports,
            officialUpdates: dto.officialUpdates,
            updates: []
        )
    }

    /// Decodes the `query_incidents_h3` callable response body into domain incidents,
    /// reusing the same contract DTO + mapping as the Firestore listener path. Internal
    /// (not private) so it can be unit-tested against sample callable payloads.
    static func decodeCallableIncidents(_ body: [String: Any]) -> [Incident] {
        guard let items = body["incidents"] as? [[String: Any]] else { return [] }
        return items.compactMap { item -> Incident? in
            guard let documentID = item["incident_id"] as? String,
                  let dto = publicIncidentDTO(from: item) else { return nil }
            return incident(fromDTO: dto, documentID: documentID)
        }
        .filter { activeStatuses.contains($0.status) }
        .sorted { $0.reportedAt > $1.reportedAt }
    }

    private static func publicIncidentDTO(from firestoreData: [String: Any]) -> ContractDTO.PublicIncident? {
        var data = jsonReadyFirestoreData(firestoreData)
        data["title"] = data["title"] ?? "Community alert"
        data["summary"] = data["summary"] ?? "Community incident report."
        data["category"] = data["category"] ?? ContractDTO.IncidentCategory.community.rawValue
        data["subtype"] = data["subtype"] ?? ContractDTO.IncidentSubtype.localWarning.rawValue
        data["severity"] = data["severity"] ?? ContractDTO.IncidentSeverity.medium.rawValue
        data["status"] = data["status"] ?? ContractDTO.IncidentStatus.active.rawValue
        data["neighborhood"] = data["neighborhood"] ?? "Nearby area"
        data["confirmations"] = data["confirmations"] ?? 1
        data["disputes"] = data["disputes"] ?? 0
        data["unsafe_reports"] = data["unsafe_reports"] ?? 0
        data["blocked_reports"] = data["blocked_reports"] ?? 0
        data["cleared_reports"] = data["cleared_reports"] ?? 0
        data["official_updates"] = data["official_updates"] ?? 0
        data["reported_at"] = data["reported_at"] ?? ISO8601DateFormatter().string(from: Date())

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: data)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(ContractDTO.PublicIncident.self, from: jsonData)
        } catch {
            return nil
        }
    }

    private static func jsonReadyFirestoreData(_ data: [String: Any]) -> [String: Any] {
        data.reduce(into: [:]) { result, entry in
            result[entry.key] = jsonReadyFirestoreValue(entry.value)
        }
    }

    private static func jsonReadyFirestoreValue(_ value: Any) -> Any {
        if let timestamp = value as? Timestamp {
            return ISO8601DateFormatter().string(from: timestamp.dateValue())
        }
        if let date = value as? Date {
            return ISO8601DateFormatter().string(from: date)
        }
        if let dictionary = value as? [String: Any] {
            return jsonReadyFirestoreData(dictionary)
        }
        if let array = value as? [Any] {
            return array.map(jsonReadyFirestoreValue)
        }
        return value
    }

    private static func stableIncidentID(for documentID: String) -> UUID {
        if let uuid = UUID(uuidString: documentID) {
            return uuid
        }

        var bytes = Array(SHA256.hash(data: Data(documentID.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80

        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

enum SafetyIncidentRemoteStoreError: Error {
    case invalidResponse
}
