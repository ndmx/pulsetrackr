import CoreLocation
import Foundation

/// Pure weight math for the incident-density heatmap. No Mapbox dependency so it
/// compiles and unit-tests without the MapboxMaps SDK.
enum IncidentDensity {
    /// A single weighted map point produced from an eligible incident.
    struct Feature: Equatable {
        let coordinate: CLLocationCoordinate2D
        let weight: Double

        static func == (lhs: Feature, rhs: Feature) -> Bool {
            lhs.coordinate.latitude == rhs.coordinate.latitude
                && lhs.coordinate.longitude == rhs.coordinate.longitude
                && lhs.weight == rhs.weight
        }
    }

    /// Severity rank × recency decay, clamped to `[0.05, 1]`.
    static func weight(severity: IncidentSeverity, reportedAt: Date, now: Date) -> Double {
        let severityRank: Double
        switch severity {
        case .low: severityRank = 0.25
        case .medium: severityRank = 0.5
        case .high: severityRank = 0.8
        case .urgent: severityRank = 1.0
        }

        let ageHours = max(0, now.timeIntervalSince(reportedAt) / 3_600)
        let recency = exp(-ageHours / 6)
        let raw = severityRank * recency
        return min(1, max(0.05, raw))
    }

    /// Eligible incidents only: `hasLocation` and not resolved.
    static func features(from incidents: [Incident], now: Date) -> [Feature] {
        incidents.compactMap { incident in
            guard incident.hasLocation, incident.status != .resolved else { return nil }
            guard let coordinate = incident.coordinate else { return nil }
            return Feature(
                coordinate: coordinate,
                weight: weight(severity: incident.severity, reportedAt: incident.reportedAt, now: now)
            )
        }
    }
}
