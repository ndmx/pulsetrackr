//
//  BoundaryTests.swift
//  pulsetrackrTests
//
//  Edge-case and boundary coverage: zero counts, exact threshold values,
//  extreme inputs, and large-number arithmetic.
//

import Testing
import MapKit
@testable import pulsetrackr

@Suite("Boundary & Edge Cases")
struct BoundaryTests {

    // MARK: - Confidence tier boundaries

    @Test func confidenceAt7ConfirmationsIsNotVerified() {
        // 7 = one below communityVerified threshold
        let incident = makeIncident(confirmations: 7)
        #expect(incident.confidence == .multipleReports)
    }

    @Test func confidenceAt8ConfirmationsIsVerified() {
        let incident = makeIncident(confirmations: 8)
        #expect(incident.confidence == .communityVerified)
    }

    @Test func confidenceAt1ConfirmationIsUnconfirmed() {
        let incident = makeIncident(confirmations: 1)
        #expect(incident.confidence == .unconfirmed)
    }

    @Test func confidenceAt2ConfirmationsIsMultipleReports() {
        let incident = makeIncident(confirmations: 2)
        #expect(incident.confidence == .multipleReports)
    }

    @Test func confidenceWithDisputesExactlyEqualConfirmationsIsNotVerified() {
        // 8 confirmations, 8 disputes: tie must not grant communityVerified
        let incident = makeIncident(confirmations: 8, disputes: 8)
        #expect(incident.confidence != .communityVerified)
    }

    @Test func confidenceWithDisputesOneLessThanConfirmationsIsVerified() {
        // 8 confirmations, 7 disputes: slight majority still earns verified
        let incident = makeIncident(confirmations: 8, disputes: 7)
        #expect(incident.confidence == .communityVerified)
    }

    // MARK: - Cleared signal threshold

    @Test @MainActor func twoClaredSignalsDoNotResolve() {
        let store = IncidentStore()
        store.addIncident(title: "T", summary: "S", category: .community,
                          subtype: .localWarning, severity: .low,
                          neighborhood: "Test", reporterCoordinate: nil)
        let added = store.incidents.last!
        store.record(.cleared, for: added)
        store.record(.cleared, for: store.incident(withID: added.id)!)
        #expect(store.incident(withID: added.id)!.status != .resolved)
    }

    @Test @MainActor func exactlyThreeClearedSignalsResolve() {
        let store = IncidentStore()
        store.addIncident(title: "T", summary: "S", category: .community,
                          subtype: .localWarning, severity: .low,
                          neighborhood: "Test", reporterCoordinate: nil)
        let added = store.incidents.last!
        for _ in 1...3 {
            store.record(.cleared, for: store.incident(withID: added.id)!)
        }
        #expect(store.incident(withID: added.id)!.status == .resolved)
    }

    // MARK: - notSeen parity boundary

    @Test @MainActor func disputesOneLessThanConfirmationsStaysActive() {
        let store = IncidentStore()
        // Seed an incident with 3 confirmations
        store.addIncident(title: "T", summary: "S", category: .community,
                          subtype: .localWarning, severity: .low,
                          neighborhood: "Test", reporterCoordinate: nil)
        let id = store.incidents.last!.id
        // Give 2 extra confirmations (total = 3)
        store.record(.seen, for: store.incident(withID: id)!)
        store.record(.seen, for: store.incident(withID: id)!)
        // 2 disputes < 3 confirmations → should stay active
        store.record(.notSeen, for: store.incident(withID: id)!)
        store.record(.notSeen, for: store.incident(withID: id)!)
        #expect(store.incident(withID: id)!.status == .active)
    }

    @Test @MainActor func disputesEqualToConfirmationsTriggersWatching() {
        let store = IncidentStore()
        store.addIncident(title: "T", summary: "S", category: .community,
                          subtype: .localWarning, severity: .low,
                          neighborhood: "Test", reporterCoordinate: nil)
        let id = store.incidents.last!.id
        // 1 confirmation already; 1 dispute = parity → watching
        store.record(.notSeen, for: store.incident(withID: id)!)
        #expect(store.incident(withID: id)!.status == .watching)
    }

    // MARK: - Zero-count store

    @Test @MainActor func activeIncidentsOnEmptyStoreIsEmptyAfterResolvingAll() {
        let store = IncidentStore()
        for incident in store.incidents {
            store.markResolved(incident)
        }
        #expect(store.activeIncidents.isEmpty)
    }

    @Test @MainActor func incidentLookupOnEmptyStoreReturnsNil() {
        let store = IncidentStore()
        for incident in store.incidents {
            store.markResolved(incident)
        }
        #expect(store.incident(withID: UUID()) == nil)
    }

    // MARK: - Large counter values

    @Test func veryHighConfirmationCountStaysVerified() {
        let incident = makeIncident(confirmations: 100_000, disputes: 0)
        #expect(incident.confidence == .communityVerified)
    }

    @Test func veryHighDisputeCountBlocksVerified() {
        let incident = makeIncident(confirmations: 8, disputes: 100_000)
        #expect(incident.confidence != .communityVerified)
    }

    @Test func signalSummaryHandlesLargeNumbers() {
        let incident = makeIncident(confirmations: 999_999, disputes: 999_999,
                                    unsafeReports: 999_999, clearedReports: 999_999)
        #expect(incident.signalSummary.contains("999999"))
    }

    // MARK: - Extreme coordinates

    @Test func googleMapsURLWithMaxValidLatitude() {
        let incident = Incident(
            id: UUID(), title: "T", summary: "S",
            category: .community, subtype: .localWarning,
            severity: .low, status: .active,
            reporterCoordinate: nil,
            coordinate: CLLocationCoordinate2D(latitude: 90.0, longitude: 180.0),
            neighborhood: "Edge", reportedAt: Date(),
            confirmations: 1, updates: []
        )
        _ = incident.googleMapsAreaURL         // must not crash
        _ = incident.googleMapsDirectionsURL   // must not crash
    }

    @Test func googleMapsURLWithNegativeCoordinates() {
        let incident = Incident(
            id: UUID(), title: "T", summary: "S",
            category: .community, subtype: .localWarning,
            severity: .low, status: .active,
            reporterCoordinate: nil,
            coordinate: CLLocationCoordinate2D(latitude: -33.8688, longitude: 151.2093),
            neighborhood: "Sydney", reportedAt: Date(),
            confirmations: 1, updates: []
        )
        let url = incident.googleMapsAreaURL
        #expect(url.absoluteString.contains("-33.8688"))
    }

    // MARK: - All categories have at least one subtype

    @Test func everyCategoryHasAtLeastOneSubtype() {
        for category in IncidentCategory.allCases {
            #expect(!IncidentSubtype.subtypes(for: category).isEmpty,
                    "Category \(category.rawValue) has no subtypes")
        }
    }

    // MARK: - Date ordering

    @Test @MainActor func activeIncidentsSortedNewestFirst() {
        let store = IncidentStore()
        // Add two incidents with distinct times — they share the same Date() so
        // check the relative order matches reportedAt descending.
        store.addIncident(title: "First", summary: "S", category: .community,
                          subtype: .localWarning, severity: .low,
                          neighborhood: "A", reporterCoordinate: nil)
        store.addIncident(title: "Second", summary: "S", category: .community,
                          subtype: .localWarning, severity: .low,
                          neighborhood: "B", reporterCoordinate: nil)
        let active = store.activeIncidents
        let dates = active.map(\.reportedAt)
        #expect(dates == dates.sorted(by: >))
    }
}

// MARK: - Local helper (mirrors the one in pulsetrackrTests.swift)

private func makeIncident(
    confirmations: Int = 1,
    disputes: Int = 0,
    unsafeReports: Int = 0,
    blockedReports: Int = 0,
    clearedReports: Int = 0,
    officialUpdates: Int = 0,
    severity: IncidentSeverity = .low,
    status: IncidentStatus = .active,
    category: IncidentCategory = .community,
    subtype: IncidentSubtype = .localWarning
) -> Incident {
    Incident(
        id: UUID(),
        title: "Boundary Test",
        summary: "Boundary test summary.",
        category: category,
        subtype: subtype,
        severity: severity,
        status: status,
        reporterCoordinate: nil,
        coordinate: CLLocationCoordinate2D(latitude: 6.5244, longitude: 3.3792),
        neighborhood: "Test Area",
        reportedAt: Date(),
        confirmations: confirmations,
        disputes: disputes,
        unsafeReports: unsafeReports,
        blockedReports: blockedReports,
        clearedReports: clearedReports,
        officialUpdates: officialUpdates,
        updates: []
    )
}
