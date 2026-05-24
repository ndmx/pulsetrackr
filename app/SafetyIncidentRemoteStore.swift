import CoreLocation
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import FirebaseFunctions
import Foundation

final class SafetyIncidentRemoteStore {
    private let db: Firestore
    private let functions: Functions
    private var listener: ListenerRegistration?

    static func makeIfConfigured() -> SafetyIncidentRemoteStore? {
        guard FirebaseBootstrap.configureIfAvailable() else { return nil }
        return SafetyIncidentRemoteStore()
    }

    private init(
        db: Firestore = Firestore.firestore(),
        functions: Functions = Functions.functions()
    ) {
        self.db = db
        self.functions = functions
    }

    deinit {
        listener?.remove()
    }

    func observeActiveIncidents(_ onChange: @escaping ([Incident]) -> Void) {
        listener?.remove()
        listener = db.collection("safety_incidents_public")
            .whereField("status", in: [IncidentStatus.active.rawValue, IncidentStatus.watching.rawValue])
            .order(by: "reported_at", descending: true)
            .addSnapshotListener { snapshot, error in
                guard error == nil, let snapshot else { return }
                let incidents = snapshot.documents.compactMap(Self.incident(from:))
                onChange(incidents)
            }
    }

    func submitIncident(
        title: String,
        summary: String,
        category: IncidentCategory,
        subtype: IncidentSubtype,
        severity: IncidentSeverity,
        neighborhood: String,
        reporterCoordinate: CLLocationCoordinate2D?,
        useApproximateLocation: Bool
    ) async throws -> String {
        try await ensureSignedIn()

        var payload: [String: Any] = [
            "title": title,
            "summary": summary,
            "category": category.rawValue,
            "subtype": subtype.rawValue,
            "severity": severity.rawValue,
            "neighborhood": neighborhood,
            "use_approximate_location": useApproximateLocation,
            "client_ref": UUID().uuidString,
            "source": "ios"
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

    private static func incident(from document: QueryDocumentSnapshot) -> Incident? {
        let data = document.data()
        let id = UUID(uuidString: document.documentID) ?? UUID()
        let category = IncidentCategory(rawValue: string(data["category"]) ?? "") ?? .community
        let subtype = IncidentSubtype(rawValue: string(data["subtype"]) ?? "") ?? IncidentSubtype.defaultSubtype(for: category)
        let severity = IncidentSeverity(rawValue: string(data["severity"]) ?? "") ?? .medium
        let status = IncidentStatus(rawValue: string(data["status"]) ?? "") ?? .active
        let coordinate = CLLocationCoordinate2D(
            latitude: double(data["latitude"]) ?? 6.5244,
            longitude: double(data["longitude"]) ?? 3.3792
        )

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
