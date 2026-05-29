# PulseTrackr Firebase Setup

PulseTrackr can use the existing PulseTrack Firebase project while keeping safety data isolated in its own collections.

## Live project status

The workspace is connected to Firebase project `pulsetracker-0000`.

- The iOS app `pulsetrackr` is registered with bundle id `org.pulsetracker.pulsetrackr.pulsetrackr`.
- `app/GoogleService-Info.plist` is **git-ignored** and supplied locally by each developer (see [Local config](#local-config-googleservice-infoplist)). The Xcode target still bundles it from disk at build time. A committed `app/GoogleService-Info.plist.example` documents the expected structure.
- Firebase Authentication is initialized and Anonymous sign-in is enabled.
- The default Firestore database exists.
- Firebase Storage is configured in code for incident photo/audio evidence, but the project bucket must be initialized in the Firebase Console before Storage rules can deploy.
- `.firebaserc` maps `default` and `production` to `pulsetracker-0000`.
- SOS Functions use the separate Firebase Functions codebase `pulsetrackr-sos` so deploying this repo does not reconcile/delete the project’s existing Python functions.

## iOS app setup

These steps are already complete for `pulsetracker-0000`:

1. Firebase iOS app for bundle id:

   ```text
   org.pulsetracker.pulsetrackr.pulsetrackr
   ```

2. `GoogleService-Info.plist` downloaded into `app/`.
3. Anonymous Auth enabled.

### Local config (`GoogleService-Info.plist`)

The live plist is git-ignored, so a fresh checkout needs it added before the app
will build:

1. Firebase Console → **Project settings** → **Your apps** → the iOS app
   (`org.pulsetracker.pulsetrackr.pulsetrackr`) → download `GoogleService-Info.plist`.
2. Save it as `app/GoogleService-Info.plist` (drop the `.example` suffix).

The `API_KEY` inside this file is **not a true secret** — it ships inside every
copy of the app binary and is extractable. Hiding it from git only quiets secret
scanners; it provides no runtime protection. The real controls are:

- **Restrict the API key** in Google Cloud Console → *APIs & Services* →
  *Credentials* → set *Application restrictions* to this iOS bundle id and
  *API restrictions* to only the Firebase APIs the app uses.
- **Lock down Security Rules** (Firestore + Storage) — see below.

Because the key is non-sensitive, the historical commit that contained it does
not require a git-history rewrite or key rotation. Just keep the key restricted.

Install and deploy the backend from this repo, or merge these files into the shared PulseTrack Firebase project:

```sh
cd /Users/ndmx0/Codehub/DEV/pulsetrackr/functions
npm install
npm test
npm run lint
cd ..
firebase deploy --only functions,firestore:rules,firestore:indexes,storage
```

Without `GoogleService-Info.plist`, the iOS app starts with an empty incident list and should not attempt SOS remote calls. (Sample incidents exist only in `#if DEBUG` builds for SwiftUI previews — they are never shown in release builds.) Once the plist is present, it reads from `safety_incidents_public`, submits through the callable `submit_incident` Cloud Function, and can opt into the SOS callable contract below.

## Firebase Storage setup

Incident photo and voice evidence uploads use Firebase Storage paths under:

```text
incident_reports/{uid}/{client_ref}/{file}
```

Before deploying Storage rules for the first time:

1. Open Firebase Console for `pulsetracker-0000`.
2. Go to **Storage**.
3. Click **Get Started** and create the default bucket.
4. Deploy rules:

   ```sh
   firebase deploy --only storage --project pulsetracker-0000
   ```

Rules allow authenticated users to create image/audio files only under their own UID path, capped at 10 MB. Reads are limited to the same authenticated owner. The callable `submit_incident` validates that evidence metadata points back to the signed-in reporter’s Storage path before writing private/public incident records.

## Geo-bounded incident feed

To scale across all App Store regions, the app does **not** stream every public
incident worldwide. Instead:

- **Write side** — `submit_incident` stores a standard geohash on each
  `safety_incidents_public` doc via [`functions/src/geohash.js`](functions/src/geohash.js)
  (`geohash` field, precision 9). This is byte-for-byte compatible with the client
  encoder in `app/Geohash.swift`.
- **Read side** — the client (`SafetyIncidentRemoteStore.observeIncidents(near:radiusMeters:)`)
  picks a geohash precision sized to the user's watch radius, then attaches one
  listener per covering cell (the cell containing the user plus its 8 neighbours)
  as `geohash` prefix-range queries. Results are merged, filtered to the exact
  radius + active statuses, and de-duplicated on the client. It re-subscribes when
  the user moves >500 m or changes their watch radius.
- **Index** — the query orders by the single `geohash` field, which Firestore
  indexes automatically. No composite index is required, so `firestore.indexes.json`
  needs no change for this feature.
- **Backfill** — incidents written *before* this change have no `geohash` field and
  will be skipped by geo-queries. Pre-launch this is typically a non-issue (the app
  ships with no real public incidents). If you have existing public docs, run a
  one-off backfill that reads each doc's `latitude`/`longitude` and sets
  `geohash = encodeGeohash(lat, lng)` using the same module.

The geohash encoder/neighbour logic is unit-tested on both sides
(`pulsetrackrTests/GeohashTests.swift`, `functions/test/geohash.test.js`). The
**end-to-end query path** (geohash-on-write + prefix-range queries returning nearby
incidents and excluding far ones) is validated against the Firestore emulator:

```sh
cd functions
npm run test:geo
```

This wraps `functions/test/geoQuery.emulator.js` in `firebase emulators:exec`,
seeds incidents at known distances (Lagos centre, ~11 km edge, New York), and
asserts the 3 km query returns only the nearby active incidents, the 15 km query
pulls in the edge incident, and another continent / resolved incidents are always
excluded. Requires the Firebase CLI and a JRE (for the Firestore emulator).

## Production notification secrets

The SOS backend has real provider adapters, but no secrets are committed. Configure these in Firebase Functions before live deployment:

```sh
firebase functions:secrets:set TWILIO_ACCOUNT_SID
firebase functions:secrets:set TWILIO_API_KEY_SID
firebase functions:secrets:set TWILIO_API_KEY_SECRET
firebase functions:secrets:set TWILIO_FROM_NUMBER
firebase functions:secrets:set SENDGRID_API_KEY
firebase functions:secrets:set SENDGRID_FROM_EMAIL
```

For local emulator testing, copy `functions/.secret.example` values into the private ignored `functions/.secret.local`; copy `functions/.env.example` into `functions/.env.local` only for non-secret local overrides such as `TWILIO_VOICE_TWIML` or `SENDGRID_FROM_NAME`. Never commit provider credentials. `TWILIO_AUTH_TOKEN` remains supported only as a local migration fallback; production should use `TWILIO_API_KEY_SID` and `TWILIO_API_KEY_SECRET`.

Delivery behavior:

- `sms` and `phone_call` use Twilio.
- `email` uses SendGrid.
- If a provider is not configured, the backend writes `provider_unconfigured` to `sos_notification_attempts_private` instead of pretending the alert was sent.
- If a provider returns an error, the attempt is marked `failed` with a capped error message for operations review.

Provider-specific setup:

- Twilio SMS/voice: configure `TWILIO_ACCOUNT_SID`, `TWILIO_API_KEY_SID`, `TWILIO_API_KEY_SECRET`, and `TWILIO_FROM_NUMBER`.
- SendGrid email: see `SENDGRID_SETUP.md` for sender verification, Mail Send API key permissions, and local/Firebase secret setup.
- App Check: see `APP_CHECK_SETUP.md` for iOS provider setup, debug token handling, and Firebase-side registration.

## Local emulator setup

Run the backend locally before shipping any SOS behavior:

```sh
cd /Users/ndmx0/Codehub/DEV/pulsetrackr/functions
npm install
npm test
cd ..
firebase emulators:start --project pulsetrackr-dev --only auth,functions,firestore
```

The Functions emulator serves callable functions at the local Firebase project. For iOS emulator/device testing, configure the app to use Firebase emulators in a debug-only code path before calling `SOSRemoteStore`; do not ship emulator hosts in production builds.

Production callable functions enforce Firebase App Check by default. The emulator disables App Check enforcement through `FUNCTIONS_EMULATOR=true`.

## Firestore collections

- `safety_reports_private`: exact raw reports, server-only.
- `safety_incidents_public`: public map/feed incidents, readable by clients.
- `safety_incident_signals`: reserved for the next milestone.
- `sos_sessions_private`: active and resolved SOS session records, server-only. Stores exact locations, recent trail snapshots, trusted-contact notification targets, redacted trusted-contact summaries, device/network metadata, status, activation/resolution timestamps, TTL, and access-expiry timestamps.
- `sos_location_updates_private`: append-only live SOS location updates keyed by `session_id` + `sequence_number`, server-only, with TTL cleanup after retention expires.
- `sos_notification_attempts_private`: trusted-contact notification attempts. The backend writes queued attempts, tries Twilio/SendGrid delivery when configured, then updates each record with `sent`, `failed`, or `provider_unconfigured`.
- `sos_idempotency_private`: maps user + `client_session_id` to the canonical server `session_id`.
- `sos_rate_limits_private`: per-user activation windows and cooldowns.
- `sos_access_grants_private`: short-lived privileged access grants for authorized responder/admin workflows.
- `sos_access_audit`: append-only audit events for admin, care-team, and law-enforcement access attempts.

## SOS callable functions

The iOS app should call these only through `SOSRemoteStore.makeIfConfigured()` so local/dev builds without Firebase keep working.

### `activate_sos`

Creates an active SOS session and asks the backend to notify trusted contacts. The app does not send SMS directly.

Server behavior:

- Requires Firebase Auth.
- Enforces App Check outside the emulator.
- Uses `client_session_id` for idempotency, so retrying the same activation returns the same `session_id`.
- Rate-limits activation per user with a short cooldown and hourly window.
- Caps recent trail sharing again on the server, even if the client sends more.
- Writes a private SOS session, idempotency record, audit event, and notification attempts.
- Attempts Twilio/SendGrid delivery after the session transaction commits, then updates notification status and the session `notificationSummary`.

Request fields:

- `client_session_id`: UUID generated on device for idempotency.
- `activated_at`: ISO-8601 timestamp from the device.
- `last_known_location`: exact location snapshot `{ latitude, longitude, horizontal_accuracy_meters?, altitude_meters?, speed_meters_per_second?, course_degrees?, captured_at }`.
- `recent_trail`: privacy-capped array of recent location snapshots.
- `direction_of_travel`: optional `{ bearing_degrees, speed_meters_per_second?, computed_from_point_count }`.
- `trusted_contacts_to_notify`: local trusted contacts selected for backend notification. Treat phone/email values as private and store only in server-only records.
- `device`: optional battery, low-power-mode, app version, build number, device model, system version, network status/interface metadata.
- `privacy`: client policy values such as trail point limit, trail age, live update interval, and privileged access constraints.

Response fields:

- `session_id`: server canonical session id.
- `trusted_contacts_notified`: contact UUID strings accepted for notification attempt.
- `expires_at`: ISO-8601 timestamp when active-session privileged access expires unless renewed by policy.

### `append_sos_location`

Appends one live location update for an active SOS session.

Server behavior:

- Requires Firebase Auth/App Check.
- Requires session ownership, active status, and unexpired access window.
- Uses `session_id + sequence_number` as an idempotent update key.
- Updates the session last-known position and writes an append-only update record.

Request fields:

- `session_id`
- `location`
- `sequence_number`
- `captured_at`
- `direction_of_travel`
- `device`

The function should reject updates for resolved or expired sessions.

### `resolve_sos`

Marks an SOS session resolved without implying emergency dispatch occurred.

Server behavior:

- Requires Firebase Auth/App Check.
- Requires the caller to own the session.
- Accepts only `user_resolved`, `false_alarm`, `timed_out`, or `transferred_to_care_team`.
- Is idempotent for already-resolved sessions and still writes an audit event.

Request fields:

- `session_id`
- `resolution_reason`: `user_resolved`, `false_alarm`, `timed_out`, or `transferred_to_care_team`.
- `resolved_at`
- `final_location`

### `request_sos_session_access`

Returns minimum exact SOS data to approved responder/admin users during active sessions only.

Request fields:

- `session_id`
- `reason`: human-readable incident/case reason for audit.

Server behavior:

- Requires Firebase Auth/App Check.
- Requires one of these custom claims: `sosAdmin`, `careTeam`, or `lawEnforcement`.
- Rejects inactive, expired, or missing sessions.
- Creates a short-lived access grant, writes `sos_access_audit`, and returns last known location, direction of travel, and redacted trusted-contact summaries.
- Does not return full trusted-contact destinations through this endpoint.

## Admin and law-enforcement access

SOS data contains exact live location and trusted-contact information. Access must be audited, time-limited, and limited to active SOS sessions unless a separate legal/retention process exists outside the mobile app flow.

- Do not expose `sos_sessions_private` or `sos_location_updates_private` to client Firestore reads.
- Require a privileged backend function or admin console role for access.
- Verify the session is active before returning exact live SOS data.
- Return only the minimum fields needed for the request.
- Write every access attempt to `sos_access_audit` with actor id, role, reason, session id, timestamp, decision, and expiry.
- Do not claim or trigger automatic law-enforcement dispatch from the iOS app. The backend may provide audited, time-limited access for authorized responders during an active SOS session.

## Privileged access claims

Responder/admin access is controlled with Firebase Auth custom claims. Use a service account with Auth admin permissions:

```sh
cd /Users/ndmx0/Codehub/DEV/pulsetrackr/functions
GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json \
  npm run set-sos-claim -- --uid USER_UID --role careTeam --project pulsetracker-0000
```

Allowed roles:

- `sosAdmin`
- `careTeam`
- `lawEnforcement`

To remove access:

```sh
GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json \
  npm run set-sos-claim -- --uid USER_UID --role careTeam --enable false --project pulsetracker-0000
```

After claims change, the affected user must refresh their Firebase ID token before calling `request_sos_session_access`.
