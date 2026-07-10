//
//  DeepLinkRouterTests.swift
//  pulsetrackrTests
//
//  Matrix coverage for custom-scheme and universal-link deep-link parsing.
//

import Foundation
import Testing
@testable import pulsetrackr

@Suite("DeepLinkRouter")
struct DeepLinkRouterTests {

    // MARK: - Valid destinations

    @Test func validCustomSchemeIncidentURL() {
        let url = URL(string: "pulsetrackr://incident/abc123")!
        #expect(DeepLinkRouter.destination(for: url) == .incident(id: "abc123"))
    }

    @Test func validHTTPSUniversalLink() {
        let url = URL(string: "https://share.example.com/i/inc-42")!
        #expect(DeepLinkRouter.destination(for: url) == .incident(id: "inc-42"))
    }

    @Test func idWithAllowedPunctuation() {
        let url = URL(string: "pulsetrackr://incident/aB_9-Zz")!
        #expect(DeepLinkRouter.destination(for: url) == .incident(id: "aB_9-Zz"))
    }

    @Test func emptyAllowedHostsAcceptsAnyHTTPSHost() {
        // allowedHosts starts empty and should accept any host for https /i/{id}.
        let url = URL(string: "https://totally-unknown.host/i/okid")!
        #expect(DeepLinkRouter.destination(for: url) == .incident(id: "okid"))
    }

    // MARK: - Rejected ids

    @Test func emptyIdIsRejected() {
        let custom = URL(string: "pulsetrackr://incident/")!
        let universal = URL(string: "https://example.com/i/")!
        #expect(DeepLinkRouter.destination(for: custom) == nil)
        #expect(DeepLinkRouter.destination(for: universal) == nil)
    }

    @Test func idLongerThan128IsRejected() {
        let longID = String(repeating: "a", count: 129)
        let url = URL(string: "pulsetrackr://incident/\(longID)")!
        #expect(DeepLinkRouter.destination(for: url) == nil)
    }

    @Test func idAt128CharsIsAccepted() {
        let maxID = String(repeating: "b", count: 128)
        let url = URL(string: "https://example.com/i/\(maxID)")!
        #expect(DeepLinkRouter.destination(for: url) == .incident(id: maxID))
    }

    @Test func idWithSlashIsRejected() {
        // Extra path component from an embedded slash.
        let url = URL(string: "pulsetrackr://incident/foo/bar")!
        #expect(DeepLinkRouter.destination(for: url) == nil)
    }

    @Test func idWithSpacesIsRejected() {
        let url = URL(string: "https://example.com/i/foo%20bar")!
        #expect(DeepLinkRouter.destination(for: url) == nil)
    }

    @Test func idWithPercentEncodingTricksIsRejected() {
        // Encoded slash becomes an extra path segment after URL parsing.
        let encodedSlash = URL(string: "https://example.com/i/foo%2Fbar")!
        #expect(DeepLinkRouter.destination(for: encodedSlash) == nil)

        // Encoded percent and other disallowed characters in the decoded id.
        let encodedJunk = URL(string: "pulsetrackr://incident/ab%25cd")!
        #expect(DeepLinkRouter.destination(for: encodedJunk) == nil)
    }

    // MARK: - Path / scheme rejections

    @Test func wrongPathPrefixIsRejected() {
        let url = URL(string: "https://example.com/x/abc123")!
        #expect(DeepLinkRouter.destination(for: url) == nil)
    }

    @Test func extraPathComponentsAreRejected() {
        let custom = URL(string: "pulsetrackr://incident/abc/extra")!
        let universal = URL(string: "https://example.com/i/abc/extra")!
        #expect(DeepLinkRouter.destination(for: custom) == nil)
        #expect(DeepLinkRouter.destination(for: universal) == nil)
    }

    @Test func httpSchemeIsRejectedForUniversalLinks() {
        let url = URL(string: "http://example.com/i/abc123")!
        #expect(DeepLinkRouter.destination(for: url) == nil)
    }

    @Test func unrelatedCustomSchemeIsRejected() {
        let url = URL(string: "otherapp://incident/abc123")!
        #expect(DeepLinkRouter.destination(for: url) == nil)
    }

    @Test func customSchemeWithWrongHostIsRejected() {
        let url = URL(string: "pulsetrackr://alerts/abc123")!
        #expect(DeepLinkRouter.destination(for: url) == nil)
    }
}
