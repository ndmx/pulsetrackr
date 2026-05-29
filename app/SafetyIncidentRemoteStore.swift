import CoreLocation
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

        var payload: [String: Any] = [
            "title": title,
            "summary": summary,
            "category": category.rawValue,
            "subtype": subtype.rawValue,
            "severity": severity.rawValue,
            "status": status.rawValue,
            "neighborhood": neighborhood,
            "use_approximate_location": useApproximateLocation,
            "client_ref": clientRef,
            "source": "ios",
            "evidence": evidence.map(\.payload)
        ]

        if let reporterCoordinate {
            payload["latitude"] = reporterCoordinate.latitude
            payload["longitude"] = reporterCoordinate.longitude
        }

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

    func recordSignal(
        _ signal: CommunitySignal,
        forIncidentWithID id: UUID,
        newStatus: IncidentStatus,
        newSeverity: IncidentSeverity
    ) async throws {
        try await ensureSignedIn()

        var fields: [String: Any] = [
            "status": newStatus.rawValue,
            "severity": newSeverity.rawValue
        ]
        switch signal {
        case .seen:        fields["confirmations"]   = FieldValue.increment(Int64(1))
        case .notSeen:     fields["disputes"]        = FieldValue.increment(Int64(1))
        case .unsafe:      fields["unsafe_reports"]  = FieldValue.increment(Int64(1))
        case .roadBlocked: fields["blocked_reports"] = FieldValue.increment(Int64(1))
        case .cleared:     fields["cleared_reports"] = FieldValue.increment(Int64(1))
        }

        try await db.collection("safety_incidents_public")
            .document(id.uuidString)
            .updateData(fields)
    }

    private func ensureSignedIn() async throws {
        if Auth.auth().currentUser != nil { return }
        try await Auth.auth().signInAnonymously()
    }

    private func callFunction(named name: String, data: [String: Any]) async throws -> HTTPSCallableResult {
        try await functions.httpsCallable(name).call(data)
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
        let data = document.data()
        let id = UUID(uuidString: document.documentID) ?? UUID()
        let category = IncidentCategory(rawValue: string(data["category"]) ?? "") ?? .community
        let subtype = IncidentSubtype(rawValue: string(data["subtype"]) ?? "") ?? IncidentSubtype.defaultSubtype(for: category)
        let severity = IncidentSeverity(rawValue: string(data["severity"]) ?? "") ?? .medium
        let status = IncidentStatus(rawValue: string(data["status"]) ?? "") ?? .active
        // Missing coordinates → nil (location unknown), not a fabricated default pin.
        let coordinate: CLLocationCoordinate2D?
        if let latitude = double(data["latitude"]), let longitude = double(data["longitude"]) {
            coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        } else {
            coordinate = nil
        }

        return Incident(
            id: id,
            title: string(data["title"]) ?? subtype.label,
            summary: string(data["summary"]) ?? "Community incident report.",
            category: category,
            subtype: subtype.category == category ? subtype : IncidentSubtype.defaultSubtype(for: category),
            severity: severity,
            status: status,
            reporterCoordinate: nil,
            coordinate: coordinate,
            neighborhood: string(data["neighborhood"]) ?? "Nearby area",
            reportedAt: date(data["reported_at"]) ?? Date(),
            confirmations: int(data["confirmations"]) ?? 1,
            disputes: int(data["disputes"]) ?? 0,
            unsafeReports: int(data["unsafe_reports"]) ?? 0,
            blockedReports: int(data["blocked_reports"]) ?? 0,
            clearedReports: int(data["cleared_reports"]) ?? 0,
            officialUpdates: int(data["official_updates"]) ?? 0,
            updates: []
        )
    }

    private static func string(_ value: Any?) -> String? {
        value as? String
    }

    private static func int(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }

    private static func double(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }

    private static func date(_ value: Any?) -> Date? {
        if let value = value as? Timestamp { return value.dateValue() }
        if let value = value as? Date { return value }
        return nil
    }
}

enum SafetyIncidentRemoteStoreError: Error {
    case invalidResponse
}
