//
//  ClassifierNigerianTests.swift
//  pulsetrackrTests
//
//  Coverage for Nigerian/Pidgin phrasing and combination handling added to
//  IncidentClassifier, plus word-boundary matching guards.
//

import Testing
@testable import pulsetrackr

@Suite("Classifier — Nigerian phrasing")
struct ClassifierNigerianTests {

    private func classify(_ text: String) -> IncidentClassification {
        IncidentClassifier.classify(title: text, summary: "")
    }

    // MARK: Fire (incl. mall/plaza combination)

    @Test func mallBurningIsBuildingFire() {
        let r = classify("mall burning in ikeja")
        #expect(r.category == .fire)
        #expect(r.subtype == .buildingFire)
        #expect(r.severity == .urgent)
    }

    @Test func plazaOnFireIsBuildingFire() {
        let r = classify("plaza on fire on lagos island")
        #expect(r.subtype == .buildingFire)
    }

    @Test func mallDeyBurnIsBuildingFire() {
        #expect(classify("the mall dey burn").subtype == .buildingFire)
    }

    @Test func fireOutbreakAtShoppingComplexIsBuildingFire() {
        // "shopping complex" must not be pulled into market fire by the "shop" prefix.
        #expect(classify("fire outbreak at shopping complex").subtype == .buildingFire)
    }

    @Test func actualMarketFireStaysMarketFire() {
        #expect(classify("market dey burn for oshodi").subtype == .marketFire)
    }

    // MARK: Structural

    @Test func buildingDonCollapse() {
        let r = classify("building don collapse for kubwa")
        #expect(r.category == .structure)
        #expect(r.subtype == .buildingCollapse)
    }

    @Test func structuralFailureIsCollapse() {
        #expect(classify("structural failure reported in a high-rise").subtype == .buildingCollapse)
    }

    @Test func cracksInBuildingIsUnsafeBuilding() {
        let r = classify("cracks in wall, dilapidated building")
        #expect(r.category == .structure)
        #expect(r.subtype == .unsafeBuilding)
    }

    // MARK: Traffic / utilities / medical / security Pidgin

    @Test func goSlowIsGridlock() {
        #expect(classify("serious go slow for third mainland").subtype == .gridlock)
    }

    @Test func phcnTookLightIsPowerOutage() {
        let r = classify("PHCN don take light since morning")
        #expect(r.category == .utilities)
        #expect(r.subtype == .powerOutage)
    }

    @Test func personDeyBleedIsMedical() {
        #expect(classify("person dey bleed for road side").subtype == .medicalEmergency)
    }

    @Test func gbomoGbomoIsKidnapping() {
        #expect(classify("gbomo gbomo spotted around the park").subtype == .kidnapping)
    }

    // MARK: Word-boundary guards (no embedded-word false positives)

    @Test func ceasefireIsNotFire() {
        #expect(classify("ceasefire announced").category != .fire)
    }

    @Test func stemmingStillWorks() {
        // Prefix/word-boundary matching must still catch inflected forms.
        #expect(classify("kidnapping reported").subtype == .kidnapping)
        #expect(classify("vehicles collided in a collision").subtype == .crash)
    }
}
