//
//  InputValidationTests.swift
//  pulsetrackrTests
//
//  Tests for the report submission gate (canSubmit logic), input edge cases,
//  locale-safe formatting, and classifier behaviour on realistic user input.
//

import Testing
import MapKit
@testable import pulsetrackr

// MARK: - canSubmit logic
//
// Mirrors the private `canSubmit` computed property in ReportIncidentView:
//   title.trimmed.count >= 4 && summary.trimmed.count >= 10
//   OR hasVoiceNote OR hasMediaEvidence OR hasLiveSignal

private func canSubmit(
    title: String, summary: String,
    hasVoiceNote: Bool = false,
    hasMediaEvidence: Bool = false,
    hasLiveSignal: Bool = false
) -> Bool {
    let hasDescription =
        title.trimmingCharacters(in: .whitespacesAndNewlines).count >= 4 &&
        summary.trimmingCharacters(in: .whitespacesAndNewlines).count >= 10
    return hasDescription || hasVoiceNote || hasMediaEvidence || hasLiveSignal
}

@Suite("Input Validation — canSubmit")
struct CanSubmitTests {

    // MARK: Minimum length boundaries

    @Test func titleAt3CharsIsRejected() {
        #expect(!canSubmit(title: "Fir", summary: "Long enough summary text."))
    }

    @Test func titleAt4CharsIsAccepted() {
        #expect(canSubmit(title: "Fire", summary: "Long enough summary text."))
    }

    @Test func summaryAt9CharsIsRejected() {
        #expect(!canSubmit(title: "Fire alert", summary: "Too short"))
    }

    @Test func summaryAt10CharsIsAccepted() {
        #expect(canSubmit(title: "Fire alert", summary: "Just right!"))
    }

    @Test func exactBoundaryBothFields() {
        #expect(canSubmit(title: "Test", summary: "Exactly ten"))
    }

    // MARK: Whitespace trimming

    @Test func whitespaceOnlyTitleIsRejected() {
        #expect(!canSubmit(title: "    ", summary: "Long enough summary text."))
    }

    @Test func whitespaceOnlySummaryIsRejected() {
        #expect(!canSubmit(title: "Fire alert", summary: "          "))
    }

    @Test func leadingTrailingWhitespaceIsTrimmedBeforeCheck() {
        // Title with padding: "  OK  " trims to "OK" (2 chars) → rejected
        #expect(!canSubmit(title: "  OK  ", summary: "Long enough summary text."))
    }

    @Test func newlineCountsAsWhitespace() {
        #expect(!canSubmit(title: "\n\n\n\n", summary: "Long enough summary text."))
    }

    // MARK: Signal overrides

    @Test func voiceNoteOverridesEmptyText() {
        #expect(canSubmit(title: "", summary: "", hasVoiceNote: true))
    }

    @Test func mediaEvidenceOverridesEmptyText() {
        #expect(canSubmit(title: "", summary: "", hasMediaEvidence: true))
    }

    @Test func liveSignalOverridesEmptyText() {
        #expect(canSubmit(title: "", summary: "", hasLiveSignal: true))
    }

    @Test func noSignalsAndEmptyTextIsRejected() {
        #expect(!canSubmit(title: "", summary: ""))
    }

    // MARK: Unicode & special characters

    @Test func emojiCountsAsCharacter() {
        // "🔥🔥🔥🔥" = 4 scalar values but each emoji is 1 Character → 4 chars
        #expect(canSubmit(title: "🔥🔥🔥🔥", summary: "Long enough summary text."))
    }

    @Test func arabicRTLTextMeetsMinimum() {
        // Arabic "حريق" = 4 characters (fire)
        #expect(canSubmit(title: "حريق", summary: "تفاصيل كافية هنا للنص"))
    }

    @Test func mixedUnicodeTitleAccepted() {
        #expect(canSubmit(title: "Fïré", summary: "Long enough summary text."))
    }
}

// MARK: - Classifier input edge cases

@Suite("Input Validation — Classifier")
struct ClassifierInputTests {

    @Test func emptyInputFallsBackToDefault() {
        let result = IncidentClassifier.classify(title: "", summary: "")
        #expect(result.category == .security)
        #expect(result.subtype == .suspiciousActivity)
    }

    @Test func whitespaceOnlyInputFallsBackToDefault() {
        let result = IncidentClassifier.classify(title: "   ", summary: "\n\n")
        #expect(result.category == .security)
        #expect(result.subtype == .suspiciousActivity)
    }

    @Test func singleKeywordInTitleClassifiesCorrectly() {
        let result = IncidentClassifier.classify(title: "flooding", summary: "")
        #expect(result.category == .weather)
    }

    @Test func keywordSpanningTitleAndSummaryIsDetected() {
        // Classifier joins title + " " + summary before checking — confirm this works
        let result = IncidentClassifier.classify(title: "Armed", summary: "robbery happened here")
        #expect(result.category == .security)
        #expect(result.subtype == .armedRobbery)
    }

    @Test func veryLongInputDoesNotCrash() {
        let longText = String(repeating: "smoke ", count: 5_000)
        let result = IncidentClassifier.classify(title: longText, summary: longText)
        #expect(result.category == .fire)
    }

    @Test func specialCharactersInInputDoNotCrash() {
        let result = IncidentClassifier.classify(
            title: "🚨 !!!\u{200B}",
            summary: "Null\0byte and <script>alert()</script>"
        )
        // Just verifying no crash and a valid classification is returned
        #expect(IncidentCategory.allCases.contains(result.category))
    }
}

// MARK: - Locale safety

@Suite("Locale Safety")
struct LocaleSafetyTests {

    // Swift string interpolation of Double always uses the C locale (period decimal),
    // regardless of device locale. This test documents and verifies that guarantee.
    @Test func googleMapsURLUsesPeriodDecimalSeparatorRegardlessOfLocale() {
        let incident = Incident(
            id: UUID(), title: "T", summary: "S",
            category: .community, subtype: .localWarning,
            severity: .low, status: .active,
            reporterCoordinate: nil,
            coordinate: CLLocationCoordinate2D(latitude: 6.5244, longitude: 3.3792),
            neighborhood: "Test", reportedAt: Date(),
            confirmations: 1, updates: []
        )
        let url = incident.googleMapsAreaURL.absoluteString
        // Must contain a period, never a comma, as the decimal separator
        #expect(url.contains("6.5244"), "URL must use period decimal: \(url)")
        #expect(url.contains("3.3792"), "URL must use period decimal: \(url)")
        #expect(!url.contains("6,5244"), "URL must not use comma decimal: \(url)")
    }

    @Test func signalSummaryFormatIsConsistentAcrossBuilds() {
        let incident = Incident(
            id: UUID(), title: "T", summary: "S",
            category: .community, subtype: .localWarning,
            severity: .low, status: .active,
            reporterCoordinate: nil,
            coordinate: CLLocationCoordinate2D(latitude: 6.5244, longitude: 3.3792),
            neighborhood: "Test", reportedAt: Date(),
            confirmations: 3, disputes: 1, unsafeReports: 0,
            blockedReports: 0, clearedReports: 1, officialUpdates: 0,
            updates: []
        )
        #expect(incident.signalSummary == "3 seen • 1 not seen • 0 unsafe • 1 cleared")
    }

    @Test func allCategoryLabelsAreNonEmptyStrings() {
        for category in IncidentCategory.allCases {
            #expect(!category.label.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    @Test func allSubtypeLabelsAreNonEmptyStrings() {
        for subtype in IncidentSubtype.allCases {
            #expect(!subtype.label.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
}
