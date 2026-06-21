import CoreLocation
import Foundation

enum SOSSessionState: String, Codable, Identifiable {
    case active
    case stopping
    case stopped
    case cancelled

    var id: String { rawValue }
}

enum SOSQueueEventKind: String, Codable, Identifiable {
    case started
    case locationUpdated
    case stopped
    case cancelled

    var id: String { rawValue }
}

enum SOSQueueStatus: String, Codable, Identifiable {
    case queued
    case waitingForRemote
    case delivered
    case failed

    var id: String { rawValue }
}

enum SOSDeliveryState: String, Identifiable {
    case localOnly
    case ready
    case syncing
    case delivered
    case failed

    var id: String { rawValue }
}

struct SOSTrailPoint: Identifiable {
    let id: UUID
    var coordinate: CLLocationCoordinate2D
    var timestamp: Date
    var speed: CLLocationSpeed?
    var course: CLLocationDirection?
    var horizontalAccuracy: CLLocationAccuracy?

    init(location: CLLocation) {
        id = UUID()
        coordinate = location.coordinate
        timestamp = location.timestamp
        speed = location.speed >= 0 ? location.speed : nil
        course = location.course >= 0 ? location.course : nil
        horizontalAccuracy = location.horizontalAccuracy >= 0 ? location.horizontalAccuracy : nil
    }

    init(coordinate: CLLocationCoordinate2D, timestamp: Date = .now) {
        id = UUID()
        self.coordinate = coordinate
        self.timestamp = timestamp
        speed = nil
        course = nil
        horizontalAccuracy = nil
    }

    init(
        id: UUID,
        coordinate: CLLocationCoordinate2D,
        timestamp: Date,
        speed: CLLocationSpeed?,
        course: CLLocationDirection?,
        horizontalAccuracy: CLLocationAccuracy?
    ) {
        self.id = id
        self.coordinate = coordinate
        self.timestamp = timestamp
        self.speed = speed
        self.course = course
        self.horizontalAccuracy = horizontalAccuracy
    }
}

struct SOSSession: Identifiable {
    let id: UUID
    var startedAt: Date
    var endedAt: Date?
    var state: SOSSessionState

    var isActive: Bool {
        state == .active || state == .stopping
    }
}

struct SOSQueueEvent: Identifiable {
    let id: UUID
    var kind: SOSQueueEventKind
    var timestamp: Date
    var coordinate: CLLocationCoordinate2D?
    var sequenceNumber: Int?
    var status: SOSQueueStatus
    var attemptCount: Int
}

struct SOSMapTrailArtifact: Identifiable {
    var point: SOSTrailPoint
    var index: Int
    var total: Int

    var id: UUID { point.id }
    var coordinate: CLLocationCoordinate2D { point.coordinate }

    var prominence: Double {
        guard total > 1 else { return 1 }
        return 0.32 + (Double(index) / Double(total - 1)) * 0.68
    }

    var isNewest: Bool {
        index == total - 1
    }
}
