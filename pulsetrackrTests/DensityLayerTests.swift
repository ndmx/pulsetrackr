import CoreLocation
import Foundation
import Testing
@testable import pulsetrackr

@Suite("IncidentDensity")
struct DensityLayerTests {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - weight()

    @Test func urgentNowIsOne() {
        let w = IncidentDensity.weight(severity: .urgent, reportedAt: now, now: now)
        #expect(abs(w - 1.0) < 0.000_1)
    }

    @Test func lowNowIsQuarter() {
        let w = IncidentDensity.weight(severity: .low, reportedAt: now, now: now)
        #expect(abs(w - 0.25) < 0.000_1)
    }

    @Test func urgentAtSixHoursDecaysByE() {
        let reportedAt = now.addingTimeInterval(-6 * 3_600)
        let w = IncidentDensity.weight(severity: .urgent, reportedAt: reportedAt, now: now)
        let expected = exp(-1.0) // ~0.367879
        #expect(abs(w - expected) < 0.01)
    }

    @Test func veryOldClampsToFloor() {
        let reportedAt = now.addingTimeInterval(-100 * 3_600)
        let w = IncidentDensity.weight(severity: .urgent, reportedAt: reportedAt, now: now)
        #expect(abs(w - 0.05) < 0.000_1)
    }

    // MARK: - features()

    @Test func excludesResolvedAndLocationless() {
        let withLocation = makeIncident(severity: .high, status: .active, coordinate: .lagos, reportedAt: now)
        let resolved = makeIncident(severity: .urgent, status: .resolved, coordinate: .lagos, reportedAt: now)
        let locationless = makeIncident(severity: .medium, status: .active, coordinate: nil, reportedAt: now)

        let features = IncidentDensity.features(from: [withLocation, resolved, locationless], now: now)
        #expect(features.count == 1)
        #expect(abs(features[0].weight - 0.8) < 0.000_1)
    }

    @Test func featureCountMatchesEligibleIncidents() {
        let incidents = [
            makeIncident(severity: .low, status: .active, coordinate: .lagos, reportedAt: now),
            makeIncident(severity: .medium, status: .watching, coordinate: .lagos, reportedAt: now),
            makeIncident(severity: .high, status: .resolved, coordinate: .lagos, reportedAt: now),
            makeIncident(severity: .urgent, status: .active, coordinate: nil, reportedAt: now),
            makeIncident(severity: .urgent, status: .active, coordinate: .abuja, reportedAt: now)
        ]
        let features = IncidentDensity.features(from: incidents, now: now)
        #expect(features.count == 3)
    }

    @Test func weightsStayWithinBounds() {
        let ages: [TimeInterval] = [0, 1, 6, 12, 48, 200].map { $0 * 3_600 }
        let severities: [IncidentSeverity] = [.low, .medium, .high, .urgent]
        for severity in severities {
            for age in ages {
                let w = IncidentDensity.weight(
                    severity: severity,
                    reportedAt: now.addingTimeInterval(-age),
                    now: now
                )
                #expect(w >= 0.05 && w <= 1.0)
            }
        }
    }
}

// MARK: - Helpers

private extension CLLocationCoordinate2D {
    static let lagos = CLLocationCoordinate2D(latitude: 6.5244, longitude: 3.3792)
    static let abuja = CLLocationCoordinate2D(latitude: 9.0765, longitude: 7.3986)
}

private func makeIncident(
    severity: IncidentSeverity,
    status: IncidentStatus,
    coordinate: CLLocationCoordinate2D?,
    reportedAt: Date
) -> Incident {
    Incident(
        id: UUID(),
        title: "Density test",
        summary: "Test incident for density math.",
        category: .security,
        subtype: .suspiciousActivity,
        severity: severity,
        status: status,
        reporterCoordinate: coordinate,
        coordinate: coordinate,
        neighborhood: "Test Area",
        reportedAt: reportedAt,
        confirmations: 1,
        updates: []
    )
}
