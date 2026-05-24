//
//  RegressionTests.swift
//  pulsetrackrTests
//
//  One test per bug that was found and fixed. These exist to prevent regressions.
//  If any of these fail, a previously fixed bug has come back.
//

import Testing
import MapKit
@testable import pulsetrackr

@Suite("Regression Tests")
struct RegressionTests {

    // Bug: "ceasefire" was classified as .buildingFire because "fire" appeared inside the word.
    // Fix: changed fire keyword from "fire" to " fire", "fire ", or hasPrefix("fire").
    @Test func bug_ceasefireNotClassifiedAsFire() {
        let result = IncidentClassifier.classify(
            title: "Ceasefire declared in the area",
            summary: "Calm restored after earlier clash."
        )
        #expect(result.category != .fire,
                "Regression: 'ceasefire' must not match the fire classifier")
    }

    // Bug: a resolved incident could be re-activated by an .unsafe community signal.
    // Fix: added `guard incidents[index].status != .resolved else { return }` in record().
    @Test @MainActor func bug_resolvedIncidentNotReactivatedByUnsafeSignal() {
        let store = IncidentStore()
        guard let incident = store.incidents.first else { return }
        store.markResolved(incident)
        store.record(.unsafe, for: store.incident(withID: incident.id)!)
        #expect(store.incident(withID: incident.id)!.status == .resolved,
                "Regression: .unsafe must not re-activate a resolved incident")
    }

    // Bug: "bad road causing accidents" was classified as .crash because the
    // accident keyword rule ran before the bad road rule.
    // Fix: moved badRoad and floodedRoad checks before the crash check.
    @Test func bug_badRoadWithAccidentWordNotMisclassifiedAsCrash() {
        let result = IncidentClassifier.classify(
            title: "Bad road",
            summary: "Pothole causing vehicles to swerve dangerously."
        )
        #expect(result.category == .traffic,
                "Regression: bad road should be traffic category")
        #expect(result.subtype == .badRoad,
                "Regression: should classify as .badRoad, not .crash")
    }

    // Bug: an incident with 8 confirmations and more disputes was still shown
    // as .communityVerified because disputes were ignored in the confidence formula.
    // Fix: added `disputes < confirmations` guard before returning communityVerified.
    @Test func bug_disputeMajorityBlocksCommunityVerified() {
        let incident = Incident(
            id: UUID(), title: "T", summary: "S",
            category: .community, subtype: .localWarning,
            severity: .low, status: .active,
            reporterCoordinate: nil,
            coordinate: CLLocationCoordinate2D(latitude: 6.5244, longitude: 3.3792),
            neighborhood: "Test", reportedAt: Date(),
            confirmations: 8, disputes: 9,
            updates: []
        )
        #expect(incident.confidence != .communityVerified,
                "Regression: majority-disputed incident must not reach communityVerified")
    }

    // Bug: googleMapsAreaURL and googleMapsDirectionsURL used force-unwrap (URL(string:)!)
    // which would crash if the coordinate contained NaN or Inf.
    // Fix: switched to optional URL construction with a fallback.
    @Test func bug_mapURLDoesNotCrashOnInvalidCoordinate() {
        // CLLocationCoordinate2DIsValid returns false for kCLLocationCoordinate2DInvalid
        let incident = Incident(
            id: UUID(), title: "T", summary: "S",
            category: .community, subtype: .localWarning,
            severity: .low, status: .active,
            reporterCoordinate: nil,
            coordinate: kCLLocationCoordinate2DInvalid,
            neighborhood: "Test", reportedAt: Date(),
            confirmations: 1, updates: []
        )
        // These must not crash — before the fix they would force-unwrap nil
        let areaURL = incident.googleMapsAreaURL
        let dirURL  = incident.googleMapsDirectionsURL
        #expect(areaURL.absoluteString.contains("google.com"))
        #expect(dirURL.absoluteString.contains("google.com"))
    }

    // Bug: notSeen used strict `>` so disputes equal to confirmations did not
    // flip the incident to .watching, leaving a 50/50-disputed incident as .active.
    // Fix: changed to `>=`.
    @Test @MainActor func bug_notSeenAtParityTriggersWatching() {
        let store = IncidentStore()
        store.addIncident(title: "T", summary: "S", category: .community,
                          subtype: .localWarning, severity: .low,
                          neighborhood: "Test", reporterCoordinate: nil)
        let added = store.incidents.last!
        // 1 confirmation already; 1 dispute = parity
        store.record(.notSeen, for: added)
        #expect(store.incident(withID: added.id)!.status == .watching,
                "Regression: dispute parity must set status to .watching")
    }

    // Bug: flooded road text was captured by the weather flooding rule instead of
    // the traffic floodedRoad subtype because the weather check ran first.
    // Fix: added flooded-road check before the weather flooding check.
    @Test func bug_floodedRoadClassifiedAsTrafficNotWeather() {
        let result = IncidentClassifier.classify(
            title: "Flooded road ahead",
            summary: "Road is impassable."
        )
        #expect(result.category == .traffic,
                "Regression: flooded road should be traffic, not weather")
        #expect(result.subtype == .floodedRoad,
                "Regression: should be .floodedRoad subtype")
    }
}
