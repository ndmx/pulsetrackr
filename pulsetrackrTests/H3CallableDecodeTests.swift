//
//  H3CallableDecodeTests.swift
//  pulsetrackrTests
//
//  Verifies the iOS decode path for the scalable H3 feed callable
//  (query_incidents_h3): contract-shaped response bodies map to domain incidents,
//  Resolved incidents are filtered, and malformed bodies decode to empty rather than
//  crashing. The decode reuses the same ContractDTO + mapping as the live listener.
//

import Testing
import Foundation
@testable import pulsetrackr

struct H3CallableDecodeTests {
    private func sampleBody() -> [String: Any] {
        [
            "incidents": [
                [
                    "incident_id": "incident-active",
                    "title": "Building fire on 3rd",
                    "summary": "Smoke reported from the upper floors.",
                    "category": "fire",
                    "subtype": "building_fire",
                    "severity": "High",
                    "status": "Active",
                    "neighborhood": "Marina",
                    "latitude": 6.5244,
                    "longitude": 3.3792,
                    "geohash": "s0gs3y",
                    "public_h3_cell": "8828308281fffff",
                    "public_h3_resolution": 8,
                    "location_reveal_status": "revealed",
                    "location_privacy_policy": "h3_k_anonymous",
                    "k_anonymity_threshold": 3,
                    "k_anonymity_distinct_reporters": 4,
                    "confirmations": 4,
                    "disputes": 0,
                    "unsafe_reports": 1,
                    "blocked_reports": 0,
                    "cleared_reports": 0,
                    "official_updates": 0,
                    "reported_at": "2026-06-21T12:00:00Z"
                ],
                [
                    "incident_id": "incident-resolved",
                    "title": "Cleared collision",
                    "summary": "Resolved by the community.",
                    "category": "traffic",
                    "subtype": "crash",
                    "severity": "Medium",
                    "status": "Resolved",
                    "neighborhood": "Yaba",
                    "confirmations": 1,
                    "disputes": 0,
                    "unsafe_reports": 0,
                    "blocked_reports": 0,
                    "cleared_reports": 3,
                    "official_updates": 0,
                    "reported_at": "2026-06-21T11:00:00Z"
                ]
            ],
            "query": ["strategy": "h3_hierarchical", "cell_count": 7, "radius_meters": 3000]
        ]
    }

    @Test func decodesActiveIncidentsAndFiltersResolved() {
        let incidents = SafetyIncidentRemoteStore.decodeCallableIncidents(sampleBody())

        #expect(incidents.count == 1)
        let incident = try! #require(incidents.first)
        #expect(incident.remoteDocumentID == "incident-active")
        #expect(incident.title == "Building fire on 3rd")
        #expect(incident.category == .fire)
        #expect(incident.subtype == .buildingFire)
        #expect(incident.severity == .high)
        #expect(incident.status == .active)
        #expect(incident.confirmations == 4)
        #expect(incident.unsafeReports == 1)
        #expect(incident.coordinate != nil)
        #expect(incident.locationRevealStatus == .revealed)
    }

    @Test func malformedBodiesDecodeToEmpty() {
        #expect(SafetyIncidentRemoteStore.decodeCallableIncidents([:]).isEmpty)
        #expect(SafetyIncidentRemoteStore.decodeCallableIncidents(["incidents": "not-an-array"]).isEmpty)
        #expect(SafetyIncidentRemoteStore.decodeCallableIncidents(["incidents": []]).isEmpty)
    }
}
