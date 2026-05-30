//
//  pulsetrackrTests.swift
//  pulsetrackrTests
//
//  Created by Alexander Ukaga on 8/14/25.
//

import Testing
import MapKit
@testable import pulsetrackr

// MARK: - Helpers

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
        title: "Test Incident",
        summary: "Test summary.",
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

// MARK: - IncidentCategory

@Suite("IncidentCategory")
struct IncidentCategoryTests {

    @Test func allCasesExist() {
        let expected: [IncidentCategory] = [.security, .traffic, .fire, .medical, .weather, .utilities, .structure, .community]
        #expect(IncidentCategory.allCases == expected)
    }

    @Test func labelsAreNonEmpty() {
        for category in IncidentCategory.allCases {
            #expect(!category.label.isEmpty)
        }
    }

    @Test func iconsAreNonEmpty() {
        for category in IncidentCategory.allCases {
            #expect(!category.icon.isEmpty)
        }
    }

    @Test func idMatchesRawValue() {
        for category in IncidentCategory.allCases {
            #expect(category.id == category.rawValue)
        }
    }
}

// MARK: - IncidentSubtype

@Suite("IncidentSubtype")
struct IncidentSubtypeTests {

    @Test func allSubtypesHaveNonEmptyLabelsAndIcons() {
        for subtype in IncidentSubtype.allCases {
            #expect(!subtype.label.isEmpty, "Empty label for \(subtype.rawValue)")
            #expect(!subtype.icon.isEmpty, "Empty icon for \(subtype.rawValue)")
        }
    }

    @Test func securitySubtypesBelongToSecurityCategory() {
        let securitySubtypes: [IncidentSubtype] = [
            .armedRobbery, .kidnapping, .gunshots, .carjacking,
            .oneChance, .suspiciousActivity, .checkpointIssue, .communalClash
        ]
        for subtype in securitySubtypes {
            #expect(subtype.category == .security, "\(subtype.rawValue) should be .security")
        }
    }

    @Test func trafficSubtypesBelongToTrafficCategory() {
        let trafficSubtypes: [IncidentSubtype] = [
            .crash, .roadblock, .gridlock, .floodedRoad, .badRoad, .brokenDownVehicle
        ]
        for subtype in trafficSubtypes {
            #expect(subtype.category == .traffic, "\(subtype.rawValue) should be .traffic")
        }
    }

    @Test func fireSubtypesBelongToFireCategory() {
        let fireSubtypes: [IncidentSubtype] = [
            .buildingFire, .marketFire, .gasLeak, .explosion, .electricalFire, .pipelineFire
        ]
        for subtype in fireSubtypes {
            #expect(subtype.category == .fire, "\(subtype.rawValue) should be .fire")
        }
    }

    @Test func subtypesForCategoryFiltersCorrectly() {
        let securitySubtypes = IncidentSubtype.subtypes(for: .security)
        #expect(securitySubtypes.allSatisfy { $0.category == .security })
        #expect(!securitySubtypes.isEmpty)
    }

    @Test func defaultSubtypeForCategoryIsFirstSubtype() {
        for category in IncidentCategory.allCases {
            let defaultSubtype = IncidentSubtype.defaultSubtype(for: category)
            let subtypes = IncidentSubtype.subtypes(for: category)
            #expect(defaultSubtype == subtypes.first)
        }
    }

    @Test func isAlwaysHighRiskReturnsTrueForDangerousSubtypes() {
        let highRiskSubtypes: [IncidentSubtype] = [
            .armedRobbery, .kidnapping, .gunshots, .carjacking, .communalClash,
            .buildingFire, .marketFire, .gasLeak, .explosion, .pipelineFire,
            .medicalEmergency, .suspectedOutbreak, .flooding,
            .buildingCollapse, .bridgeCollapse, .roadCollapse, .fallenPowerLine, .missingPerson
        ]
        for subtype in highRiskSubtypes {
            #expect(subtype.isAlwaysHighRisk, "\(subtype.rawValue) should be high risk")
        }
    }

    @Test func isAlwaysHighRiskReturnsFalseForRoutineSubtypes() {
        let routineSubtypes: [IncidentSubtype] = [
            .localWarning, .safeRoute, .communityWatch, .publicGathering, .aidNeeded,
            .powerOutage, .waterOutage, .fuelScarcity, .roadblock, .gridlock
        ]
        for subtype in routineSubtypes {
            #expect(!subtype.isAlwaysHighRisk, "\(subtype.rawValue) should NOT be always high risk")
        }
    }
}

// MARK: - IncidentConfidence

@Suite("Incident.confidence")
struct IncidentConfidenceTests {

    @Test func officialUpdateTakesPriority() {
        let incident = makeIncident(confirmations: 100, officialUpdates: 1)
        #expect(incident.confidence == .officialUpdate)
    }

    @Test func communityVerifiedAt8OrMoreConfirmations() {
        let incident = makeIncident(confirmations: 8)
        #expect(incident.confidence == .communityVerified)
    }

    @Test func communityVerifiedAt20Confirmations() {
        let incident = makeIncident(confirmations: 20)
        #expect(incident.confidence == .communityVerified)
    }

    @Test func multipleReportsAt2Confirmations() {
        let incident = makeIncident(confirmations: 2)
        #expect(incident.confidence == .multipleReports)
    }

    @Test func multipleReportsWithUnsafeSignal() {
        let incident = makeIncident(confirmations: 1, unsafeReports: 1)
        #expect(incident.confidence == .multipleReports)
    }

    @Test func multipleReportsWithBlockedSignal() {
        let incident = makeIncident(confirmations: 1, blockedReports: 1)
        #expect(incident.confidence == .multipleReports)
    }

    @Test func unconfirmedWithSingleConfirmation() {
        let incident = makeIncident(confirmations: 1)
        #expect(incident.confidence == .unconfirmed)
    }

    @Test func unconfirmedWithZeroConfirmations() {
        let incident = makeIncident(confirmations: 0)
        #expect(incident.confidence == .unconfirmed)
    }

    @Test func communityVerifiedBlockedWhenDisputesMajority() {
        // 8 confirmations but more disputes — should NOT reach communityVerified
        let incident = makeIncident(confirmations: 8, disputes: 9)
        #expect(incident.confidence != .communityVerified)
    }

    @Test func communityVerifiedBlockedWhenDisputesEqual() {
        let incident = makeIncident(confirmations: 8, disputes: 8)
        #expect(incident.confidence != .communityVerified)
    }
}

// MARK: - Incident.isHighRisk

@Suite("Incident.isHighRisk")
struct IncidentIsHighRiskTests {

    @Test func urgentSeverityIsHighRisk() {
        let incident = makeIncident(severity: .urgent)
        #expect(incident.isHighRisk)
    }

    @Test func highSeverityIsHighRisk() {
        let incident = makeIncident(severity: .high)
        #expect(incident.isHighRisk)
    }

    @Test func lowSeverityIsNotHighRiskByDefault() {
        let incident = makeIncident(severity: .low, subtype: .localWarning)
        #expect(!incident.isHighRisk)
    }

    @Test func lowSeverityWithUnsafeReportIsHighRisk() {
        let incident = makeIncident(unsafeReports: 1, severity: .low)
        #expect(incident.isHighRisk)
    }

    @Test func alwaysHighRiskSubtypeElevatesRisk() {
        let incident = makeIncident(severity: .low, subtype: .gunshots)
        #expect(incident.isHighRisk)
    }
}

@Suite("IncidentStore alert filters")
struct IncidentStoreAlertFilterTests {
    private let userCoordinate = CLLocationCoordinate2D(latitude: 6.5244, longitude: 3.3792)
    private let hiddenIncidentIDsKey = "hiddenIncidentIDs"

    private func resetHiddenIncidents() {
        UserDefaults.standard.removeObject(forKey: hiddenIncidentIDsKey)
    }

    @Test @MainActor func highRiskCommunityCategoryUsesUrgentToggle() {
        resetHiddenIncidents()
        let store = IncidentStore(remoteStore: nil)
        store.addIncident(
            title: "Bridge blocked",
            summary: "Urgent traffic risk.",
            category: .traffic,
            subtype: .roadblock,
            severity: .urgent,
            neighborhood: "Test",
            reporterCoordinate: userCoordinate
        )

        let visible = store.nearbyIncidents(
            urgentAlerts: true,
            communityAlerts: false,
            watchRadius: 15,
            near: userCoordinate
        )

        #expect(visible.count == 1)
    }

    @Test @MainActor func urgentToggleHidesHighRiskCommunityCategory() {
        resetHiddenIncidents()
        let store = IncidentStore(remoteStore: nil)
        store.addIncident(
            title: "Bridge blocked",
            summary: "Urgent traffic risk.",
            category: .traffic,
            subtype: .roadblock,
            severity: .urgent,
            neighborhood: "Test",
            reporterCoordinate: userCoordinate
        )

        let visible = store.nearbyIncidents(
            urgentAlerts: false,
            communityAlerts: true,
            watchRadius: 15,
            near: userCoordinate
        )

        #expect(visible.isEmpty)
    }

    @Test @MainActor func communityToggleControlsLowerRiskCommunityNotices() {
        resetHiddenIncidents()
        let store = IncidentStore(remoteStore: nil)
        store.addIncident(
            title: "Local notice",
            summary: "Community watch update.",
            category: .community,
            subtype: .communityWatch,
            severity: .low,
            neighborhood: "Test",
            reporterCoordinate: userCoordinate
        )

        let hidden = store.nearbyIncidents(
            urgentAlerts: true,
            communityAlerts: false,
            watchRadius: 15,
            near: userCoordinate
        )
        let visible = store.nearbyIncidents(
            urgentAlerts: true,
            communityAlerts: true,
            watchRadius: 15,
            near: userCoordinate
        )

        #expect(hidden.isEmpty)
        #expect(visible.count == 1)
    }

    @Test @MainActor func reportingConcernHidesIncidentLocally() {
        resetHiddenIncidents()
        defer { resetHiddenIncidents() }

        let store = IncidentStore(remoteStore: nil)
        store.addIncident(
            title: "False alert",
            summary: "This report should be hidden after concern reporting.",
            category: .community,
            subtype: .localWarning,
            severity: .low,
            neighborhood: "Test",
            reporterCoordinate: userCoordinate
        )

        let incident = store.activeIncidents[0]
        store.recordConcern(.falseReport, for: incident)

        #expect(store.activeIncidents.isEmpty)
        #expect(store.incident(withID: incident.id) != nil)
    }
}

// MARK: - Incident.alertTone

@Suite("Incident.alertTone")
struct IncidentAlertToneTests {

    @Test func resolvedIncidentReturnsNoLongerActive() {
        let incident = makeIncident(status: .resolved)
        #expect(incident.alertTone == "No longer active")
    }

    @Test func highRiskActiveIncidentReturnsNearbyAlert() {
        let incident = makeIncident(severity: .urgent, status: .active)
        #expect(incident.alertTone == "Nearby alert sent")
    }

    @Test func lowRiskActiveIncidentReturnsLiveLocalReport() {
        let incident = makeIncident(severity: .low, status: .active, subtype: .publicGathering)
        #expect(incident.alertTone == "Live local report")
    }

    @Test func resolvedTakesPriorityOverHighRisk() {
        // A resolved incident that is also high risk should say "No longer active"
        let incident = makeIncident(severity: .urgent, status: .resolved)
        #expect(incident.alertTone == "No longer active")
    }
}

// MARK: - Incident.signalSummary

@Suite("Incident.signalSummary")
struct IncidentSignalSummaryTests {

    @Test func signalSummaryFormatsAllCounts() {
        let incident = makeIncident(confirmations: 5, disputes: 2, unsafeReports: 1, clearedReports: 3)
        #expect(incident.signalSummary == "5 seen • 2 not seen • 1 unsafe • 3 cleared")
    }

    @Test func signalSummaryWithAllZeros() {
        let incident = makeIncident(confirmations: 0, disputes: 0, unsafeReports: 0, clearedReports: 0)
        #expect(incident.signalSummary == "0 seen • 0 not seen • 0 unsafe • 0 cleared")
    }
}

// MARK: - Incident URLs

@Suite("Incident URLs")
struct IncidentURLTests {

    @Test func googleMapsAreaURLContainsCoordinates() {
        let lat = 6.5244
        let lon = 3.3792
        let incident = makeIncident()
        let url = incident.googleMapsAreaURL
        #expect(url.absoluteString.contains(String(lat)))
        #expect(url.absoluteString.contains(String(lon)))
        #expect(url.absoluteString.contains("maps.google.com") || url.absoluteString.contains("google.com/maps"))
    }

    @Test func googleMapsDirectionsURLContainsCoordinatesAndDriving() {
        let incident = makeIncident()
        let url = incident.googleMapsDirectionsURL
        #expect(url.absoluteString.contains("travelmode=driving"))
        #expect(url.absoluteString.contains("destination="))
    }
}

// MARK: - CommunitySignal

@Suite("CommunitySignal")
struct CommunitySignalTests {

    @Test func allSignalsHaveNonEmptyLabels() {
        for signal in CommunitySignal.allCases {
            #expect(!signal.label.isEmpty)
        }
    }

    @Test func allSignalsHaveNonEmptyIcons() {
        for signal in CommunitySignal.allCases {
            #expect(!signal.icon.isEmpty)
        }
    }

    @Test func allSignalsHaveNonEmptyUpdateMessages() {
        for signal in CommunitySignal.allCases {
            #expect(!signal.updateMessage.isEmpty)
        }
    }
}

// MARK: - IncidentClassifier

@Suite("IncidentClassifier")
struct IncidentClassifierTests {

    // Security — Kidnapping
    @Test func classifiesKidnapping() {
        let result = IncidentClassifier.classify(title: "Man kidnapped near school", summary: "Witnesses say abductors fled in a jeep.")
        #expect(result.category == .security)
        #expect(result.subtype == .kidnapping)
        #expect(result.severity == .urgent)
    }

    // Security — Gunshots
    @Test func classifiesGunshots() {
        let result = IncidentClassifier.classify(title: "Gunshots heard", summary: "Shots fired near the market.")
        #expect(result.category == .security)
        #expect(result.subtype == .gunshots)
        #expect(result.severity == .urgent)
    }

    // Security — Armed Robbery
    @Test func classifiesArmedRobbery() {
        let result = IncidentClassifier.classify(title: "Robbery at fuel station", summary: "Armed robbers stormed the area.")
        #expect(result.category == .security)
        #expect(result.subtype == .armedRobbery)
        #expect(result.severity == .urgent)
    }

    // Security — Carjacking
    @Test func classifiesCarjacking() {
        let result = IncidentClassifier.classify(title: "Carjacking reported", summary: "Suspect snatched car at gunpoint.")
        #expect(result.category == .security)
        #expect(result.subtype == .carjacking)
        #expect(result.severity == .high)
    }

    // Security — One-Chance
    @Test func classifiesOneChance() {
        let result = IncidentClassifier.classify(title: "One chance bus spotted", summary: "Fake taxi operating near the junction.")
        #expect(result.category == .security)
        #expect(result.subtype == .oneChance)
        #expect(result.severity == .high)
    }

    // Security — Communal Clash
    @Test func classifiesCommunalClash() {
        let result = IncidentClassifier.classify(title: "Clash in community", summary: "Riot and cultist activity reported.")
        #expect(result.category == .security)
        #expect(result.subtype == .communalClash)
        #expect(result.severity == .high)
    }

    // Security — Checkpoint Issue
    @Test func classifiesCheckpointIssue() {
        let result = IncidentClassifier.classify(title: "Checkpoint issue ahead", summary: "Extortion reported at road checkpoint.")
        #expect(result.category == .security)
        #expect(result.subtype == .checkpointIssue)
        #expect(result.severity == .medium)
    }

    // Traffic — Crash
    @Test func classifiesCrash() {
        let result = IncidentClassifier.classify(title: "Accident on express", summary: "Collision between two vehicles reported.")
        #expect(result.category == .traffic)
        #expect(result.subtype == .crash)
        #expect(result.severity == .high)
    }

    // Traffic — Roadblock
    @Test func classifiesRoadblock() {
        let result = IncidentClassifier.classify(title: "Road blocked", summary: "Blocked route near bridge.")
        #expect(result.category == .traffic)
        #expect(result.subtype == .roadblock)
        #expect(result.severity == .medium)
    }

    // Traffic — Gridlock
    @Test func classifiesGridlock() {
        let result = IncidentClassifier.classify(title: "Heavy traffic", summary: "Gridlock and go slow on the expressway.")
        #expect(result.category == .traffic)
        #expect(result.subtype == .gridlock)
        #expect(result.severity == .medium)
    }

    // Traffic — Bad Road
    @Test func classifiesBadRoad() {
        // "accident" must not appear — it triggers the crash rule before bad road is checked
        let result = IncidentClassifier.classify(title: "Bad road ahead", summary: "Large pothole on the road causing damage.")
        #expect(result.category == .traffic)
        #expect(result.subtype == .badRoad)
        #expect(result.severity == .medium)
    }

    // Fire — Market Fire
    @Test func classifiesMarketFire() {
        let result = IncidentClassifier.classify(title: "Fire at market", summary: "Smoke and flames visible from the main shop area.")
        #expect(result.category == .fire)
        #expect(result.subtype == .marketFire)
        #expect(result.severity == .urgent)
    }

    // Fire — Building Fire (no market keyword)
    @Test func classifiesBuildingFire() {
        let result = IncidentClassifier.classify(title: "Building on fire", summary: "Smoke rising from the warehouse.")
        #expect(result.category == .fire)
        #expect(result.subtype == .buildingFire)
        #expect(result.severity == .urgent)
    }

    // Fire — Gas Leak
    @Test func classifiesGasLeak() {
        let result = IncidentClassifier.classify(title: "Gas leak reported", summary: "Strong gas smell near cylinder storage.")
        #expect(result.category == .fire)
        #expect(result.subtype == .gasLeak)
        #expect(result.severity == .urgent)
    }

    // Fire — Explosion
    @Test func classifiesExplosion() {
        let result = IncidentClassifier.classify(title: "Explosion heard", summary: "A loud blast shook nearby buildings.")
        #expect(result.category == .fire)
        #expect(result.subtype == .explosion)
        #expect(result.severity == .urgent)
    }

    // Medical — Emergency
    @Test func classifiesMedicalEmergency() {
        let result = IncidentClassifier.classify(title: "Man injured", summary: "Ambulance needed — person bleeding on the road.")
        #expect(result.category == .medical)
        #expect(result.subtype == .medicalEmergency)
        #expect(result.severity == .high)
    }

    // Medical — Suspected Outbreak
    @Test func classifiesSuspectedOutbreak() {
        let result = IncidentClassifier.classify(title: "Suspected cholera outbreak", summary: "Many sick residents near the estate.")
        #expect(result.category == .medical)
        #expect(result.subtype == .suspectedOutbreak)
        #expect(result.severity == .high)
    }

    // Weather — Flooding
    @Test func classifiesFlooding() {
        let result = IncidentClassifier.classify(title: "Flooding reported", summary: "Road is waterlogged and submerged.")
        #expect(result.category == .weather)
        #expect(result.subtype == .flooding)
        #expect(result.severity == .high)
    }

    // Weather — Storm
    @Test func classifiesStorm() {
        let result = IncidentClassifier.classify(title: "Heavy rain and storm", summary: "Wind damage expected across the area.")
        #expect(result.category == .weather)
        #expect(result.subtype == .stormDamage)
        #expect(result.severity == .medium)
    }

    // Utilities — Power Outage
    @Test func classifiesPowerOutage() {
        let result = IncidentClassifier.classify(title: "Power outage", summary: "Blackout — no light on the street since morning.")
        #expect(result.category == .utilities)
        #expect(result.subtype == .powerOutage)
        #expect(result.severity == .low)
    }

    // Utilities — Fuel Scarcity
    @Test func classifiesFuelScarcity() {
        let result = IncidentClassifier.classify(title: "Fuel queue at filling station", summary: "No fuel available, petrol queue stretching outside.")
        #expect(result.category == .utilities)
        #expect(result.subtype == .fuelScarcity)
        #expect(result.severity == .medium)
    }

    // Structure — Building Collapse
    @Test func classifiesBuildingCollapse() {
        let result = IncidentClassifier.classify(title: "Building collapse", summary: "Three-storey house collapsed this morning.")
        #expect(result.category == .structure)
        #expect(result.subtype == .buildingCollapse)
        #expect(result.severity == .urgent)
    }

    // Structure — Bridge Collapse
    @Test func classifiesBridgeCollapse() {
        let result = IncidentClassifier.classify(title: "Collapsed bridge", summary: "The pedestrian bridge collapsed.")
        #expect(result.category == .structure)
        #expect(result.subtype == .bridgeCollapse)
        #expect(result.severity == .urgent)
    }

    // Community — Missing Person
    @Test func classifiesMissingPerson() {
        let result = IncidentClassifier.classify(title: "Missing child", summary: "A missing person report filed for a 10-year-old.")
        #expect(result.category == .community)
        #expect(result.subtype == .missingPerson)
        #expect(result.severity == .high)
    }

    // Community — Safe Route
    @Test func classifiesSafeRoute() {
        let result = IncidentClassifier.classify(title: "Safe route available", summary: "Pass here to avoid the blocked area.")
        #expect(result.category == .community)
        #expect(result.subtype == .safeRoute)
        #expect(result.severity == .low)
    }

    // Default fallback
    @Test func classifiesUnknownAsDefault() {
        let result = IncidentClassifier.classify(title: "Something happened", summary: "Not sure what is going on.")
        #expect(result.category == .security)
        #expect(result.subtype == .suspiciousActivity)
        #expect(result.severity == .medium)
    }

    // Case-insensitivity
    @Test func classificationIsCaseInsensitive() {
        let lower = IncidentClassifier.classify(title: "gunshots heard", summary: "")
        let upper = IncidentClassifier.classify(title: "GUNSHOTS HEARD", summary: "")
        #expect(lower.category == upper.category)
        #expect(lower.subtype == upper.subtype)
    }

    // Traffic — Flooded Road (now distinct from weather flooding)
    @Test func classifiesFloodedRoad() {
        let result = IncidentClassifier.classify(title: "Flooded road ahead", summary: "Road is waterlogged and impassable.")
        #expect(result.category == .traffic)
        #expect(result.subtype == .floodedRoad)
    }

    // Bad road with accident keyword no longer misfires as crash
    @Test func badRoadWithAccidentWordClassifiesAsBadRoad() {
        let result = IncidentClassifier.classify(title: "Bad road", summary: "Pothole causing vehicles to swerve dangerously.")
        #expect(result.category == .traffic)
        #expect(result.subtype == .badRoad)
    }

    // "ceasefire" must not match the fire rule
    @Test func ceasefireDoesNotClassifyAsFire() {
        let result = IncidentClassifier.classify(title: "Ceasefire declared in the area", summary: "Calm restored after earlier clash.")
        #expect(result.category != .fire)
    }
}

// MARK: - IncidentStore

@Suite("IncidentStore")
struct IncidentStoreTests {

    // MARK: Seed Data

    @Test @MainActor func storeInitializesEmpty() {
        // Production store starts empty; real incidents arrive from the remote store.
        // (Sample data is DEBUG-only, via IncidentStore.preview.)
        let store = IncidentStore()
        #expect(store.incidents.isEmpty)
    }

    @Test @MainActor func activeIncidentsExcludesResolved() {
        let store = IncidentStore()
        #expect(store.activeIncidents.allSatisfy { $0.status != .resolved })
    }

    @Test @MainActor func activeIncidentsSortedByReportedAtDescending() {
        let store = IncidentStore()
        let active = store.activeIncidents
        let dates = active.map(\.reportedAt)
        #expect(dates == dates.sorted(by: >))
    }

    // MARK: addIncident

    @Test @MainActor func addIncidentAppendsToStore() {
        let store = IncidentStore()
        let initialCount = store.incidents.count
        store.addIncident(
            title: "Test Robbery",
            summary: "A robbery occurred.",
            category: .security,
            subtype: .armedRobbery,
            severity: .urgent,
            neighborhood: "Test Island",
            reporterCoordinate: CLLocationCoordinate2D(latitude: 6.5244, longitude: 3.3792)
        )
        #expect(store.incidents.count == initialCount + 1)
        #expect(store.incidents.last?.title == "Test Robbery")
    }

    @Test @MainActor func addIncidentSetsStatusToActive() {
        let store = IncidentStore()
        store.addIncident(
            title: "Fire alert",
            summary: "Fire spotted.",
            category: .fire,
            subtype: .buildingFire,
            severity: .urgent,
            neighborhood: "Marina",
            reporterCoordinate: nil
        )
        #expect(store.incidents.last?.status == .active)
    }

    @Test @MainActor func addIncidentLeavesCoordinateNilWhenNoLocation() {
        let store = IncidentStore()
        store.addIncident(
            title: "Power gone",
            summary: "Blackout.",
            category: .utilities,
            subtype: .powerOutage,
            severity: .low,
            neighborhood: "Yaba",
            reporterCoordinate: nil
        )
        let added = store.incidents.last!
        // No location shared → coordinate stays nil (no fabricated default pin).
        #expect(added.coordinate == nil)
    }

    @Test @MainActor func addIncidentFallsBackToNearbyAreaWhenNeighborhoodIsEmpty() {
        let store = IncidentStore()
        store.addIncident(
            title: "Something",
            summary: "Details.",
            category: .community,
            subtype: .localWarning,
            severity: .low,
            neighborhood: "",
            reporterCoordinate: nil
        )
        #expect(store.incidents.last?.neighborhood == "Nearby area")
    }

    @Test @MainActor func addIncidentCorrectedSubtypeWhenMismatch() {
        let store = IncidentStore()
        // Provide a subtype that belongs to .traffic but declare category .fire
        store.addIncident(
            title: "Mismatch",
            summary: "Subtype mismatch test.",
            category: .fire,
            subtype: .crash,   // .crash belongs to .traffic, not .fire
            severity: .medium,
            neighborhood: "Test",
            reporterCoordinate: nil
        )
        let added = store.incidents.last!
        #expect(added.subtype.category == .fire)
    }

    @Test @MainActor func addIncidentOffsetsPublicCoordinateFromExact() {
        let store = IncidentStore()
        let exact = CLLocationCoordinate2D(latitude: 6.5244, longitude: 3.3792)
        store.addIncident(
            title: "Offset test",
            summary: "",
            category: .community,
            subtype: .localWarning,
            severity: .low,
            neighborhood: "Test",
            reporterCoordinate: exact
        )
        let added = store.incidents.last!
        let pub = added.coordinate!
        let latDiff = abs(pub.latitude - exact.latitude)
        let lonDiff = abs(pub.longitude - exact.longitude)
        // Should differ (fuzzing applied), but stay within roughly 300 m
        #expect(latDiff > 0 || lonDiff > 0)
        #expect(latDiff < 0.005)   // ~550 m max latitude
        #expect(lonDiff < 0.005)
    }

    // MARK: incident(withID:)

    @Test @MainActor func incidentWithIDReturnsCorrectIncident() {
        let store = IncidentStore()
        guard let first = store.incidents.first else { return }
        let found = store.incident(withID: first.id)
        #expect(found == first)
    }

    @Test @MainActor func incidentWithIDReturnsNilForUnknownID() {
        let store = IncidentStore()
        #expect(store.incident(withID: UUID()) == nil)
    }

    // MARK: confirm

    @Test @MainActor func confirmIncrementsConfirmations() {
        let store = IncidentStore()
        guard let incident = store.incidents.first else { return }
        let before = incident.confirmations
        store.confirm(incident)
        let after = store.incident(withID: incident.id)!.confirmations
        #expect(after == before + 1)
    }

    // MARK: record(.seen)

    @Test @MainActor func recordSeenIncrementsConfirmations() {
        let store = IncidentStore()
        guard let incident = store.incidents.first else { return }
        let before = incident.confirmations
        store.record(.seen, for: incident)
        let after = store.incident(withID: incident.id)!.confirmations
        #expect(after == before + 1)
    }

    // MARK: record(.notSeen)

    @Test @MainActor func recordNotSeenIncrementsDisputes() {
        let store = IncidentStore()
        guard let incident = store.incidents.first else { return }
        let before = incident.disputes
        store.record(.notSeen, for: incident)
        let after = store.incident(withID: incident.id)!.disputes
        #expect(after == before + 1)
    }

    @Test @MainActor func recordNotSeenSetsWatchingWhenDisputesEqualConfirmations() {
        let store = IncidentStore()
        // New incidents start with 1 confirmation; disputes >= confirmations now triggers
        // watching, so one "not seen" is enough (disputes=1 >= confirmations=1).
        store.addIncident(
            title: "Low conf",
            summary: ".",
            category: .community,
            subtype: .localWarning,
            severity: .low,
            neighborhood: "Test",
            reporterCoordinate: nil
        )
        let added = store.incidents.last!
        #expect(added.confirmations == 1)
        store.record(.notSeen, for: added)
        let updated = store.incident(withID: added.id)!
        #expect(updated.status == .watching)
    }

    // MARK: record(.unsafe)

    @Test @MainActor func recordUnsafeIncrementsUnsafeReports() {
        let store = IncidentStore()
        guard let incident = store.incidents.first else { return }
        let before = incident.unsafeReports
        store.record(.unsafe, for: incident)
        let after = store.incident(withID: incident.id)!.unsafeReports
        #expect(after == before + 1)
    }

    @Test @MainActor func recordUnsafeElevatesSeverityToHighIfNotUrgent() {
        let store = IncidentStore()
        // Community cleanup — low severity
        store.addIncident(
            title: "Cleanup event",
            summary: ".",
            category: .community,
            subtype: .publicGathering,
            severity: .low,
            neighborhood: "Lekki",
            reporterCoordinate: nil
        )
        let added = store.incidents.last!
        store.record(.unsafe, for: added)
        let updated = store.incident(withID: added.id)!
        #expect(updated.severity == .high)
        #expect(updated.status == .active)
    }

    @Test @MainActor func recordUnsafeDoesNotDowngradeUrgentSeverity() {
        let store = IncidentStore()
        guard let urgentIncident = store.incidents.first(where: { $0.severity == .urgent }) else { return }
        store.record(.unsafe, for: urgentIncident)
        let updated = store.incident(withID: urgentIncident.id)!
        #expect(updated.severity == .urgent)
    }

    // MARK: record(.roadBlocked)

    @Test @MainActor func recordRoadBlockedIncrementsBlockedReports() {
        let store = IncidentStore()
        guard let incident = store.incidents.first else { return }
        let before = incident.blockedReports
        store.record(.roadBlocked, for: incident)
        let after = store.incident(withID: incident.id)!.blockedReports
        #expect(after == before + 1)
    }

    @Test @MainActor func recordRoadBlockedElevatesLowSeverityToMedium() {
        let store = IncidentStore()
        store.addIncident(
            title: "Power outage",
            summary: ".",
            category: .utilities,
            subtype: .powerOutage,
            severity: .low,
            neighborhood: "Yaba",
            reporterCoordinate: nil
        )
        let added = store.incidents.last!
        store.record(.roadBlocked, for: added)
        let updated = store.incident(withID: added.id)!
        #expect(updated.severity == .medium)
    }

    @Test @MainActor func recordRoadBlockedForTrafficIncidentElevatesFromLow() {
        let store = IncidentStore()
        store.addIncident(
            title: "Traffic jam",
            summary: ".",
            category: .traffic,
            subtype: .gridlock,
            severity: .low,
            neighborhood: "Lagos",
            reporterCoordinate: nil
        )
        let added = store.incidents.last!
        store.record(.roadBlocked, for: added)
        let updated = store.incident(withID: added.id)!
        #expect(updated.severity == .medium)
    }

    // MARK: record(.cleared)

    @Test @MainActor func recordClearedIncrementsClearedReports() {
        let store = IncidentStore()
        guard let incident = store.incidents.first else { return }
        let before = incident.clearedReports
        store.record(.cleared, for: incident)
        let after = store.incident(withID: incident.id)!.clearedReports
        #expect(after == before + 1)
    }

    @Test @MainActor func recordClearedSetsWatchingBeforeThreshold() {
        let store = IncidentStore()
        store.addIncident(
            title: "Watching",
            summary: ".",
            category: .community,
            subtype: .localWarning,
            severity: .low,
            neighborhood: "Test",
            reporterCoordinate: nil
        )
        let added = store.incidents.last!
        store.record(.cleared, for: added)    // 1 cleared
        store.record(.cleared, for: store.incident(withID: added.id)!)    // 2 cleared
        let updated = store.incident(withID: added.id)!
        #expect(updated.status == .watching)
    }

    @Test @MainActor func recordClearedResolvesAtThreeOrMore() {
        let store = IncidentStore()
        store.addIncident(
            title: "Will resolve",
            summary: ".",
            category: .community,
            subtype: .localWarning,
            severity: .low,
            neighborhood: "Test",
            reporterCoordinate: nil
        )
        let added = store.incidents.last!
        for _ in 1...3 {
            store.record(.cleared, for: store.incident(withID: added.id)!)
        }
        let updated = store.incident(withID: added.id)!
        #expect(updated.status == .resolved)
    }

    // MARK: markResolved

    @Test @MainActor func markResolvedSetsStatusToResolved() {
        let store = IncidentStore()
        guard let incident = store.incidents.first else { return }
        store.markResolved(incident)
        let updated = store.incident(withID: incident.id)!
        #expect(updated.status == .resolved)
    }

    @Test @MainActor func markResolvedAppendsUpdateEntry() {
        let store = IncidentStore()
        guard let incident = store.incidents.first else { return }
        let countBefore = incident.updates.count
        store.markResolved(incident)
        let updated = store.incident(withID: incident.id)!
        #expect(updated.updates.count == countBefore + 1)
        #expect(updated.updates[0].message.contains("resolved"))
    }

    // MARK: signal appends update

    @Test @MainActor func recordSignalAppendsUpdateEntry() {
        let store = IncidentStore()
        guard let incident = store.incidents.first else { return }
        let countBefore = incident.updates.count
        store.record(.seen, for: incident)
        let updated = store.incident(withID: incident.id)!
        #expect(updated.updates.count == countBefore + 1)
    }

    // MARK: resolved guard

    @Test @MainActor func recordSignalIgnoredOnResolvedIncident() {
        let store = IncidentStore()
        guard let incident = store.incidents.first else { return }
        store.markResolved(incident)
        let resolved = store.incident(withID: incident.id)!
        let updatesBefore = resolved.updates.count
        let confirmsBefore = resolved.confirmations
        store.record(.unsafe, for: resolved)
        let after = store.incident(withID: incident.id)!
        #expect(after.status == .resolved, "unsafe signal must not re-activate a resolved incident")
        #expect(after.updates.count == updatesBefore, "no update entry should be added")
        #expect(after.confirmations == confirmsBefore)
    }

    // MARK: URL safety

    @Test func googleMapsURLsNeverCrashOnValidCoordinate() {
        let incident = makeIncident()
        // These must not crash — previously force-unwrapped
        _ = incident.googleMapsAreaURL
        _ = incident.googleMapsDirectionsURL
    }
}
