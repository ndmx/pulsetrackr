import CoreLocation
import FirebaseAuth
import FirebaseCore
import FirebaseFunctions
import Foundation
#if canImport(Network)
import Network
#endif
#if canImport(UIKit)
import UIKit
#endif

final class SOSRemoteStore {
    private let functions: Functions

    static func makeIfConfigured() -> SOSRemoteStore? {
        guard FirebaseBootstrap.configureIfAvailable() else { return nil }
        return SOSRemoteStore()
    }

    private init(functions: Functions = Functions.functions()) {
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

    private func ensureSignedIn() async throws {
        if Auth.auth().currentUser != nil { return }
        try await Auth.auth().signInAnonymously()
    }

    private func callFunction(named name: String, data: [String: Any]) async throws -> HTTPSCallableResult {
        try await functions.httpsCallable(name).call(data)
    }
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

    init(
        clientSessionID: UUID = UUID(),
        activatedAt: Date = Date(),
        lastKnownLocation: SOSLocationSnapshot,
        recentTrail: [SOSLocationSnapshot] = [],
        directionOfTravel: SOSDirectionOfTravel? = nil,
        trustedContactsToNotify: [SOSTrustedContactNotificationTarget] = [],
        deviceMetadata: SOSDeviceMetadata = .current(),
        privacyPolicy: SOSPrivacyPolicy = .default,
        source: String = "ios"
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
    }

    var functionPayload: [String: Any] {
        [
            "client_session_id": clientSessionID.uuidString,
            "activated_at": SOSPayloadCoding.string(from: activatedAt),
            "source": source,
            "last_known_location": lastKnownLocation.functionPayload,
            "recent_trail": privacyScopedTrail.map(\.functionPayload),
            "direction_of_travel": resolvedDirectionOfTravel?.functionPayload as Any,
            "trusted_contacts_to_notify": trustedContactsToNotify.map(\.functionPayload),
            "device": deviceMetadata.functionPayload,
            "privacy": privacyPolicy.functionPayload
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
            "privacy": privacyPolicy.functionPayload
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
        [
            "location": location.functionPayload,
            "sequence_number": sequenceNumber,
            "captured_at": SOSPayloadCoding.string(from: location.capturedAt),
            "direction_of_travel": directionOfTravel?.functionPayload as Any,
            "device": deviceMetadata.functionPayload
        ].compactingNilValuesForSOS
    }
}

struct SOSResolutionPayload: Equatable {
    var sessionID: String
    var reason: SOSResolutionReason
    var finalLocation: SOSLocationSnapshot?
    var resolvedAt: Date

    var functionPayload: [String: Any] {
        [
            "session_id": sessionID,
            "resolution_reason": reason.rawValue,
            "resolved_at": SOSPayloadCoding.string(from: resolvedAt),
            "final_location": finalLocation?.functionPayload as Any
        ].compactingNilValuesForSOS
    }
}

enum SOSResolutionReason: String, Codable, CaseIterable, Equatable {
    case userResolved = "user_resolved"
    case falseAlarm = "false_alarm"
    case timedOut = "timed_out"
    case transferredToCareTeam = "transferred_to_care_team"
}

struct SOSActivationResponse {
    var sessionID: String
    var trustedContactsNotified: [UUID]
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
        self.expiresAt = SOSPayloadCoding.date(from: body["expires_at"])
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
