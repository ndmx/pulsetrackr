# PulseTrackr App Store Submission Checklist

Last updated: 2026-05-30

## App Store Connect URLs

Use these public URLs in App Store Connect:

| Field | URL |
| --- | --- |
| Marketing URL | `https://edentv.us/pages/pulsetrackr.html` |
| Support URL | `https://edentv.us/docs/pulsetrackr-support.html` |
| Privacy Policy URL | `https://edentv.us/docs/pulsetrackr-privacy.html` |
| User Privacy Choices URL | `https://edentv.us/docs/pulsetrackr-privacy.html#choices` |
| Terms / EULA URL | `https://edentv.us/docs/pulsetrackr-terms.html` |

Apple currently requires a privacy policy URL for iOS apps, and the iOS version metadata requires a support URL. The privacy choices URL is optional, but include it because PulseTrackr already has a deletion/privacy choices section.

## App Metadata

| Field | Value |
| --- | --- |
| App name | PulseTrackr |
| Bundle ID | `org.pulsetracker.pulsetrackr.pulsetrackr` |
| Version | `1.0` |
| Build | `7` |
| Minimum iOS | `17.0` |
| Category | Navigation or Utilities |
| Content rights | PulseTrackr owns or has rights to included app content |
| Encryption export compliance | Uses standard HTTPS/TLS through Apple/Firebase/Mapbox SDK networking; no custom encryption |

Suggested subtitle, if available:

> Local safety alerts

Suggested promotional text:

> Share and verify nearby safety reports, send SOS updates to trusted contacts, and keep movement decisions grounded in live local context.

Suggested review notes:

> PulseTrackr is a local safety and incident reporting app. Testers can create community reports, verify or dispute reports, hide/report objectionable reports, and configure SOS trusted contacts. The app does not contact police, ambulance, or emergency services; SOS only notifies user-selected trusted contacts. Community incident locations shown publicly are privacy-offset from the reporter's precise location.

## Privacy Manifest

The app target now includes `app/PrivacyInfo.xcprivacy`, and the simulator build placed it at:

`pulsetrackr.app/PrivacyInfo.xcprivacy`

Declared required-reason API:

| API category | Reason |
| --- | --- |
| UserDefaults | `CA92.1` |

Declared tracking:

| Field | Value |
| --- | --- |
| Tracking | No |
| Tracking domains | None |

## App Privacy Answers

Answer App Store Connect privacy questions inclusively for the app and integrated SDKs. PulseTrackr directly uses Firebase and Mapbox, so third-party SDK data practices should be included.

Recommended collected data disclosures:

| Data type | Linked to user | Tracking | Purpose |
| --- | --- | --- | --- |
| Precise location | Yes | No | App Functionality |
| Coarse location | Yes | No | App Functionality |
| Contacts | Yes | No | App Functionality |
| Photos or videos | Yes | No | App Functionality |
| Audio data | Yes | No | App Functionality |
| Other user content | Yes | No | App Functionality |
| User ID | Yes | No | App Functionality |
| Diagnostics / crash or other diagnostic data | Yes | No | App Functionality |
| Product interaction / analytics, if prompted by SDK manifests | Yes | No | Analytics and App Functionality |

Notes for the reviewer/privacy form:

- Precise location is used for SOS and local incident relevance.
- Public incident locations are offset before sharing to reduce exact-location exposure.
- Trusted contacts are stored locally; SOS contact destinations are not exposed in redacted diagnostics.
- Photos, videos, audio, and text are user-submitted evidence for safety reports.
- No third-party advertising tracking is intended.
- PulseTrackr uses Firebase anonymous auth and stores server records under the anonymous UID for ownership, moderation, and abuse controls. Treat the listed data as linked unless the backend is redesigned to strip that UID before collection and prevent re-linkage.

## User-Generated Content Readiness

PulseTrackr has user-generated community reports, so the submission should emphasize safety controls:

| Requirement area | Implementation |
| --- | --- |
| Filter objectionable material | Report validation, category/subtype constraints, backend rate limits, and private moderation signal flow |
| Report objectionable content | Incident detail screen has "Report or hide this" with moderation reasons |
| Timely response path | Support and privacy pages publish contact information |
| Block or hide abuse | User can hide a reported incident locally; backend stores private concern reports for moderation |

Backend moderation endpoint added:

`record_incident_concern`

Concern reasons:

- `false_report`
- `offensive_content`
- `private_information`
- `dangerous_advice`
- `spam_or_abuse`

Deploy before App Review:

```sh
firebase deploy --only functions:record_incident_concern,firestore:rules
```

If deploying all backend updates for the current branch, use the broader project deploy command from `FIREBASE_SETUP.md`.

## Pre-Submission Verification

Completed locally on 2026-05-30:

```sh
plutil -lint app/PrivacyInfo.xcprivacy
cd functions && npm run lint && npm test
xcodebuild test -project pulsetrackr.xcodeproj -scheme pulsetrackr -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 -resultBundlePath build/Test-pulsetrackr-approval-20260530-0615.xcresult
```

Results:

- Privacy manifest lint passed.
- Functions lint and Node tests passed.
- iOS test suite passed: 198 tests in 21 suites.

## Remaining Before Upload

- Deploy the new callable function and Firestore rules.
- Increment build number if build `7` was already uploaded to App Store Connect.
- Archive a Release build in Xcode or with `xcodebuild archive`.
- Upload to TestFlight and wait for Apple processing.
- Re-check App Store Connect privacy labels against SDK-provided privacy manifests during upload.
- Add screenshots for all required device sizes.
