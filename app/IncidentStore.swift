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
    @Published private(set) var pendingOutboxCount: Int = 0

    // O(1) lookup: id → stable index in the incidents array.
    // Local mutations keep indices stable; remote snapshots rebuild the lookup.
    private var lookup: [UUID: Int] = [:]
    private let remoteStore: SafetyIncidentRemoteStore?
    private let hiddenIncidentIDsKey = "hiddenIncidentIDs"
    private var hiddenIncidentIDs: Set<UUID>

    // The region currently being observed, so we only re-subscribe when the user
    // moves meaningfully or changes their radius (avoids listener thrash).
    private var observedCenter: CLLocationCoordinate2D?
    private var observedRadiusKm: Double?
    private let resubscribeDistanceMeters: CLLocationDistance = 500
    private let outbox: OutboxQueue
    private var isDrainingOutbox = false

    init(
        remoteStore: SafetyIncidentRemoteStore? = SafetyIncidentRemoteStore.makeIfConfigured(),
        outbox: OutboxQueue? = nil
    ) {
        self.remoteStore = remoteStore
        // Production uses the durable shared outbox; under XCTest each store gets an
        // isolated, throwaway outbox so tests don't share persistent state.
        self.outbox = outbox ?? IncidentStore.defaultOutbox()
        hiddenIncidentIDs = Set(
            UserDefaults.standard
                .stringArray(forKey: hiddenIncidentIDsKey)?
                .compactMap(UUID.init(uuidString:)) ?? []
        )
        rebuildLookup()
        refreshActiveIncidents()
        retryPendingOutbox()
    }

    /// True when running under XCTest. Used to keep unit tests hermetic: no live
    /// network store, an isolated outbox, and no background drain Tasks (which would
    /// otherwise pile up on the MainActor and starve other @MainActor tests).
    static var isUnderTest: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private static func defaultOutbox() -> OutboxQueue {
        // In-memory (no disk I/O) under XCTest so per-store construction never blocks the
        // MainActor; durable shared singleton otherwise.
        if isUnderTest {
            return OutboxQueue(inMemory: true)
        }
        return .shared
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

        // Opt-in complement: seed quickly from the scalable H3 callable while the live
        // listener spins up. The listener stays the source of truth; this only adds
        // incidents it hasn't delivered yet and never removes any.
        if UserDefaults.standard.bool(forKey: AppStorageKey.useH3FeedCallable) {
            seedFromH3Callable(center: center, radiusKm: radiusKm)
        }
    }

    private func seedFromH3Callable(center: CLLocationCoordinate2D, radiusKm: Double) {
        guard let remoteStore else { return }
        Task { [weak self] in
            guard let seeded = try? await remoteStore.queryIncidentsH3(near: center, radiusMeters: radiusKm * 1_000),
                  !seeded.isEmpty else { return }
            await MainActor.run { self?.mergeSeededIncidents(seeded) }
        }
    }

    /// Additively merges callable-seeded incidents: only those the live listener has not
    /// already provided, so the listener remains authoritative for the observed region.
    private func mergeSeededIncidents(_ seeded: [Incident]) {
        var didChange = false
        for incident in seeded where lookup[incident.id] == nil {
            lookup[incident.id] = incidents.count
            incidents.append(incident)
            didChange = true
        }
        guard didChange else { return }
        objectWillChange.send()
        refreshActiveIncidents()
    }

    private(set) var activeIncidents: [Incident] = []

    private func refreshActiveIncidents() {
        activeIncidents = incidents
            .filter { $0.status != .resolved && hiddenIncidentIDs.contains($0.id) == false }
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
        let incident = Incident(
            id: UUID(),
            remoteDocumentID: nil,
            title: title,
            summary: summary,
            category: category,
            subtype: subtype.category == category ? subtype : IncidentSubtype.defaultSubtype(for: category),
            severity: severity,
            status: status,
            reporterCoordinate: reporterCoordinate,
            coordinate: nil,
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

        let clientRef = UUID().uuidString
        enqueueIncidentOperation(.incidentReport(IncidentReportOutboxPayload(
            localIncidentID: incident.id,
            clientRef: clientRef,
            title: incident.title,
            summary: incident.summary,
            category: incident.category.rawValue,
            subtype: incident.subtype.rawValue,
            severity: incident.severity.rawValue,
            status: status.rawValue,
            neighborhood: incident.neighborhood,
            reporterCoordinate: incident.reporterCoordinate.map(CodableCoordinate.init),
            useApproximateLocation: useApproximateLocation,
            evidenceAttachments: evidenceAttachments.map(IncidentEvidenceOutboxPayload.init)
        )))
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
        guard let nextState = incidents[index].contractState(after: signal) else { return }
        objectWillChange.send()
        incidents[index].apply(nextState)
        incidents[index].updates.insert(
            IncidentUpdate(message: signal.updateMessage, timestamp: Date()),
            at: 0
        )
        refreshActiveIncidents()

        if signal == .cleared {
            hideIncident(incidents[index])
        }

        enqueueIncidentOperation(.incidentSignal(IncidentSignalOutboxPayload(
            localIncidentID: incident.id,
            remoteIncidentID: incident.remoteDocumentID,
            signal: signal.rawValue
        )))
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

    func recordConcern(_ reason: IncidentConcernReason, for incident: Incident) {
        hideIncident(incident)

        enqueueIncidentOperation(.incidentConcern(IncidentConcernOutboxPayload(
            localIncidentID: incident.id,
            remoteIncidentID: incident.remoteDocumentID,
            reason: reason.rawValue
        )))
    }

    func hideIncident(_ incident: Incident) {
        objectWillChange.send()
        hiddenIncidentIDs.insert(incident.id)
        UserDefaults.standard.set(hiddenIncidentIDs.map(\.uuidString), forKey: hiddenIncidentIDsKey)
        refreshActiveIncidents()
    }

    private func replaceIncidents(_ remoteIncidents: [Incident]) {
        objectWillChange.send()
        incidents = remoteIncidents
        rebuildLookup()
        refreshActiveIncidents()
    }

    private func attachRemoteDocumentID(_ remoteID: String, toIncidentWithID id: UUID) {
        guard let index = lookup[id] else { return }
        incidents[index].remoteDocumentID = remoteID
    }

    func retryPendingOutbox() {
        guard !IncidentStore.isUnderTest else { return }
        Task { [weak self] in
            await self?.drainIncidentOutbox(force: true)
        }
    }

    private func enqueueIncidentOperation(_ payload: OutboxPayload) {
        // Under XCTest the local incident state is already updated synchronously by the
        // caller; skip the durable-outbox background Task so it can't starve the MainActor.
        guard !IncidentStore.isUnderTest else { return }
        let kind: OutboxOperationKind
        switch payload {
        case .incidentReport:
            kind = .incidentReport
        case .incidentSignal:
            kind = .incidentSignal
        case .incidentConcern:
            kind = .incidentConcern
        default:
            return
        }

        Task { [weak self] in
            await self?.outbox.enqueue(OutboxOperation(kind: kind, payload: payload))
            await self?.refreshOutboxCount()
            await self?.drainIncidentOutbox(force: true)
        }
    }

    private func refreshOutboxCount() async {
        pendingOutboxCount = await outbox.pendingCount(for: [.incidentReport, .incidentSignal, .incidentConcern])
    }

    private func drainIncidentOutbox(force: Bool) async {
        guard !isDrainingOutbox else { return }
        guard let remoteStore else {
            await refreshOutboxCount()
            lastSyncError = "Your updates are saved locally until Firebase is configured."
            return
        }

        isDrainingOutbox = true
        defer { isDrainingOutbox = false }

        let dueOperations = await outbox.dueOperations(
            for: [.incidentReport, .incidentSignal, .incidentConcern],
            now: force ? .distantFuture : .now
        )

        for operation in dueOperations {
            await outbox.markProcessing(operation.id)
            do {
                try await processIncidentOutboxOperation(operation, remoteStore: remoteStore)
                await outbox.remove(operation.id)
                lastSyncError = nil
            } catch {
                await outbox.retryLater(operation.id, error: error)
                lastSyncError = message(for: operation.kind)
            }
        }

        await refreshOutboxCount()
    }

    private func processIncidentOutboxOperation(
        _ operation: OutboxOperation,
        remoteStore: SafetyIncidentRemoteStore
    ) async throws {
        switch operation.payload {
        case .incidentReport(let payload):
            guard
                let category = IncidentCategory(rawValue: payload.category),
                let subtype = IncidentSubtype(rawValue: payload.subtype),
                let severity = IncidentSeverity(rawValue: payload.severity),
                let status = IncidentStatus(rawValue: payload.status)
            else {
                throw IncidentOutboxError.invalidPayload
            }

            let uploadedEvidence = try await remoteStore.uploadIncidentEvidence(
                payload.evidenceAttachments.map(\.attachment),
                clientRef: payload.clientRef
            )
            let remoteID = try await remoteStore.submitIncident(
                title: payload.title,
                summary: payload.summary,
                category: category,
                subtype: subtype,
                severity: severity,
                status: status,
                neighborhood: payload.neighborhood,
                reporterCoordinate: payload.reporterCoordinate?.clLocationCoordinate,
                useApproximateLocation: payload.useApproximateLocation,
                clientRef: payload.clientRef,
                evidence: uploadedEvidence
            )
            attachRemoteDocumentID(remoteID, toIncidentWithID: payload.localIncidentID)

        case .incidentSignal(let payload):
            guard
                let signal = CommunitySignal(rawValue: payload.signal),
                let incidentID = remoteIncidentID(from: payload.localIncidentID, explicitID: payload.remoteIncidentID)
            else {
                throw IncidentOutboxError.missingRemoteIncidentID
            }
            try await remoteStore.recordSignal(signal, forIncidentWithID: incidentID)

        case .incidentConcern(let payload):
            guard
                let reason = IncidentConcernReason(rawValue: payload.reason),
                let incidentID = remoteIncidentID(from: payload.localIncidentID, explicitID: payload.remoteIncidentID)
            else {
                throw IncidentOutboxError.missingRemoteIncidentID
            }
            try await remoteStore.recordConcern(reason, forIncidentWithID: incidentID)

        default:
            break
        }
    }

    private func remoteIncidentID(from localID: UUID?, explicitID: String?) -> String? {
        if let explicitID, !explicitID.isEmpty { return explicitID }
        guard let localID else { return nil }
        return incident(withID: localID)?.remoteDocumentID
    }

    private func message(for kind: OutboxOperationKind) -> String {
        switch kind {
        case .incidentReport:
            "We couldn't upload your report yet. It is saved and will retry."
        case .incidentSignal:
            "We couldn't sync that update yet. It is saved and will retry."
        case .incidentConcern:
            "We hid this report, but the review request is waiting to retry."
        default:
            "An update is waiting to retry."
        }
    }

    private func rebuildLookup() {
        lookup.removeAll(keepingCapacity: true)
        for (i, incident) in incidents.enumerated() {
            lookup[incident.id] = i
        }
    }

}

private enum IncidentOutboxError: Error {
    case invalidPayload
    case missingRemoteIncidentID
}

private extension IncidentEvidenceOutboxPayload {
    init(_ attachment: IncidentEvidenceAttachment) {
        self.kind = attachment.kind.rawValue
        self.data = attachment.data
        self.filename = attachment.filename
        self.contentType = attachment.contentType
        self.durationSeconds = attachment.durationSeconds
    }

    var attachment: IncidentEvidenceAttachment {
        IncidentEvidenceAttachment(
            kind: IncidentEvidenceKind(rawValue: kind) ?? .photo,
            filename: filename,
            contentType: contentType,
            data: data,
            durationSeconds: durationSeconds
        )
    }
}

private extension Incident {
    func contractState(after signal: CommunitySignal) -> ContractDTO.IncidentState? {
        guard
            let status = ContractDTO.IncidentStatus(rawValue: status.rawValue),
            let severity = ContractDTO.IncidentSeverity(rawValue: severity.rawValue),
            let contractSignal = ContractDTO.CommunitySignal(rawValue: signal.rawValue)
        else {
            return nil
        }

        let state = ContractDTO.IncidentState(
            blockedReports: blockedReports,
            clearedReports: clearedReports,
            confirmations: confirmations,
            disputes: disputes,
            severity: severity,
            status: status,
            unsafeReports: unsafeReports
        )
        return ContractDTO.applySignal(state, signal: contractSignal)
    }

    mutating func apply(_ state: ContractDTO.IncidentState) {
        blockedReports = state.blockedReports
        clearedReports = state.clearedReports
        confirmations = state.confirmations
        disputes = state.disputes
        unsafeReports = state.unsafeReports
        severity = IncidentSeverity(rawValue: state.severity.rawValue) ?? severity
        status = IncidentStatus(rawValue: state.status.rawValue) ?? status
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
            remoteDocumentID: nil,
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
            remoteDocumentID: nil,
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
            remoteDocumentID: nil,
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
            remoteDocumentID: nil,
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
            remoteDocumentID: nil,
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
