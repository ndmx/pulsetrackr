# PulseTrackr Firebase Setup

PulseTrackr can use the existing PulseTrack Firebase project while keeping safety data isolated in its own collections.

## iOS app setup

1. In the Firebase console, add an iOS app for bundle id:

   ```text
   org.pulsetracker.pulsetrackr.pulsetrackr
   ```

2. Download `GoogleService-Info.plist`.
3. Add it to the Xcode app target without committing secrets/config you do not want in git.
4. Enable Anonymous Auth in Firebase Authentication.
5. Deploy the backend changes from the PulseTrack webapp repo:

   ```sh
   cd /Users/ndmx0/PROD/shipped/PulseTrack
   firebase deploy --only functions,firestore:rules
   ```

Without `GoogleService-Info.plist`, the iOS app keeps using local seed incidents. Once the plist is present, it reads from `safety_incidents_public` and submits through the callable `submit_incident` Cloud Function.

## Firestore collections

- `safety_reports_private`: exact raw reports, server-only.
- `safety_incidents_public`: public map/feed incidents, readable by clients.
- `safety_incident_signals`: reserved for the next milestone.
