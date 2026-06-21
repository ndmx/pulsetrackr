import Foundation
import MapKit
import SwiftUI

extension CLLocationCoordinate2D {
    var isValid: Bool { CLLocationCoordinate2DIsValid(self) }
}

enum IncidentCategory: String, CaseIterable, Identifiable {
    case security
    case traffic
    case fire
    case medical
    case weather
    case utilities
    case structure
    case community

    var id: String { rawValue }

    var label: String {
        switch self {
        case .security: "Security"
        case .traffic: "Traffic"
        case .fire: "Fire / Explosion"
        case .medical: "Medical"
        case .weather: "Weather / Flood"
        case .utilities: "Utilities"
        case .structure: "Structural Hazard"
        case .community: "Community"
        }
    }

    var icon: String {
        switch self {
        case .security: "shield.lefthalf.filled"
        case .traffic: "car.2.fill"
        case .fire: "flame.fill"
        case .medical: "cross.case.fill"
        case .weather: "cloud.heavyrain.fill"
        case .utilities: "bolt.fill"
        case .structure: "building.2.crop.circle.fill"
        case .community: "person.3.fill"
        }
    }

    /// Muted identity tones (Calm Authority). These mark *category*, not urgency —
    /// severity carries the vivid alert color. Mid-luminance so they read on both
    /// light and dark surfaces. Note: fire and medical are now distinct.
    var color: Color {
        switch self {
        case .security: Color(light: 0xB23A3A, dark: 0xD06A6A)   // muted red
        case .traffic: Color(light: 0xB5701F, dark: 0xD79A4E)    // muted amber
        case .fire: Color(light: 0xC0532F, dark: 0xDD7A52)       // ember orange
        case .medical: Color(light: 0xA84368, dark: 0xCC6E92)    // rose
        case .weather: Color(light: 0x35718C, dark: 0x5E9FB8)    // muted teal
        case .utilities: Color(light: 0x9A7C1F, dark: 0xC2A647)  // muted gold
        case .structure: Color(light: 0x5B549E, dark: 0x8A83C8)  // muted indigo
        case .community: Color(light: 0x2F7A53, dark: 0x5CA77B)  // muted green
        }
    }
}

enum IncidentSubtype: String, CaseIterable, Identifiable {
    case armedRobbery = "armed_robbery"
    case kidnapping
    case gunshots
    case carjacking
    case oneChance = "one_chance"
    case suspiciousActivity = "suspicious_activity"
    case checkpointIssue = "checkpoint_issue"
    case communalClash = "communal_clash"

    case crash
    case roadblock
    case gridlock
    case floodedRoad = "flooded_road"
    case badRoad = "bad_road"
    case brokenDownVehicle = "broken_down_vehicle"

    case buildingFire = "building_fire"
    case marketFire = "market_fire"
    case gasLeak = "gas_leak"
    case explosion
    case electricalFire = "electrical_fire"
    case pipelineFire = "pipeline_fire"

    case medicalEmergency = "medical_emergency"
    case suspectedOutbreak = "suspected_outbreak"
    case hospitalIssue = "hospital_issue"
    case medicineShortage = "medicine_shortage"
    case contaminatedWater = "contaminated_water"
    case foodPoisoning = "food_poisoning"

    case flooding
    case heavyRain = "heavy_rain"
    case stormDamage = "storm_damage"
    case erosionLandslide = "erosion_landslide"
    case droughtWaterScarcity = "drought_water_scarcity"

    case powerOutage = "power_outage"
    case waterOutage = "water_outage"
    case fuelScarcity = "fuel_scarcity"
    case bridgeDamage = "bridge_damage"
    case railIssue = "rail_issue"

    case buildingCollapse = "building_collapse"
    case bridgeCollapse = "bridge_collapse"
    case roadCollapse = "road_collapse"
    case unsafeBuilding = "unsafe_building"
    case fallenPowerLine = "fallen_power_line"

    case missingPerson = "missing_person"
    case localWarning = "local_warning"
    case safeRoute = "safe_route"
    case communityWatch = "community_watch"
    case publicGathering = "public_gathering"
    case aidNeeded = "aid_needed"

    var id: String { rawValue }

    var category: IncidentCategory {
        switch self {
        case .armedRobbery, .kidnapping, .gunshots, .carjacking, .oneChance, .suspiciousActivity, .checkpointIssue, .communalClash:
            .security
        case .crash, .roadblock, .gridlock, .floodedRoad, .badRoad, .brokenDownVehicle:
            .traffic
        case .buildingFire, .marketFire, .gasLeak, .explosion, .electricalFire, .pipelineFire:
            .fire
        case .medicalEmergency, .suspectedOutbreak, .hospitalIssue, .medicineShortage, .contaminatedWater, .foodPoisoning:
            .medical
        case .flooding, .heavyRain, .stormDamage, .erosionLandslide, .droughtWaterScarcity:
            .weather
        case .powerOutage, .waterOutage, .fuelScarcity, .bridgeDamage, .railIssue:
            .utilities
        case .buildingCollapse, .bridgeCollapse, .roadCollapse, .unsafeBuilding, .fallenPowerLine:
            .structure
        case .missingPerson, .localWarning, .safeRoute, .communityWatch, .publicGathering, .aidNeeded:
            .community
        }
    }

    var label: String {
        switch self {
        case .armedRobbery: "Armed robbery"
        case .kidnapping: "Kidnapping"
        case .gunshots: "Gunshots"
        case .carjacking: "Carjacking"
        case .oneChance: "One-chance"
        case .suspiciousActivity: "Suspicious activity"
        case .checkpointIssue: "Checkpoint issue"
        case .communalClash: "Communal clash"
        case .crash: "Crash"
        case .roadblock: "Roadblock"
        case .gridlock: "Gridlock"
        case .floodedRoad: "Flooded road"
        case .badRoad: "Bad road"
        case .brokenDownVehicle: "Broken-down vehicle"
        case .buildingFire: "Building fire"
        case .marketFire: "Market fire"
        case .gasLeak: "Gas leak"
        case .explosion: "Explosion"
        case .electricalFire: "Electrical fire"
        case .pipelineFire: "Pipeline fire"
        case .medicalEmergency: "Medical emergency"
        case .suspectedOutbreak: "Suspected outbreak"
        case .hospitalIssue: "Hospital issue"
        case .medicineShortage: "Medicine shortage"
        case .contaminatedWater: "Contaminated water"
        case .foodPoisoning: "Food poisoning"
        case .flooding: "Flooding"
        case .heavyRain: "Heavy rain"
        case .stormDamage: "Storm damage"
        case .erosionLandslide: "Erosion / landslide"
        case .droughtWaterScarcity: "Drought / water scarcity"
        case .powerOutage: "Power outage"
        case .waterOutage: "Water outage"
        case .fuelScarcity: "Fuel scarcity"
        case .bridgeDamage: "Bridge damage"
        case .railIssue: "Rail issue"
        case .buildingCollapse: "Building collapse"
        case .bridgeCollapse: "Bridge collapse"
        case .roadCollapse: "Road collapse"
        case .unsafeBuilding: "Unsafe building"
        case .fallenPowerLine: "Fallen power line"
        case .missingPerson: "Missing person"
        case .localWarning: "Local warning"
        case .safeRoute: "Safe route"
        case .communityWatch: "Community watch"
        case .publicGathering: "Public gathering"
        case .aidNeeded: "Aid needed"
        }
    }

    var icon: String {
        switch self {
        case .armedRobbery: "figure.run"
        case .kidnapping: "person.fill.questionmark"
        case .gunshots: "firearm.fill"
        case .carjacking: "car.fill"
        case .oneChance: "bus.fill"
        case .suspiciousActivity: "eye.fill"
        case .checkpointIssue: "exclamationmark.shield.fill"
        case .communalClash: "person.3.sequence.fill"
        case .crash: "car.2.fill"
        case .roadblock: "road.lanes.curved.right"
        case .gridlock: "car.3.fill"
        case .floodedRoad: "water.waves"
        case .badRoad: "exclamationmark.triangle.fill"
        case .brokenDownVehicle: "wrench.and.screwdriver.fill"
        case .buildingFire: "house.lodge.fill"
        case .marketFire: "storefront.fill"
        case .gasLeak: "flame.fill"
        case .explosion: "burst.fill"
        case .electricalFire: "bolt.trianglebadge.exclamationmark.fill"
        case .pipelineFire: "pipe.and.drop.fill"
        case .medicalEmergency: "cross.case.fill"
        case .suspectedOutbreak: "microbe.fill"
        case .hospitalIssue: "cross.fill"
        case .medicineShortage: "pills.fill"
        case .contaminatedWater: "drop.triangle.fill"
        case .foodPoisoning: "fork.knife.circle.fill"
        case .flooding: "drop.triangle.fill"
        case .heavyRain: "cloud.heavyrain.fill"
        case .stormDamage: "wind"
        case .erosionLandslide: "mountain.2.fill"
        case .droughtWaterScarcity: "sun.max.trianglebadge.exclamationmark.fill"
        case .powerOutage: "bolt.slash.fill"
        case .waterOutage: "drop.slash.fill"
        case .fuelScarcity: "fuelpump.fill"
        case .bridgeDamage: "bridge.2.fill"
        case .railIssue: "tram.fill"
        case .buildingCollapse: "building.2.crop.circle.fill"
        case .bridgeCollapse: "exclamationmark.triangle.fill"
        case .roadCollapse: "road.lanes"
        case .unsafeBuilding: "building.columns.fill"
        case .fallenPowerLine: "bolt.horizontal.circle.fill"
        case .missingPerson: "person.crop.circle.badge.questionmark"
        case .localWarning: "megaphone.fill"
        case .safeRoute: "arrow.triangle.turn.up.right.diamond.fill"
        case .communityWatch: "person.3.fill"
        case .publicGathering: "person.3.sequence.fill"
        case .aidNeeded: "hands.sparkles.fill"
        }
    }

    var isAlwaysHighRisk: Bool {
        switch self {
        case .armedRobbery, .kidnapping, .gunshots, .carjacking, .communalClash, .buildingFire, .marketFire, .gasLeak, .explosion, .pipelineFire, .medicalEmergency, .suspectedOutbreak, .flooding, .buildingCollapse, .bridgeCollapse, .roadCollapse, .fallenPowerLine, .missingPerson:
            true
        default:
            false
        }
    }

    private static let subtypesByCategory: [IncidentCategory: [IncidentSubtype]] = {
        var map: [IncidentCategory: [IncidentSubtype]] = [:]
        for subtype in allCases { map[subtype.category, default: []].append(subtype) }
        return map
    }()

    static func subtypes(for category: IncidentCategory) -> [IncidentSubtype] {
        subtypesByCategory[category] ?? []
    }

    static func defaultSubtype(for category: IncidentCategory) -> IncidentSubtype {
        subtypes(for: category).first ?? .localWarning
    }
}

enum IncidentSeverity: String, CaseIterable, Identifiable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case urgent = "Urgent"

    var id: String { rawValue }
}

enum IncidentStatus: String, CaseIterable, Identifiable {
    case active = "Active"
    case watching = "Watching"
    case resolved = "Resolved"

    var id: String { rawValue }
}

enum IncidentConfidence: String, Identifiable {
    case unconfirmed = "Unconfirmed report"
    case multipleReports = "Multiple reports"
    case communityVerified = "Verified by community"
    case officialUpdate = "Official update"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .unconfirmed: "exclamationmark.triangle.fill"
        case .multipleReports: "person.2.wave.2.fill"
        case .communityVerified: "checkmark.seal.fill"
        case .officialUpdate: "building.columns.fill"
        }
    }

    var color: Color {
        switch self {
        case .unconfirmed: .yellow
        case .multipleReports: .orange
        case .communityVerified: .green
        case .officialUpdate: .blue
        }
    }
}

enum CommunitySignal: String, CaseIterable, Identifiable {
    case seen
    case notSeen
    case unsafe
    case roadBlocked
    case cleared

    var id: String { rawValue }

    var label: String {
        switch self {
        case .seen: "I see this"
        case .notSeen: "I don't see it"
        case .unsafe: "Area unsafe"
        case .roadBlocked: "Road blocked"
        case .cleared: "Cleared"
        }
    }

    var icon: String {
        switch self {
        case .seen: "eye.fill"
        case .notSeen: "eye.slash.fill"
        case .unsafe: "exclamationmark.octagon.fill"
        case .roadBlocked: "road.lanes.curved.right"
        case .cleared: "checkmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .seen: .green
        case .notSeen: .gray
        case .unsafe: .red
        case .roadBlocked: .orange
        case .cleared: .mint
        }
    }

    var updateMessage: String {
        switch self {
        case .seen: "A nearby person reports they can see signs of this incident."
        case .notSeen: "A nearby person does not currently see signs of this incident."
        case .unsafe: "A nearby person marked the area unsafe. Avoid the area if possible."
        case .roadBlocked: "A nearby person reports the road is blocked."
        case .cleared: "A nearby person reports the area appears cleared."
        }
    }
}

enum IncidentConcernReason: String, CaseIterable, Identifiable {
    case falseReport = "false_report"
    case offensiveContent = "offensive_content"
    case privateInformation = "private_information"
    case dangerousAdvice = "dangerous_advice"
    case spamOrAbuse = "spam_or_abuse"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .falseReport: "False or misleading"
        case .offensiveContent: "Offensive content"
        case .privateInformation: "Shares private information"
        case .dangerousAdvice: "Dangerous advice"
        case .spamOrAbuse: "Spam or abuse"
        }
    }
}

struct Incident: Identifiable, Equatable {
    let id: UUID
    var remoteDocumentID: String? = nil
    var title: String
    var summary: String
    var category: IncidentCategory
    var subtype: IncidentSubtype
    var severity: IncidentSeverity
    var status: IncidentStatus
    var reporterCoordinate: CLLocationCoordinate2D?
    /// Public map location. `nil` until the backend reveals a k-anonymous H3 cell
    /// center, or when the incident has no location to show.
    var coordinate: CLLocationCoordinate2D?
    var neighborhood: String
    var reportedAt: Date
    var confirmations: Int
    var disputes: Int = 0
    var unsafeReports: Int = 0
    var blockedReports: Int = 0
    var clearedReports: Int = 0
    var officialUpdates: Int = 0
    var updates: [IncidentUpdate]

    static func == (lhs: Incident, rhs: Incident) -> Bool {
        lhs.id == rhs.id
    }

    var confidence: IncidentConfidence {
        if officialUpdates > 0 {
            return .officialUpdate
        }

        // Disputes must be a minority — a 50/50 split is not community-verified
        if confirmations >= 8 && disputes < confirmations {
            return .communityVerified
        }

        if confirmations >= 2 || unsafeReports > 0 || blockedReports > 0 {
            return .multipleReports
        }

        return .unconfirmed
    }

    var isHighRisk: Bool {
        severity == .urgent || severity == .high || subtype.isAlwaysHighRisk || unsafeReports > 0
    }

    var alertTone: String {
        if status == .resolved {
            return "No longer active"
        }

        if isHighRisk {
            return "Nearby alert sent"
        }

        return "Live local report"
    }

    var signalSummary: String {
        let parts = [
            "\(confirmations) seen",
            "\(disputes) not seen",
            "\(unsafeReports) unsafe",
            "\(clearedReports) cleared"
        ]

        return parts.joined(separator: " • ")
    }

    /// True when the incident has a usable public location to pin/route to.
    var hasLocation: Bool { coordinate?.isValid == true }

    /// The coordinate to route a Maps link to, falling back to the default center
    /// when no valid location is shared. Views should gate on `hasLocation` first.
    private var mapLinkCoordinate: CLLocationCoordinate2D {
        if let coordinate, coordinate.isValid { return coordinate }
        return .pulseDefaultCenter
    }

    // Validated once at load; a static literal that is guaranteed to parse.
    private static let googleMapsHomeURL = URL(string: "https://www.google.com/maps")!

    var googleMapsAreaURL: URL {
        let coord = mapLinkCoordinate
        return Self.googleMapsURL(path: "/maps/search/", queryItems: [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "query", value: "\(coord.latitude),\(coord.longitude)")
        ])
    }

    var googleMapsDirectionsURL: URL {
        let coord = mapLinkCoordinate
        return Self.googleMapsURL(path: "/maps/dir/", queryItems: [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "destination", value: "\(coord.latitude),\(coord.longitude)"),
            URLQueryItem(name: "travelmode", value: "driving")
        ])
    }

    private static func googleMapsURL(path: String, queryItems: [URLQueryItem]) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.google.com"
        components.path = path
        components.queryItems = queryItems
        return components.url ?? googleMapsHomeURL
    }
}

struct IncidentUpdate: Identifiable {
    let id = UUID()
    var message: String
    var timestamp: Date
}

extension CLLocationCoordinate2D {
    /// Default map center and fallback used when a precise location is unavailable (Lagos, Nigeria).
    static let pulseDefaultCenter = CLLocationCoordinate2D(latitude: 6.5244, longitude: 3.3792)

    func distance(to other: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: other.latitude, longitude: other.longitude))
    }

    /// True when the user's locale prefers imperial distances (US, UK, Liberia, Myanmar).
    private static var usesImperialDistance: Bool {
        Locale.current.measurementSystem != .metric
    }

    func formattedDistance(to other: CLLocationCoordinate2D) -> String {
        let m = distance(to: other)
        guard Self.usesImperialDistance else {
            if m < 100 { return "< 100 m away" }
            if m < 1_000 { return "\(Int((m / 50).rounded() * 50)) m away" }
            let km = m / 1_000
            return km < 10 ? String(format: "%.1f km away", km) : "\(Int(km.rounded())) km away"
        }
        let feet = m * 3.280_84
        let miles = m / 1_609.344
        if feet < 300 { return "< 300 ft away" }
        if miles < 0.1 { return "\(Int((feet / 50).rounded() * 50)) ft away" }
        return miles < 10 ? String(format: "%.1f mi away", miles) : "\(Int(miles.rounded())) mi away"
    }

    func shortFormattedDistance(to other: CLLocationCoordinate2D) -> String {
        let m = distance(to: other)
        guard Self.usesImperialDistance else {
            if m < 1_000 { return "\(Int(m.rounded()))m" }
            let km = m / 1_000
            return km < 10 ? String(format: "%.1fkm", km) : "\(Int(km.rounded()))km"
        }
        let feet = m * 3.280_84
        let miles = m / 1_609.344
        if miles < 0.1 { return "\(Int(feet.rounded()))ft" }
        return miles < 10 ? String(format: "%.1fmi", miles) : "\(Int(miles.rounded()))mi"
    }
}

extension IncidentCategory {
    static let urgentTypes: Set<IncidentCategory> = [.security, .fire, .medical]
    static let communityTypes: Set<IncidentCategory> = [.traffic, .utilities, .community, .weather, .structure]
}
