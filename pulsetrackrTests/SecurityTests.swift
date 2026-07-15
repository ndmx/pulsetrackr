//
//  SecurityTests.swift
//  pulsetrackrTests
//
//  Security-focused tests: HTTPS enforcement, coordinate privacy, URL safety,
//  and input sanitisation at system boundaries.
//

import Testing
import MapKit
@testable import pulsetrackr

@Suite("Security")
struct SecurityTests {

    // MARK: - HTTPS enforcement

    @Test func googleMapsAreaURLUsesHTTPS() {
        let incident = makeSecurityIncident()
        #expect(incident.googleMapsAreaURL.scheme == "https",
                "Area URL must use HTTPS, not HTTP")
    }

    @Test func googleMapsDirectionsURLUsesHTTPS() {
        let incident = makeSecurityIncident()
        #expect(incident.googleMapsDirectionsURL.scheme == "https",
                "Directions URL must use HTTPS, not HTTP")
    }

    @Test func fallbackURLAfterInvalidCoordinateUsesHTTPS() {
        let incident = Incident(
            id: UUID(), title: "T", summary: "S",
            category: .community, subtype: .localWarning,
            severity: .low, status: .active,
            reporterCoordinate: nil,
            coordinate: kCLLocationCoordinate2DInvalid,
            neighborhood: "Test", reportedAt: Date(),
            confirmations: 1, updates: []
        )
        #expect(incident.googleMapsAreaURL.scheme == "https")
        #expect(incident.googleMapsDirectionsURL.scheme == "https")
    }

    // MARK: - Coordinate privacy

    @Test @MainActor func publicCoordinateIsNotExactReporterLocation() {
        let store = IncidentStore()
        let exact = CLLocationCoordinate2D(latitude: 6.5244, longitude: 3.3792)
        store.addIncident(
            title: "Privacy test", summary: "Verifying local approximate privacy.",
            category: .community, subtype: .localWarning, severity: .low,
            neighborhood: "Test", reporterCoordinate: exact
        )
        let added = store.incidents.last!
        // Local visibility uses a coarse approximate pin so the reporter can see
        // their own report; the exact reporter coordinate stays private and is
        // never published as the public map pin.
        #expect(added.coordinate != nil)
        #expect(added.coordinate?.latitude != exact.latitude || added.coordinate?.longitude != exact.longitude)
    }

    @Test @MainActor func publicCoordinateIsStoredSeparatelyFromReporterCoordinate() {
        let store = IncidentStore()
        let exact = CLLocationCoordinate2D(latitude: 6.5244, longitude: 3.3792)
        store.addIncident(
            title: "T", summary: "S", category: .community,
            subtype: .localWarning, severity: .low,
            neighborhood: "Test", reporterCoordinate: exact
        )
        let added = store.incidents.last!
        // reporterCoordinate holds the exact location (private).
        // coordinate is a local approximate display pin (not the exact reporter point).
        #expect(added.reporterCoordinate != nil)
        let reporter = added.reporterCoordinate!
        #expect(reporter.latitude  == exact.latitude)
        #expect(reporter.longitude == exact.longitude)
        #expect(added.coordinate != nil)
        #expect(added.coordinate?.latitude != exact.latitude || added.coordinate?.longitude != exact.longitude)
    }

    @Test @MainActor func noReporterCoordinateStoresNilInstead() {
        let store = IncidentStore()
        store.addIncident(
            title: "Anonymous", summary: "No location shared.",
            category: .community, subtype: .localWarning, severity: .low,
            neighborhood: "Test", reporterCoordinate: nil
        )
        let added = store.incidents.last!
        #expect(added.reporterCoordinate == nil)
        // No location shared → no fabricated public pin either.
        #expect(added.coordinate == nil)
    }

    // MARK: - Input sanitisation at system boundary (classifier)

    @Test func classifierHandlesNullByteWithoutCrash() {
        let result = IncidentClassifier.classify(title: "fire\0bomb", summary: "")
        #expect(IncidentCategory.allCases.contains(result.category))
    }

    @Test func classifierHandlesHTMLTagsWithoutCrash() {
        let result = IncidentClassifier.classify(
            title: "<script>alert('xss')</script>",
            summary: "'; DROP TABLE incidents; --"
        )
        #expect(IncidentCategory.allCases.contains(result.category))
    }

    @Test func classifierHandlesVeryLongInputWithoutCrash() {
        let megaString = String(repeating: "a", count: 100_000)
        let result = IncidentClassifier.classify(title: megaString, summary: megaString)
        #expect(IncidentCategory.allCases.contains(result.category))
    }

    // MARK: - URL structure integrity

    @Test func googleMapsAreaURLContainsRequiredQueryParam() {
        let incident = makeSecurityIncident()
        let url = incident.googleMapsAreaURL.absoluteString
        #expect(url.contains("api=1"))
        #expect(url.contains("query="))
    }

    @Test func googleMapsDirectionsURLContainsTravelMode() {
        let incident = makeSecurityIncident()
        let url = incident.googleMapsDirectionsURL.absoluteString
        #expect(url.contains("travelmode=driving"))
        #expect(url.contains("destination="))
    }
}

private func makeSecurityIncident() -> Incident {
    Incident(
        id: UUID(), title: "Test", summary: "Test summary.",
        category: .security, subtype: .suspiciousActivity,
        severity: .medium, status: .active,
        reporterCoordinate: nil,
        coordinate: CLLocationCoordinate2D(latitude: 6.5244, longitude: 3.3792),
        neighborhood: "Test", reportedAt: Date(),
        confirmations: 1, updates: []
    )
}
