//
//  IncidentShareCardTests.swift
//  pulsetrackrTests
//
//  Share URL composition, deep-link round-trip, and card render size.
//

import Foundation
import MapKit
import Testing
import UIKit
@testable import pulsetrackr

@Suite("IncidentShareCard")
struct IncidentShareCardTests {

    @Test func shareURLUsesRemoteDocumentIDWhenPresent() {
        var incident = makeShareFixture()
        incident.remoteDocumentID = "remote-doc-42"

        let url = ShareConfig.shareURL(for: incident)
        #expect(url != nil)
        #expect(url?.absoluteString == "https://pulsetrackr.example/i/remote-doc-42")
        #expect(url?.path == "/i/remote-doc-42")
    }

    @Test func shareURLFallsBackToLowercasedUUID() {
        let id = UUID(uuidString: "A1B2C3D4-E5F6-7890-ABCD-EF1234567890")!
        var incident = makeShareFixture(id: id)
        incident.remoteDocumentID = nil

        let url = ShareConfig.shareURL(for: incident)
        #expect(url != nil)
        #expect(url?.absoluteString == "https://pulsetrackr.example/i/a1b2c3d4-e5f6-7890-abcd-ef1234567890")
        #expect(url?.lastPathComponent == id.uuidString.lowercased())
    }

    @Test func shareURLRoundTripsThroughDeepLinkRouter() throws {
        var incident = makeShareFixture()
        incident.remoteDocumentID = "inc_share_abc"

        let url = try #require(ShareConfig.shareURL(for: incident))
        #expect(DeepLinkRouter.destination(for: url) == .incident(id: "inc_share_abc"))

        let localID = UUID()
        var localOnly = makeShareFixture(id: localID)
        localOnly.remoteDocumentID = nil
        let localURL = try #require(ShareConfig.shareURL(for: localOnly))
        #expect(DeepLinkRouter.destination(for: localURL) == .incident(id: localID.uuidString.lowercased()))
    }

    @Test @MainActor
    func renderReturnsNonNilImageOfExpectedPixelSize() throws {
        #if DEBUG
        let seed = Incident.seedIncidents[0]
        let image = IncidentShareCard.render(incident: seed)
        #else
        let image = IncidentShareCard.render(incident: makeShareFixture())
        #endif

        let rendered = try #require(image)
        // 600×315 pt @ scale 2 → 1200×630 px
        #expect(rendered.scale == 2)
        #expect(abs(rendered.size.width - 600) < 0.5)
        #expect(abs(rendered.size.height - 315) < 0.5)
        if let cgImage = rendered.cgImage {
            #expect(cgImage.width == 1200)
            #expect(cgImage.height == 630)
        }
    }
}

// MARK: - Fixtures

private func makeShareFixture(id: UUID = UUID()) -> Incident {
    Incident(
        id: id,
        remoteDocumentID: nil,
        title: "Share card test incident",
        summary: "Fixture for share URL and card render tests.",
        category: .security,
        subtype: .armedRobbery,
        severity: .urgent,
        status: .active,
        reporterCoordinate: nil,
        coordinate: CLLocationCoordinate2D(latitude: 6.5244, longitude: 3.3792),
        neighborhood: "Lagos Island",
        reportedAt: Date().addingTimeInterval(-12 * 60),
        confirmations: 5,
        updates: []
    )
}
