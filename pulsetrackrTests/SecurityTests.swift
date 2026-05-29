//
//  SecurityTests.swift
//  pulsetrackrTests
//
//  Security-focused tests: HTTPS enforcement, coordinate privacy (reporter
//  location fuzzing), URL safety, and input sanitisation at system boundaries.
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

    // MARK: - Coordinate privacy (reporter location fuzzing)

    @Test @MainActor func publicCoordinateDiffersFromExactReporterLocation() {
        let store = IncidentStore()
        let exact = CLLocationCoordinate2D(latitude: 6.5244, longitude: 3.3792)
        store.addIncident(
            title: "Privacy test", summary: "Verifying fuzzing.",
            category: .community, subtype: .localWarning, severity: .low,
            neighborhood: "Test", reporterCoordinate: exact
        )
        let added = store.incidents.last!
        let pub = added.coordinate!
        // The public coordinate must not match the reporter's exact position
        let sameLocation = pub.latitude == exact.latitude &&
                           pub.longitude == exact.longitude
        #expect(!sameLocation, "Public coordinate must be fuzzed away from exact location")
    }

    @Test @MainActor func publicCoordinateStaysWithinPrivacyRadiusMeters() {
        let store = IncidentStore()
        let exact = CLLocationCoordinate2D(latitude: 6.5244, longitude: 3.3792)
        store.addIncident(
            title: "Radius test", summary: "Verifying fuzzing radius.",
            category: .community, subtype: .localWarning, severity: .low,
            neighborhood: "Test", reporterCoordinate: exact
        )
        let added = store.incidents.last!
        let pub = added.coordinate!

        // Convert degree difference to approximate metres
        let latMetres = abs(pub.latitude  - exact.latitude)  * 111_320.0
        let lonMetres = abs(pub.longitude - exact.longitude) *
                        cos(exact.latitude * .pi / 180) * 111_320.0
        let distance  = (latMetres * latMetres + lonMetres * lonMetres).squareRoot()

        #expect(distance >= 100, "Fuzz must be at least 100 m for privacy")
        #expect(distance <= 400, "Fuzz must stay within 400 m to remain area-accurate")
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
        // reporterCoordinate holds the exact location (private)
        // coordinate holds the fuzzed location (public)
        #expect(added.reporterCoordinate != nil)
        let reporter = added.reporterCoordinate!
        #expect(reporter.latitude  == exact.latitude)
        #expect(reporter.longitude == exact.longitude)
        // The public coordinate is different
        let pub = added.coordinate!
        #expect(pub.latitude  != reporter.latitude  ||
                pub.longitude != reporter.longitude)
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
