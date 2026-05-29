import CoreLocation
import Foundation

@MainActor
final class SOSStore: ObservableObject {
    @Published private(set) var session: SOSSession?
    @Published private(set) var trail: [SOSTrailPoint] = []
    @Published private(set) var queuedEvents: [SOSQueueEvent] = []
    @Published private(set) var lastKnownPoint: SOSTrailPoint?
    @Published private(set) var trustedContacts: [SOSTrustedContact] = []
    @Published private(set) var trustedContactError: String?
    @Published private(set) var deliveryState: SOSDeliveryState = .ready
    @Published private(set) var remoteSessionID: String?
    @Published private(set) var alertedContactIDs: Set<UUID> = []
    @Published private(set) var lastRemoteError: String?
    @Published private(set) var lastUploadAttemptAt: Date?
    @Published private(set) var lastSuccessfulUploadAt: Date?

    private let maxTrailPoints = 80
    private let maxTrailAge: TimeInterval = 30 * 60
    private let minDistanceBetweenPoints: CLLocationDistance = 8
    private let contactStore: SOSTrustedContactStore
    private let privacyPolicy: SOSPrivacyPolicy
    private let remoteFactory: () -> SOSRemoteStore?
    private var remoteStore: SOSRemoteStore?
    private var isSyncingRemote = false
    private var nextLocationSequenceNumber = 0

    init(
        contactStore: SOSTrustedContactStore = SOSTrustedContactStore(),
        privacyPolicy: SOSPrivacyPolicy = .default,
        remoteStore: SOSRemoteStore? = nil,
        remoteFactory: @escaping () -> SOSRemoteStore? = SOSRemoteStore.makeIfConfigured
    ) {
        self.contactStore = contactStore
        self.privacyPolicy = privacyPolicy
        self.remoteStore = remoteStore
        self.remoteFactory = remoteFactory
        loadTrustedContacts()
    }

    var isActive: Bool {
        session?.isActive == true
    }

    var pendingRemoteEventCount: Int {
        queuedEvents.filter { $0.status == .queued || $0.status == .waitingForRemote }.count
    }

    var failedRemoteEventCount: Int {
        queuedEvents.filter { $0.status == .failed }.count
    }

    var activeTrustedContacts: [SOSTrustedContact] {
        trustedContacts.filter(\.isDeliverable)
    }

    var alertedContacts: [SOSTrustedContact] {
        trustedContacts.filter { alertedContactIDs.contains($0.id) }
    }

    var uploadStatusText: String {
        switch deliveryState {
        case .localOnly:
            return "Saved on this device"
        case .ready:
            return activeTrustedContacts.isEmpty ? "Add trusted contacts" : "Ready to alert"
        case .syncing:
            return "Sending emergency updates"
        case .delivered:
            if let lastSuccessfulUploadAt {
                return "Last uploaded \(lastSuccessfulUploadAt.formatted(date: .omitted, time: .shortened))"
            }
            return "Emergency record uploaded"
        case .failed:
            return "Updates waiting to retry"
        }
    }

    var latestDirectionOfTravel: SOSDirectionOfTravel? {
        SOSDirectionOfTravel(recentTrail: trail.compactMap(\.locationSnapshot))
    }

    var trailArtifacts: [SOSMapTrailArtifact] {
        let visiblePoints = Array(trail.suffix(18))
        return visiblePoints.enumerated().map { index, point in
            SOSMapTrailArtifact(point: point, index: index, total: visiblePoints.count)
        }
    }

    var lastKnownCoordinate: CLLocationCoordinate2D? {
        lastKnownPoint?.coordinate
    }

    func startSession(from location: CLLocation?) {
        if let location {
            record(location: location, force: true)
        }

        session = SOSSession(id: UUID(), startedAt: .now, endedAt: nil, state: .active)
        remoteSessionID = nil
        alertedContactIDs = []
        queuedEvents = []
        lastRemoteError = nil
        nextLocationSequenceNumber = 0
        deliveryState = activeTrustedContacts.isEmpty ? .localOnly : .syncing
        enqueue(.started, coordinate: location?.coordinate ?? lastKnownCoordinate, status: .waitingForRemote)
        syncRemote(force: true)
    }

    func stopSession() {
        guard var activeSession = session, activeSession.isActive else { return }
        activeSession.state = .stopping
        session = activeSession
        enqueue(.stopped, coordinate: lastKnownCoordinate, status: .waitingForRemote)

        activeSession.state = .stopped
        activeSession.endedAt = .now
        session = activeSession
        syncRemote(force: true)
    }

    func cancelSession() {
        guard var activeSession = session else { return }
        activeSession.state = .cancelled
        activeSession.endedAt = .now
        session = activeSession
        enqueue(.cancelled, coordinate: lastKnownCoordinate, status: .waitingForRemote)
        syncRemote(force: true)
    }

    func record(location: CLLocation, force: Bool = false) {
        let point = SOSTrailPoint(location: location)
        lastKnownPoint = point

        guard force || shouldAppend(point) else {
            trimTrail(now: point.timestamp)
            return
        }

        trail.append(point)
        trimTrail(now: point.timestamp)

        if isActive {
            enqueue(.locationUpdated, coordinate: point.coordinate, status: .queued)
            if shouldAttemptLiveUpload(now: point.timestamp) {
                syncRemote(force: false)
            }
        }
    }

    func markQueuedEventsFailed() {
        queuedEvents = queuedEvents.map { event in
            var updated = event
            updated.status = .failed
            updated.attemptCount += 1
            return updated
        }
    }

    func retryQueuedEvents() {
        syncRemote(force: true)
    }

    func loadTrustedContacts() {
        do {
            trustedContacts = try contactStore.loadContacts()
                .sorted { $0.createdAt < $1.createdAt }
            trustedContactError = nil
        } catch {
            trustedContactError = "Trusted contacts could not be loaded."
        }
    }

    func saveTrustedContact(_ contact: SOSTrustedContact) {
        do {
            try contactStore.upsert(contact)
            loadTrustedContacts()
        } catch {
            trustedContactError = "Trusted contact could not be saved."
        }
    }

    func deleteTrustedContact(withID id: UUID) {
        do {
            try contactStore.deleteContact(withID: id)
            loadTrustedContacts()
        } catch {
            trustedContactError = "Trusted contact could not be removed."
        }
    }

    func toggleTrustedContact(_ contact: SOSTrustedContact) {
        var updated = contact
        updated.isActive.toggle()
        saveTrustedContact(updated)
    }

    private func shouldAppend(_ point: SOSTrailPoint) -> Bool {
        guard let previous = trail.last else { return true }

        let previousLocation = CLLocation(
            latitude: previous.coordinate.latitude,
            longitude: previous.coordinate.longitude
        )
        let nextLocation = CLLocation(
            latitude: point.coordinate.latitude,
            longitude: point.coordinate.longitude
        )

        return nextLocation.distance(from: previousLocation) >= minDistanceBetweenPoints
            || point.timestamp.timeIntervalSince(previous.timestamp) >= 60
    }

    private func trimTrail(now: Date) {
        let oldestAllowed = now.addingTimeInterval(-maxTrailAge)
        trail.removeAll { $0.timestamp < oldestAllowed }

        if trail.count > maxTrailPoints {
            trail.removeFirst(trail.count - maxTrailPoints)
        }

        if queuedEvents.count > maxTrailPoints {
            queuedEvents.removeFirst(queuedEvents.count - maxTrailPoints)
        }
    }

    private func syncRemote(force: Bool) {
        guard !isSyncingRemote else { return }

        Task {
            await syncRemoteNow(force: force)
        }
    }

    private func syncRemoteNow(force: Bool) async {
        guard let activeSession = session else { return }

        let unsentEvents = queuedEvents.filter { event in
            event.status == .waitingForRemote || event.status == .queued || (force && event.status == .failed)
        }
        guard force || !unsentEvents.isEmpty else { return }

        guard let remote = configuredRemoteStore() else {
            deliveryState = .localOnly
            lastRemoteError = "Emergency route is saved locally until Firebase SOS delivery is configured."
            return
        }

        isSyncingRemote = true
        deliveryState = .syncing
        lastUploadAttemptAt = .now
        lastRemoteError = nil
        markEvents(unsentEvents.map(\.id), status: .waitingForRemote)

        do {
            if remoteSessionID == nil {
                try await activateRemoteSession(remote: remote, session: activeSession)
            }

            if let remoteSessionID {
                try await uploadLocationEvents(remote: remote, sessionID: remoteSessionID, force: force)
                try await resolveRemoteIfNeeded(remote: remote, sessionID: remoteSessionID)
            }

            lastSuccessfulUploadAt = .now
            deliveryState = .delivered
        } catch {
            lastRemoteError = "Emergency updates could not upload. Keep moving if safe; PulseTrackr will retry."
            markEvents(unsentEvents.map(\.id), status: .failed, incrementAttempt: true)
            deliveryState = .failed
        }

        isSyncingRemote = false
    }

    private func configuredRemoteStore() -> SOSRemoteStore? {
        if let remoteStore {
            return remoteStore
        }

        remoteStore = remoteFactory()
        return remoteStore
    }

    private func activateRemoteSession(remote: SOSRemoteStore, session: SOSSession) async throws {
        guard let lastKnownLocation = lastKnownPoint?.locationSnapshot else {
            throw SOSStoreError.missingLocation
        }

        let payload = SOSActivationPayload(
            clientSessionID: session.id,
            activatedAt: session.startedAt,
            lastKnownLocation: lastKnownLocation,
            recentTrail: trail.compactMap(\.locationSnapshot),
            directionOfTravel: latestDirectionOfTravel,
            trustedContactsToNotify: activeTrustedContacts.compactMap(\.notificationTarget),
            privacyPolicy: privacyPolicy
        )
        let response = try await remote.activateSOS(payload: payload)
        remoteSessionID = response.sessionID
        alertedContactIDs = Set(response.trustedContactsNotified)
        if !response.trustedContactsNotified.isEmpty {
            try? contactStore.markNotified(contactIDs: response.trustedContactsNotified)
            loadTrustedContacts()
        }
        markEvents(ofKind: .started, status: .delivered)
    }

    private func uploadLocationEvents(remote: SOSRemoteStore, sessionID: String, force: Bool) async throws {
        let locationEvents = queuedEvents.filter { event in
            event.kind == .locationUpdated &&
                (event.status == .queued || event.status == .waitingForRemote || (force && event.status == .failed))
        }

        for event in locationEvents {
            guard let snapshot = event.locationSnapshot else { continue }
            let payload = SOSLocationUpdatePayload(
                location: snapshot,
                sequenceNumber: event.sequenceNumber ?? 0,
                directionOfTravel: latestDirectionOfTravel
            )
            try await remote.appendSOSLocation(sessionID: sessionID, update: payload)
            markEvents([event.id], status: .delivered)
        }
    }

    private func resolveRemoteIfNeeded(remote: SOSRemoteStore, sessionID: String) async throws {
        guard let state = session?.state, state == .stopped || state == .cancelled else { return }

        let reason: SOSResolutionReason = state == .cancelled ? .falseAlarm : .userResolved
        try await remote.resolveSOS(
            sessionID: sessionID,
            resolution: reason,
            finalLocation: lastKnownPoint?.locationSnapshot
        )
        markEvents(ofKind: state == .cancelled ? .cancelled : .stopped, status: .delivered)
    }

    private func shouldAttemptLiveUpload(now: Date) -> Bool {
        guard isActive else { return false }
        guard activeTrustedContacts.isEmpty == false else { return false }
        guard lastUploadAttemptAt.map({ now.timeIntervalSince($0) }) ?? .infinity >= privacyPolicy.liveLocationUpdateIntervalSeconds else {
            return false
        }
        return true
    }

    private func markEvents(
        _ ids: [UUID],
        status: SOSQueueStatus,
        incrementAttempt: Bool = false
    ) {
        guard !ids.isEmpty else { return }
        let idSet = Set(ids)
        for index in queuedEvents.indices where idSet.contains(queuedEvents[index].id) {
            queuedEvents[index].status = status
            if incrementAttempt {
                queuedEvents[index].attemptCount += 1
            }
        }
    }

    private func markEvents(ofKind kind: SOSQueueEventKind, status: SOSQueueStatus) {
        for index in queuedEvents.indices where queuedEvents[index].kind == kind {
            queuedEvents[index].status = status
        }
    }

    private func enqueue(
        _ kind: SOSQueueEventKind,
        coordinate: CLLocationCoordinate2D?,
        status: SOSQueueStatus
    ) {
        queuedEvents.append(
            SOSQueueEvent(
                id: UUID(),
                kind: kind,
                timestamp: .now,
                coordinate: coordinate,
                sequenceNumber: nextSequenceNumber(for: kind),
                status: status,
                attemptCount: 0
            )
        )

        if queuedEvents.count > maxTrailPoints {
            queuedEvents.removeFirst(queuedEvents.count - maxTrailPoints)
        }
    }

    private func nextSequenceNumber(for kind: SOSQueueEventKind) -> Int? {
        guard kind == .locationUpdated else { return nil }
        defer { nextLocationSequenceNumber += 1 }
        return nextLocationSequenceNumber
    }
}

enum SOSStoreError: Error {
    case missingLocation
}

private extension SOSTrailPoint {
    var locationSnapshot: SOSLocationSnapshot? {
        SOSLocationSnapshot(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            horizontalAccuracyMeters: horizontalAccuracy,
            speedMetersPerSecond: speed,
            courseDegrees: course,
            capturedAt: timestamp
        )
    }
}

private extension SOSQueueEvent {
    var locationSnapshot: SOSLocationSnapshot? {
        guard let coordinate else { return nil }
        return SOSLocationSnapshot(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            capturedAt: timestamp
        )
    }
}
