import Foundation
import MapKit

@MainActor
final class IncidentStore: ObservableObject {
    // Not @Published — we call objectWillChange.send() manually so mutations go
    // in-place through the stored property's _modify accessor (O(1), no COW copy).
    // Views still react normally; ObservableObject only needs objectWillChange fired.
    // Starts empty: real incidents arrive from the remote store. (Seed data lives in
    // the DEBUG-only preview helper below so it never ships to users.)
    private(set) var incidents: [Incident] = []

    /// Set when a remote write (report submission, signal) ultimately fails so the UI can surface it.
    @Published var lastSyncError: String?

    // O(1) lookup: id → stable index in the incidents array.
    // Local mutations keep indices stable; remote snapshots rebuild the lookup.
    private var lookup: [UUID: Int] = [:]
    private let remoteStore: SafetyIncidentRemoteStore?

    // The region currently being observed, so we only re-subscribe when the user
    // moves meaningfully or changes their radius (avoids listener thrash).
    private var observedCenter: CLLocationCoordinate2D?
    private var observedRadiusKm: Double?
    private let resubscribeDistanceMeters: CLLocationDistance = 500

    init(remoteStore: SafetyIncidentRemoteStore? = SafetyIncidentRemoteStore.makeIfConfigured()) {
        self.remoteStore = remoteStore
        rebuildLookup()
        refreshActiveIncidents()
    }

    /// Point the incident feed at the user's area. Call when location or the watch
    /// radius changes; it re-subscribes only when the change is significant.
    func updateObservedRegion(center: CLLocationCoordinate2D, radiusKm: Double) {
        guard let remoteStore, center.isValid else { return }

        if let observedCenter, let observedRadiusKm,
           observedRadiusKm == radiusKm,
           observedCenter.distance(to: center) < resubscribeDistanceMeters {
            return
        }
        observedCenter = center
        observedRadiusKm = radiusKm

        remoteStore.observeIncidents(near: center, radiusMeters: radiusKm * 1_000) { [weak self] remoteIncidents in
            Task { @MainActor in
                self?.replaceIncidents(remoteIncidents)
            }
        }
    }

    private(set) var activeIncidents: [Incident] = []

    private func refreshActiveIncidents() {
        activeIncidents = incidents
            .filter { $0.status != .resolved }
            .sorted { $0.reportedAt > $1.reportedAt }
    }

    func addIncident(
        title: String,
        summary: String,
        category: IncidentCategory,
        subtype: IncidentSubtype,
        severity: IncidentSeverity,
        neighborhood: String,
        reporterCoordinate: CLLocationCoordinate2D?,
        useApproximateLocation: Bool = true,
        status: IncidentStatus = .active,
        evidenceUpdates: [String] = [],
        evidenceAttachments: [IncidentEvidenceAttachment] = []
    ) {
        // No location shared → store nil rather than fabricating a pin at the
        // default center. The incident still appears in the feed, just without a map pin.
        let publicCoordinate: CLLocationCoordinate2D?
        if let exact = reporterCoordinate {
            publicCoordinate = useApproximateLocation ? Self.publicCoordinate(from: exact) : exact
        } else {
            publicCoordinate = nil
        }

        let incident = Incident(
            id: UUID(),
            title: title,
            summary: summary,
            category: category,
            subtype: subtype.category == category ? subtype : IncidentSubtype.defaultSubtype(for: category),
            severity: severity,
            status: status,
            reporterCoordinate: reporterCoordinate,
            coordinate: publicCoordinate,
            neighborhood: neighborhood.isEmpty ? "Nearby area" : neighborhood,
            reportedAt: Date(),
            confirmations: 1,
            updates: [
                IncidentUpdate(message: "Immediate nearby alert sent as an unconfirmed community report.", timestamp: Date())
            ] + evidenceUpdates.map { IncidentUpdate(message: $0, timestamp: Date()) }
        )
        // Append (O(1) amortised) keeps all existing indices stable in the lookup.
        objectWillChange.send()
        lookup[incident.id] = incidents.count
        incidents.append(incident)
        refreshActiveIncidents()

        if let remoteStore {
            let clientRef = UUID().uuidString
            let submittedTitle = incident.title
            let submittedSummary = incident.summary
            let submittedCategory = incident.category
            let submittedSubtype = incident.subtype
            let submittedSeverity = incident.severity
            let submittedNeighborhood = incident.neighborhood
            let submittedCoordinate = incident.reporterCoordinate
            Task { [weak self] in
                // Evidence upload is best-effort; the report itself must not be lost silently.
                let uploadedEvidence = try? await remoteStore.uploadIncidentEvidence(
                    evidenceAttachments,
                    clientRef: clientRef
                )
                do {
                    _ = try await Self.retrying {
                        try await remoteStore.submitIncident(
                            title: submittedTitle,
                            summary: submittedSummary,
                            category: submittedCategory,
                            subtype: submittedSubtype,
                            severity: submittedSeverity,
                            status: status,
                            neighborhood: submittedNeighborhood,
                            reporterCoordinate: submittedCoordinate,
                            useApproximateLocation: useApproximateLocation,
                            clientRef: clientRef,
                            evidence: uploadedEvidence ?? []
                        )
                    }
                    self?.lastSyncError = nil
                } catch {
                    self?.lastSyncError = "We couldn't upload your report. Check your connection and try again."
                }
            }
        }
    }

    private static func publicCoordinate(from exactCoordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let minimumMeters = 140.0
        let maximumMeters = 260.0
        let distance = Double.random(in: minimumMeters...maximumMeters)
        let bearing = Double.random(in: 0..<(2 * .pi))
        let latitudeMeters = 111_320.0
        let longitudeMeters = max(cos(exactCoordinate.latitude * .pi / 180) * latitudeMeters, 1)

        return CLLocationCoordinate2D(
            latitude: exactCoordinate.latitude + (cos(bearing) * distance / latitudeMeters),
            longitude: exactCoordinate.longitude + (sin(bearing) * distance / longitudeMeters)
        )
    }

    func nearbyIncidents(
        urgentAlerts: Bool,
        communityAlerts: Bool,
        watchRadius: Double,
        near coordinate: CLLocationCoordinate2D?
    ) -> [Incident] {
        activeIncidents.filter { incident in
            let isUrgentAlert = IncidentCategory.urgentTypes.contains(incident.category) || incident.isHighRisk
            let isCommunityNotice = !isUrgentAlert && IncidentCategory.communityTypes.contains(incident.category)
            if isUrgentAlert && !urgentAlerts { return false }
            if isCommunityNotice && !communityAlerts { return false }
            guard let userCoord = coordinate else { return true }
            // A locationless incident can't be matched to a radius — exclude it
            // from distance-filtered "nearby" alerts.
            guard let incidentCoord = incident.coordinate else { return false }
            return userCoord.distance(to: incidentCoord) <= watchRadius * 1_000
        }
    }

    func incident(withID id: Incident.ID) -> Incident? {
        lookup[id].map { incidents[$0] }
    }

    func confirm(_ incident: Incident) {
        record(.seen, for: incident)
    }

    func record(_ signal: CommunitySignal, for incident: Incident) {
        guard let index = lookup[incident.id] else { return }
        guard incidents[index].status != .resolved else { return }
        objectWillChange.send()
        switch signal {
        case .seen:
            incidents[index].confirmations += 1
        case .notSeen:
            incidents[index].disputes += 1
            if incidents[index].status == .active, incidents[index].disputes >= incidents[index].confirmations {
                incidents[index].status = .watching
            }
        case .unsafe:
            incidents[index].unsafeReports += 1
            incidents[index].status = .active
            if incidents[index].severity != .urgent {
                incidents[index].severity = .high
            }
        case .roadBlocked:
            incidents[index].blockedReports += 1
            if incidents[index].category == .traffic || incidents[index].severity == .low {
                incidents[index].severity = .medium
            }
        case .cleared:
            incidents[index].clearedReports += 1
            if incidents[index].clearedReports >= 3 {
                incidents[index].status = .resolved
            } else {
                incidents[index].status = .watching
            }
        }

        incidents[index].updates.insert(
            IncidentUpdate(message: signal.updateMessage, timestamp: Date()),
            at: 0
        )
        refreshActiveIncidents()

        if let remoteStore {
            let incidentID  = incident.id
            let newStatus   = incidents[index].status
            let newSeverity = incidents[index].severity
            Task { [weak self] in
                do {
                    try await Self.retrying {
                        try await remoteStore.recordSignal(
                            signal,
                            forIncidentWithID: incidentID,
                            newStatus: newStatus,
                            newSeverity: newSeverity
                        )
                    }
                    self?.lastSyncError = nil
                } catch {
                    self?.lastSyncError = "We couldn't sync that update. Check your connection and try again."
                }
            }
        }
    }

    func markResolved(_ incident: Incident) {
        guard let index = lookup[incident.id] else { return }
        objectWillChange.send()
        incidents[index].status = .resolved
        incidents[index].updates.insert(
            IncidentUpdate(message: "Marked resolved by the community.", timestamp: Date()),
            at: 0
        )
        refreshActiveIncidents()
    }

    private func replaceIncidents(_ remoteIncidents: [Incident]) {
        objectWillChange.send()
        incidents = remoteIncidents
        rebuildLookup()
        refreshActiveIncidents()
    }

    private func rebuildLookup() {
        lookup.removeAll(keepingCapacity: true)
        for (i, incident) in incidents.enumerated() {
            lookup[incident.id] = i
        }
    }

    /// Retries a remote operation with linear backoff before giving up.
    private static func retrying<T>(
        attempts: Int = 3,
        _ operation: () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        for attempt in 0..<attempts {
            do {
                return try await operation()
            } catch {
                lastError = error
                if attempt < attempts - 1 {
                    try? await Task.sleep(for: .seconds(Double(attempt + 1) * 2))
                }
            }
        }
        throw lastError ?? CancellationError()
    }
}

#if DEBUG
extension IncidentStore {
    /// In-memory store populated with sample incidents, for SwiftUI previews only.
    static var preview: IncidentStore {
        let store = IncidentStore(remoteStore: nil)
        store.replaceIncidents(Incident.seedIncidents)
        return store
    }
}
#endif

#if DEBUG
extension Incident {
    /// Sample incidents for SwiftUI previews only — never shipped in release builds.
    static let seedIncidents: [Incident] = [
        Incident(
            id: UUID(),
            title: "Robbery reported near fuel station",
            summary: "People nearby report armed suspects moving away from the station. Avoid the frontage road while details are confirmed.",
            category: .security,
            subtype: .armedRobbery,
            severity: .urgent,
            status: .active,
            reporterCoordinate: CLLocationCoordinate2D(latitude: 6.5232, longitude: 3.3781),
            coordinate: CLLocationCoordinate2D(latitude: 6.5244, longitude: 3.3792),
            neighborhood: "Lagos Island",
            reportedAt: Date().addingTimeInterval(-4 * 60),
            confirmations: 37,
            updates: [
                IncidentUpdate(message: "Security patrol is moving toward the area.", timestamp: Date().addingTimeInterval(-2 * 60)),
                IncidentUpdate(message: "Multiple residents flagged the same block.", timestamp: Date().addingTimeInterval(-3 * 60))
            ]
        ),
        Incident(
            id: UUID(),
            title: "Smoke spotted behind warehouse",
            summary: "Small smoke plume visible from the service road. People nearby are keeping distance.",
            category: .fire,
            subtype: .buildingFire,
            severity: .urgent,
            status: .active,
            reporterCoordinate: CLLocationCoordinate2D(latitude: 6.5312, longitude: 3.3874),
            coordinate: CLLocationCoordinate2D(latitude: 6.5322, longitude: 3.3881),
            neighborhood: "Marina",
            reportedAt: Date().addingTimeInterval(-9 * 60),
            confirmations: 18,
            updates: [
                IncidentUpdate(message: "Emergency services have been notified.", timestamp: Date().addingTimeInterval(-3 * 60))
            ]
        ),
        Incident(
            id: UUID(),
            title: "Heavy traffic near bridge approach",
            summary: "Vehicles are moving slowly after a minor collision. Drivers are using the right lane only.",
            category: .traffic,
            subtype: .crash,
            severity: .medium,
            status: .active,
            reporterCoordinate: CLLocationCoordinate2D(latitude: 6.5049, longitude: 3.3889),
            coordinate: CLLocationCoordinate2D(latitude: 6.5058, longitude: 3.3895),
            neighborhood: "Lagos Mainland",
            reportedAt: Date().addingTimeInterval(-18 * 60),
            confirmations: 24,
            updates: [
                IncidentUpdate(message: "Traffic officers are directing vehicles.", timestamp: Date().addingTimeInterval(-6 * 60)),
                IncidentUpdate(message: "Right lane remains open.", timestamp: Date().addingTimeInterval(-12 * 60))
            ]
        ),
        Incident(
            id: UUID(),
            title: "Power outage affecting several streets",
            summary: "Residents around the market area report a sudden outage. No restoration estimate yet.",
            category: .utilities,
            subtype: .powerOutage,
            severity: .low,
            status: .watching,
            reporterCoordinate: CLLocationCoordinate2D(latitude: 6.5409, longitude: 3.3645),
            coordinate: CLLocationCoordinate2D(latitude: 6.5418, longitude: 3.3652),
            neighborhood: "Yaba",
            reportedAt: Date().addingTimeInterval(-46 * 60),
            confirmations: 11,
            updates: [
                IncidentUpdate(message: "Two more streets confirmed affected.", timestamp: Date().addingTimeInterval(-20 * 60))
            ]
        ),
        Incident(
            id: UUID(),
            title: "Community cleanup gathering",
            summary: "Volunteers are meeting near the school gate to clear blocked drainage before the rain.",
            category: .community,
            subtype: .publicGathering,
            severity: .low,
            status: .active,
            reporterCoordinate: CLLocationCoordinate2D(latitude: 6.4688, longitude: 3.5843),
            coordinate: CLLocationCoordinate2D(latitude: 6.4698, longitude: 3.5852),
            neighborhood: "Lekki",
            reportedAt: Date().addingTimeInterval(-90 * 60),
            confirmations: 31,
            updates: [
                IncidentUpdate(message: "Bags and gloves are available at the gate.", timestamp: Date().addingTimeInterval(-60 * 60))
            ]
        )
    ]
}
#endif
