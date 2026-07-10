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
    @Published private(set) var optedOutContactIDs: Set<UUID> = []
    @Published private(set) var lastRemoteError: String?
    @Published private(set) var lastUploadAttemptAt: Date?
    @Published private(set) var lastSuccessfulUploadAt: Date?
    @Published private(set) var appTrustedContactList: SOSAppTrustedContactList?
    @Published private(set) var appAlerts: [SOSAppAlert] = []

    private let maxTrailPoints = 80
    private let maxTrailAge: TimeInterval = 30 * 60
    private let minDistanceBetweenPoints: CLLocationDistance = 8
    private let contactStore: SOSTrustedContactStore
    private let privacyPolicy: SOSPrivacyPolicy
    private let remoteFactory: () -> SOSRemoteStore?
    private var remoteStore: SOSRemoteStore?
    private var appAlertObservation: SOSAppAlertObservation?
    private var isStartingAppAlertObservation = false
    private var isSyncingRemote = false
    private var isPollingNotificationStatus = false
    private var nextLocationSequenceNumber = 0
    private var queuedActivationSessionID: UUID?
    private let outbox = OutboxQueue.shared
    private let snapshotURL: URL
    private let snapshotEncoder = JSONEncoder()
    private let snapshotDecoder = JSONDecoder()

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
        let supportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = supportURL.appendingPathComponent("PulseTrackr", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        snapshotURL = directory.appendingPathComponent("sos-state.json")
        snapshotEncoder.dateEncodingStrategy = .iso8601
        snapshotDecoder.dateDecodingStrategy = .iso8601
        restoreSnapshot()
        loadTrustedContacts()
        replayQueuedEvents()
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

    var activeAppAlert: SOSAppAlert? {
        appAlerts.first { $0.status == "active" }
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

        let newSession = SOSSession(id: UUID(), startedAt: .now, endedAt: nil, state: .active)
        session = newSession
        remoteSessionID = nil
        alertedContactIDs = []
        optedOutContactIDs = []
        queuedEvents = []
        lastRemoteError = nil
        nextLocationSequenceNumber = 0
        deliveryState = activeTrustedContacts.isEmpty ? .localOnly : .syncing
        enqueue(.started, coordinate: location?.coordinate ?? lastKnownCoordinate, status: .waitingForRemote)
        guard let activationLocation = lastKnownPoint?.locationSnapshot else {
            lastRemoteError = "SOS is saved locally until your device has a current location."
            deliveryState = .localOnly
            persistSnapshot()
            return
        }
        enqueueSOSOperation(.sosActivate(SOSActivateOutboxPayload(
            localSessionID: newSession.id,
            activatedAt: newSession.startedAt,
            lastKnownLocation: activationLocation,
            recentTrail: trail.compactMap(\.locationSnapshot),
            directionOfTravel: latestDirectionOfTravel,
            trustedContacts: activeTrustedContacts.compactMap(\.notificationTarget),
            privacyPolicy: privacyPolicy
        )))
        queuedActivationSessionID = newSession.id
        persistSnapshot()
        syncRemote(force: true)
    }

    func stopSession() {
        guard var activeSession = session, activeSession.isActive else { return }
        activeSession.state = .stopping
        session = activeSession
        let event = enqueue(.stopped, coordinate: lastKnownCoordinate, status: .waitingForRemote)

        activeSession.state = .stopped
        activeSession.endedAt = .now
        session = activeSession
        enqueueSOSOperation(.sosResolve(SOSResolveOutboxPayload(
            localEventID: event.id,
            localSessionID: activeSession.id,
            remoteSessionID: remoteSessionID,
            reason: .userResolved,
            finalLocation: lastKnownPoint?.locationSnapshot,
            resolvedAt: activeSession.endedAt ?? .now
        )))
        persistSnapshot()
        syncRemote(force: true)
    }

    func cancelSession() {
        guard var activeSession = session else { return }
        activeSession.state = .cancelled
        activeSession.endedAt = .now
        session = activeSession
        let event = enqueue(.cancelled, coordinate: lastKnownCoordinate, status: .waitingForRemote)
        enqueueSOSOperation(.sosResolve(SOSResolveOutboxPayload(
            localEventID: event.id,
            localSessionID: activeSession.id,
            remoteSessionID: remoteSessionID,
            reason: .falseAlarm,
            finalLocation: lastKnownPoint?.locationSnapshot,
            resolvedAt: activeSession.endedAt ?? .now
        )))
        persistSnapshot()
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
            enqueueActivationIfNeeded()
            let event = enqueue(.locationUpdated, coordinate: point.coordinate, status: .queued)
            if let activeSession = session, let snapshot = point.locationSnapshot {
                enqueueSOSOperation(.sosLocationUpdate(SOSLocationUpdateOutboxPayload(
                    localEventID: event.id,
                    localSessionID: activeSession.id,
                    remoteSessionID: remoteSessionID,
                    location: snapshot,
                    sequenceNumber: event.sequenceNumber ?? 0,
                    directionOfTravel: latestDirectionOfTravel
                )))
            }
            if shouldAttemptLiveUpload(now: point.timestamp) {
                syncRemote(force: false)
            }
        }
        persistSnapshot()
    }

    func markQueuedEventsFailed() {
        queuedEvents = queuedEvents.map { event in
            var updated = event
            updated.status = .failed
            updated.attemptCount += 1
            return updated
        }
        persistSnapshot()
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

    func createAppTrustedContactInvite(ownerDisplayName: String) async throws -> SOSAppTrustedContactInvite {
        guard let remote = configuredRemoteStore() else {
            throw SOSStoreError.remoteUnavailable
        }
        return try await remote.createAppTrustedContactInvite(ownerDisplayName: ownerDisplayName)
    }

    func acceptAppTrustedContactInvite(
        inviteCode: String,
        trustedContactDisplayName: String
    ) async throws -> SOSAppTrustedContactRelationship {
        guard let remote = configuredRemoteStore() else {
            throw SOSStoreError.remoteUnavailable
        }
        let relationship = try await remote.acceptAppTrustedContactInvite(
            inviteCode: inviteCode,
            trustedContactDisplayName: trustedContactDisplayName
        )
        try? await refreshAppTrustedContacts()
        return relationship
    }

    func refreshAppTrustedContacts() async throws {
        guard let remote = configuredRemoteStore() else {
            throw SOSStoreError.remoteUnavailable
        }
        appTrustedContactList = try await remote.listAppTrustedContacts()
    }

    func startObservingAppAlerts() {
        guard appAlertObservation == nil, !isStartingAppAlertObservation else { return }
        isStartingAppAlertObservation = true

        Task {
            defer { isStartingAppAlertObservation = false }
            guard let remote = configuredRemoteStore() else { return }
            do {
                appAlertObservation = try await remote.observeAppSOSAlerts { [weak self] alerts in
                    Task { @MainActor in
                        self?.appAlerts = alerts
                    }
                }
            } catch {
                lastRemoteError = "Incoming app SOS alerts could not be started."
            }
        }
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
            try await drainSOSOutbox(remote: remote, force: force)
            lastSuccessfulUploadAt = .now
            deliveryState = .delivered
            if isActive, remoteSessionID != nil {
                startNotificationStatusReadback()
            }
        } catch {
            lastRemoteError = uploadErrorMessage(for: error)
            markEvents(unsentEvents.map(\.id), status: .failed, incrementAttempt: true)
            deliveryState = .failed
        }

        isSyncingRemote = false
        persistSnapshot()
    }

    private func uploadErrorMessage(for error: Error) -> String {
        switch error {
        case SOSStoreError.noTrustedContactDelivery:
            return smsOptOutNotice ?? "SOS saved, but no trusted contact was reached. Check the SMS/email provider setup and try again."
        case SOSStoreError.missingRemoteSession:
            return "SOS is saved, but one queued update is missing its server link. PulseTrackr will reconnect it before sending."
        case SOSStoreError.missingLocation:
            return "SOS is saved locally until your device has a current location."
        case SOSStoreError.remoteUnavailable:
            return "Emergency route is saved locally until Firebase SOS delivery is configured."
        default:
            break
        }
        if let remote = error as? SOSRemoteCallError {
            #if DEBUG
            return "\(remote.userMessage)\n\(remote.diagnosticMessage)"
            #else
            return remote.userMessage
            #endif
        }
        #if DEBUG
        let nsError = error as NSError
        return "Emergency updates could not upload. Keep moving if safe; PulseTrackr will retry.\n\(nsError.domain) #\(nsError.code): \(nsError.localizedDescription)"
        #else
        return "Emergency updates could not upload. Keep moving if safe; PulseTrackr will retry."
        #endif
    }

    /// Backend trusted-contact delivery runs in an async Cloud Task, so the activation
    /// response comes back before SMS/email are actually sent. Poll the owner-scoped
    /// status endpoint a few times so the SOS panel reflects real "alerted"/"opted out"
    /// status instead of staying on "ready".
    private func startNotificationStatusReadback() {
        guard !isPollingNotificationStatus, let remote = configuredRemoteStore() else { return }
        isPollingNotificationStatus = true

        Task { [weak self] in
            defer { self?.isPollingNotificationStatus = false }
            let delaysSeconds: [UInt64] = [2, 4, 8, 12]
            for delay in delaysSeconds {
                try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
                guard let self, let sessionID = self.remoteSessionID, self.isActive else { return }
                guard let status = try? await remote.fetchNotificationStatus(sessionID: sessionID) else { continue }
                if self.applyNotificationStatus(status) { return }
            }
        }
    }

    /// Returns true once the backend notification saga has settled (so polling can stop).
    @discardableResult
    private func applyNotificationStatus(_ status: SOSNotificationStatus) -> Bool {
        optedOutContactIDs.formUnion(status.trustedContactsOptedOut)
        if !status.trustedContactsNotified.isEmpty {
            alertedContactIDs.formUnion(status.trustedContactsNotified)
            do {
                try contactStore.markNotified(contactIDs: status.trustedContactsNotified)
            } catch {
                trustedContactError = "Your contacts were alerted, but we couldn't update their status on this device."
            }
            loadTrustedContacts()
        }
        if let notice = smsOptOutNotice {
            lastRemoteError = notice
        } else if status.notificationSummary.sent > 0 || !status.trustedContactsNotified.isEmpty || !status.appTrustedContactsNotified.isEmpty {
            lastRemoteError = nil
            deliveryState = .delivered
        }
        persistSnapshot()
        return status.isSettled
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
        optedOutContactIDs = Set(response.trustedContactsOptedOut)
        if let smsOptOutNotice {
            lastRemoteError = smsOptOutNotice
        }
        if !activeTrustedContacts.isEmpty && response.notificationSummary.sent == 0 && response.notificationSummary.queued == 0 {
            throw SOSStoreError.noTrustedContactDelivery
        }
        if !response.trustedContactsNotified.isEmpty {
            // Contacts were alerted remotely; failing to persist that locally must not
            // fail the SOS activation, but it shouldn't vanish silently either.
            do {
                try contactStore.markNotified(contactIDs: response.trustedContactsNotified)
            } catch {
                trustedContactError = "Your contacts were alerted, but we couldn't update their status on this device."
            }
            loadTrustedContacts()
        }
        markEvents(ofKind: .started, status: .delivered)
    }

    private var smsOptOutNotice: String? {
        let optedOutNames = activeTrustedContacts
            .filter { optedOutContactIDs.contains($0.id) }
            .map(\.displayName)
        guard !optedOutNames.isEmpty else { return nil }

        if optedOutNames.count == 1, let name = optedOutNames.first {
            return "\(name) opted out of receiving your SOS SMS alerts. They can reply START to receive texts again."
        }

        let names = optedOutNames.prefix(3).joined(separator: ", ")
        let suffix = optedOutNames.count > 3 ? " and \(optedOutNames.count - 3) more" : ""
        return "\(names)\(suffix) opted out of receiving your SOS SMS alerts. They can reply START to receive texts again."
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
        persistSnapshot()
    }

    private func markEvents(ofKind kind: SOSQueueEventKind, status: SOSQueueStatus) {
        for index in queuedEvents.indices where queuedEvents[index].kind == kind {
            queuedEvents[index].status = status
        }
        persistSnapshot()
    }

    @discardableResult
    private func enqueue(
        _ kind: SOSQueueEventKind,
        coordinate: CLLocationCoordinate2D?,
        status: SOSQueueStatus
    ) -> SOSQueueEvent {
        let event = SOSQueueEvent(
            id: UUID(),
            kind: kind,
            timestamp: .now,
            coordinate: coordinate,
            sequenceNumber: nextSequenceNumber(for: kind),
            status: status,
            attemptCount: 0
        )
        queuedEvents.append(event)

        if queuedEvents.count > maxTrailPoints {
            queuedEvents.removeFirst(queuedEvents.count - maxTrailPoints)
        }
        persistSnapshot()
        return event
    }

    private func nextSequenceNumber(for kind: SOSQueueEventKind) -> Int? {
        guard kind == .locationUpdated else { return nil }
        defer { nextLocationSequenceNumber += 1 }
        return nextLocationSequenceNumber
    }

    private func enqueueSOSOperation(_ payload: OutboxPayload) {
        let kind: OutboxOperationKind
        switch payload {
        case .sosActivate:
            kind = .sosActivate
        case .sosLocationUpdate:
            kind = .sosLocationUpdate
        case .sosResolve:
            kind = .sosResolve
        default:
            return
        }

        Task { [weak self] in
            guard let self else { return }
            await outbox.enqueue(OutboxOperation(kind: kind, payload: payload))
            await MainActor.run {
                self.syncRemote(force: true)
            }
        }
    }

    private func enqueueActivationIfNeeded() {
        guard remoteSessionID == nil, let activeSession = session, let activationLocation = lastKnownPoint?.locationSnapshot else { return }
        guard queuedActivationSessionID != activeSession.id else { return }
        enqueueSOSOperation(.sosActivate(SOSActivateOutboxPayload(
            localSessionID: activeSession.id,
            activatedAt: activeSession.startedAt,
            lastKnownLocation: activationLocation,
            recentTrail: trail.compactMap(\.locationSnapshot),
            directionOfTravel: latestDirectionOfTravel,
            trustedContacts: activeTrustedContacts.compactMap(\.notificationTarget),
            privacyPolicy: privacyPolicy
        )))
        queuedActivationSessionID = activeSession.id
    }

    private func replayQueuedEvents() {
        guard !queuedEvents.isEmpty || session != nil else { return }
        syncRemote(force: true)
    }

    private func drainSOSOutbox(remote: SOSRemoteStore, force: Bool) async throws {
        let operations = await outbox.dueOperations(
            for: [.sosActivate, .sosLocationUpdate, .sosResolve],
            now: force ? .distantFuture : .now
        ).sorted(by: sosOutboxProcessingOrder)

        for operation in operations {
            await outbox.markProcessing(operation.id)
            do {
                try await processSOSOutboxOperation(operation, remote: remote)
                await outbox.remove(operation.id)
            } catch {
                if isTerminalSOSOutboxError(error, for: operation) {
                    markLocalEventDelivered(for: operation)
                    await outbox.remove(operation.id)
                    continue
                }
                await outbox.retryLater(operation.id, error: error, baseDelaySeconds: 10)
                throw error
            }
        }
    }

    private func sosOutboxProcessingOrder(_ lhs: OutboxOperation, _ rhs: OutboxOperation) -> Bool {
        let leftPriority = sosOutboxPriority(lhs.kind)
        let rightPriority = sosOutboxPriority(rhs.kind)
        if leftPriority != rightPriority {
            return leftPriority < rightPriority
        }
        return lhs.createdAt < rhs.createdAt
    }

    private func sosOutboxPriority(_ kind: OutboxOperationKind) -> Int {
        switch kind {
        case .sosActivate:
            return 0
        case .sosLocationUpdate:
            return 1
        case .sosResolve:
            return 2
        default:
            return 3
        }
    }

    private func processSOSOutboxOperation(_ operation: OutboxOperation, remote: SOSRemoteStore) async throws {
        switch operation.payload {
        case .sosActivate(let payload):
            guard payload.localSessionID == session?.id else {
                return
            }
            guard remoteSessionID == nil else {
                markEvents(ofKind: .started, status: .delivered)
                return
            }
            let response = try await remote.activateSOS(payload: SOSActivationPayload(
                clientSessionID: payload.localSessionID,
                activatedAt: payload.activatedAt,
                lastKnownLocation: payload.lastKnownLocation,
                recentTrail: payload.recentTrail,
                directionOfTravel: payload.directionOfTravel,
                trustedContactsToNotify: payload.trustedContacts,
                privacyPolicy: payload.privacyPolicy
            ))
            remoteSessionID = response.sessionID
            alertedContactIDs = Set(response.trustedContactsNotified)
            optedOutContactIDs = Set(response.trustedContactsOptedOut)
            if let smsOptOutNotice {
                lastRemoteError = smsOptOutNotice
            }
            if !activeTrustedContacts.isEmpty && response.notificationSummary.sent == 0 && response.notificationSummary.queued == 0 {
                throw SOSStoreError.noTrustedContactDelivery
            }
            if !response.trustedContactsNotified.isEmpty {
                do {
                    try contactStore.markNotified(contactIDs: response.trustedContactsNotified)
                } catch {
                    trustedContactError = "Your contacts were alerted, but we couldn't update their status on this device."
                }
                loadTrustedContacts()
            }
            markEvents(ofKind: .started, status: .delivered)

        case .sosLocationUpdate(let payload):
            guard payload.localSessionID == session?.id else {
                markEvents([payload.localEventID], status: .delivered)
                return
            }
            guard let sessionID = remoteSessionID ?? payload.remoteSessionID else {
                throw SOSStoreError.missingRemoteSession
            }
            try await remote.appendSOSLocation(
                sessionID: sessionID,
                update: SOSLocationUpdatePayload(
                    location: payload.location,
                    sequenceNumber: payload.sequenceNumber,
                    directionOfTravel: payload.directionOfTravel
                )
            )
            markEvents([payload.localEventID], status: .delivered)

        case .sosResolve(let payload):
            guard payload.localSessionID == session?.id else {
                markEvents([payload.localEventID], status: .delivered)
                return
            }
            guard let sessionID = remoteSessionID ?? payload.remoteSessionID else {
                throw SOSStoreError.missingRemoteSession
            }
            try await remote.resolveSOS(
                sessionID: sessionID,
                resolution: payload.reason,
                finalLocation: payload.finalLocation,
                resolvedAt: payload.resolvedAt
            )
            markEvents([payload.localEventID], status: .delivered)

        default:
            break
        }
    }

    private func isTerminalSOSOutboxError(_ error: Error, for operation: OutboxOperation) -> Bool {
        guard case .sosLocationUpdate = operation.payload else {
            if case .sosResolve = operation.payload {
                return isClosedRemoteSessionError(error)
            }
            return false
        }
        return isClosedRemoteSessionError(error)
    }

    private func isClosedRemoteSessionError(_ error: Error) -> Bool {
        (error as? SOSRemoteCallError)?.isClosedSessionPrecondition == true
    }

    private func markLocalEventDelivered(for operation: OutboxOperation) {
        switch operation.payload {
        case .sosLocationUpdate(let payload):
            markEvents([payload.localEventID], status: .delivered)
        case .sosResolve(let payload):
            markEvents([payload.localEventID], status: .delivered)
        default:
            break
        }
    }

    private func restoreSnapshot() {
        guard
            let data = try? Data(contentsOf: snapshotURL),
            let snapshot = try? snapshotDecoder.decode(SOSStoreSnapshot.self, from: data)
        else {
            return
        }

        session = snapshot.session?.session
        trail = snapshot.trail.map(\.point)
        queuedEvents = snapshot.queuedEvents.map(\.event)
        lastKnownPoint = snapshot.lastKnownPoint?.point
        remoteSessionID = snapshot.remoteSessionID
        alertedContactIDs = Set(snapshot.alertedContactIDs)
        optedOutContactIDs = Set(snapshot.optedOutContactIDs)
        nextLocationSequenceNumber = snapshot.nextLocationSequenceNumber
        deliveryState = queuedEvents.contains { $0.status != .delivered } ? .failed : deliveryState
    }

    private func persistSnapshot() {
        let snapshot = SOSStoreSnapshot(
            session: session.map(StoredSOSSession.init),
            trail: trail.map(StoredSOSTrailPoint.init),
            queuedEvents: queuedEvents.map(StoredSOSQueueEvent.init),
            lastKnownPoint: lastKnownPoint.map(StoredSOSTrailPoint.init),
            remoteSessionID: remoteSessionID,
            alertedContactIDs: Array(alertedContactIDs),
            optedOutContactIDs: Array(optedOutContactIDs),
            nextLocationSequenceNumber: nextLocationSequenceNumber
        )
        do {
            let data = try snapshotEncoder.encode(snapshot)
            try data.write(to: snapshotURL, options: [.atomic])
        } catch {
            assertionFailure("Unable to persist SOS queue: \(error)")
        }
    }
}

enum SOSStoreError: Error {
    case missingLocation
    case missingRemoteSession
    case noTrustedContactDelivery
    case remoteUnavailable
}

private struct SOSStoreSnapshot: Codable {
    var session: StoredSOSSession?
    var trail: [StoredSOSTrailPoint]
    var queuedEvents: [StoredSOSQueueEvent]
    var lastKnownPoint: StoredSOSTrailPoint?
    var remoteSessionID: String?
    var alertedContactIDs: [UUID]
    var optedOutContactIDs: [UUID]
    var nextLocationSequenceNumber: Int
}

private struct StoredSOSSession: Codable {
    var id: UUID
    var startedAt: Date
    var endedAt: Date?
    var state: SOSSessionState

    init(_ session: SOSSession) {
        self.id = session.id
        self.startedAt = session.startedAt
        self.endedAt = session.endedAt
        self.state = session.state
    }

    var session: SOSSession {
        SOSSession(id: id, startedAt: startedAt, endedAt: endedAt, state: state)
    }
}

private struct StoredSOSTrailPoint: Codable {
    var id: UUID
    var coordinate: CodableCoordinate
    var timestamp: Date
    var speed: CLLocationSpeed?
    var course: CLLocationDirection?
    var horizontalAccuracy: CLLocationAccuracy?

    init(_ point: SOSTrailPoint) {
        self.id = point.id
        self.coordinate = CodableCoordinate(point.coordinate)
        self.timestamp = point.timestamp
        self.speed = point.speed
        self.course = point.course
        self.horizontalAccuracy = point.horizontalAccuracy
    }

    var point: SOSTrailPoint {
        SOSTrailPoint(
            id: id,
            coordinate: coordinate.clLocationCoordinate,
            timestamp: timestamp,
            speed: speed,
            course: course,
            horizontalAccuracy: horizontalAccuracy
        )
    }
}

private struct StoredSOSQueueEvent: Codable {
    var id: UUID
    var kind: SOSQueueEventKind
    var timestamp: Date
    var coordinate: CodableCoordinate?
    var sequenceNumber: Int?
    var status: SOSQueueStatus
    var attemptCount: Int

    init(_ event: SOSQueueEvent) {
        self.id = event.id
        self.kind = event.kind
        self.timestamp = event.timestamp
        self.coordinate = event.coordinate.map(CodableCoordinate.init)
        self.sequenceNumber = event.sequenceNumber
        self.status = event.status
        self.attemptCount = event.attemptCount
    }

    var event: SOSQueueEvent {
        SOSQueueEvent(
            id: id,
            kind: kind,
            timestamp: timestamp,
            coordinate: coordinate?.clLocationCoordinate,
            sequenceNumber: sequenceNumber,
            status: status,
            attemptCount: attemptCount
        )
    }
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
