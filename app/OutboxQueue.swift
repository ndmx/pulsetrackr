import CoreLocation
import Foundation

enum OutboxOperationKind: String, Codable, CaseIterable {
    case incidentReport
    case incidentSignal
    case incidentConcern
    case sosActivate
    case sosLocationUpdate
    case sosResolve
}

enum OutboxOperationStatus: String, Codable {
    case queued
    case processing
    case failed
}

struct OutboxOperation: Identifiable, Codable {
    var id: UUID
    var kind: OutboxOperationKind
    var status: OutboxOperationStatus
    var createdAt: Date
    var updatedAt: Date
    var nextAttemptAt: Date
    var attemptCount: Int
    var lastError: String?
    var payload: OutboxPayload

    init(id: UUID = UUID(), kind: OutboxOperationKind, payload: OutboxPayload, createdAt: Date = .now) {
        self.id = id
        self.kind = kind
        self.status = .queued
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.nextAttemptAt = createdAt
        self.attemptCount = 0
        self.lastError = nil
        self.payload = payload
    }
}

enum OutboxPayload: Codable {
    case incidentReport(IncidentReportOutboxPayload)
    case incidentSignal(IncidentSignalOutboxPayload)
    case incidentConcern(IncidentConcernOutboxPayload)
    case sosActivate(SOSActivateOutboxPayload)
    case sosLocationUpdate(SOSLocationUpdateOutboxPayload)
    case sosResolve(SOSResolveOutboxPayload)
}

struct IncidentReportOutboxPayload: Codable {
    var localIncidentID: UUID
    var clientRef: String
    var title: String
    var summary: String
    var category: String
    var subtype: String
    var severity: String
    var status: String
    var neighborhood: String
    var reporterCoordinate: CodableCoordinate?
    var useApproximateLocation: Bool
    var evidenceAttachments: [IncidentEvidenceOutboxPayload]
}

struct IncidentEvidenceOutboxPayload: Codable {
    var kind: String
    var data: Data
    var filename: String
    var contentType: String
    var durationSeconds: Double?
}

struct IncidentSignalOutboxPayload: Codable {
    var localIncidentID: UUID?
    var remoteIncidentID: String?
    var signal: String
}

struct IncidentConcernOutboxPayload: Codable {
    var localIncidentID: UUID?
    var remoteIncidentID: String?
    var reason: String
}

struct SOSActivateOutboxPayload: Codable {
    var localSessionID: UUID
    var activatedAt: Date
    var lastKnownLocation: SOSLocationSnapshot
    var recentTrail: [SOSLocationSnapshot]
    var directionOfTravel: SOSDirectionOfTravel?
    var trustedContacts: [SOSTrustedContactNotificationTarget]
    var privacyPolicy: SOSPrivacyPolicy
}

struct SOSLocationUpdateOutboxPayload: Codable {
    var localEventID: UUID
    var localSessionID: UUID
    var remoteSessionID: String?
    var location: SOSLocationSnapshot
    var sequenceNumber: Int
    var directionOfTravel: SOSDirectionOfTravel?
}

struct SOSResolveOutboxPayload: Codable {
    var localEventID: UUID
    var localSessionID: UUID
    var remoteSessionID: String?
    var reason: SOSResolutionReason
    var finalLocation: SOSLocationSnapshot?
    var resolvedAt: Date
}

struct CodableCoordinate: Codable, Equatable {
    var latitude: Double
    var longitude: Double

    init(_ coordinate: CLLocationCoordinate2D) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }

    var clLocationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

actor OutboxQueue {
    static let shared = OutboxQueue()

    private var operations: [OutboxOperation] = []
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let persistsToDisk: Bool

    init(filename: String = "client-outbox.json", inMemory: Bool = false) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        if inMemory {
            // No disk persistence — used by unit tests so store construction never does
            // synchronous file I/O on the MainActor (which would starve parallel
            // @MainActor tests). Operations live only for the instance's lifetime.
            self.persistsToDisk = false
            self.fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            self.operations = []
            return
        }

        self.persistsToDisk = true
        let supportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = supportURL.appendingPathComponent("PulseTrackr", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent(filename)

        self.operations = (try? Data(contentsOf: fileURL))
            .flatMap { try? decoder.decode([OutboxOperation].self, from: $0) } ?? []
        recoverInterruptedOperations()
    }

    func enqueue(_ operation: OutboxOperation) async {
        operations.append(operation)
        persist()
    }

    func pendingCount(for kinds: Set<OutboxOperationKind>? = nil) async -> Int {
        operations.filter { operation in
            (kinds?.contains(operation.kind) ?? true) && operation.status != .processing
        }.count
    }

    func dueOperations(for kinds: Set<OutboxOperationKind>, now: Date = .now) async -> [OutboxOperation] {
        operations
            .filter { kinds.contains($0.kind) && $0.nextAttemptAt <= now && $0.status != .processing }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func markProcessing(_ id: UUID) async {
        update(id) { operation in
            operation.status = .processing
            operation.updatedAt = .now
        }
    }

    func remove(_ id: UUID) async {
        operations.removeAll { $0.id == id }
        persist()
    }

    func retryLater(_ id: UUID, error: Error, baseDelaySeconds: TimeInterval = 20) async {
        update(id) { operation in
            operation.status = .failed
            operation.attemptCount += 1
            operation.updatedAt = .now
            operation.lastError = String(describing: error)
            let delay = min(baseDelaySeconds * pow(2, Double(max(operation.attemptCount - 1, 0))), 15 * 60)
            operation.nextAttemptAt = Date().addingTimeInterval(delay)
        }
    }

    func replacePayload(_ id: UUID, payload: OutboxPayload) async {
        update(id) { operation in
            operation.payload = payload
            operation.status = .queued
            operation.updatedAt = .now
            operation.nextAttemptAt = .now
        }
    }

    private func update(_ id: UUID, mutate: (inout OutboxOperation) -> Void) {
        guard let index = operations.firstIndex(where: { $0.id == id }) else { return }
        mutate(&operations[index])
        persist()
    }

    private func recoverInterruptedOperations() {
        for index in operations.indices where operations[index].status == .processing {
            operations[index].status = .queued
            operations[index].updatedAt = .now
            operations[index].nextAttemptAt = .now
        }
        persist()
    }

    private func persist() {
        guard persistsToDisk else { return }
        do {
            let data = try encoder.encode(operations)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            assertionFailure("Unable to persist client outbox: \(error)")
        }
    }
}
