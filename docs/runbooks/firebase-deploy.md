# Firebase Deploy Runbook

## Verify Locally

```sh
cd /Users/ndmx0/Codehub/DEV/pulsetrackr/packages/contract
npm run codegen

cd /Users/ndmx0/Codehub/DEV/pulsetrackr/functions
npm test
npm run test:rules

cd /Users/ndmx0/Codehub/DEV/pulsetrackr
xcodebuild -project pulsetrackr.xcodeproj -scheme pulsetrackr -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

## Required Secrets

```sh
firebase functions:secrets:set SOS_ENVELOPE_KEK --project pulsetracker-0000
```

`TWILIO_AUTH_TOKEN` remains bound only to the legacy inbound STOP/START
webhook. No new SOS alert uses Twilio. Configure the APNs key in Firebase
Console before enabling the new iPhone push flow.

## Deploy

```sh
firebase deploy --only functions:pulsetrackr-sos,storage --project pulsetracker-0000
```

Deploy the merged Firestore rules from the PulseTrack website repository. Its
Hosting config owns the public site and the `/i/**` incident share rewrite.
Do not deploy Hosting or Firestore rules from this app repository to the shared
Firebase project.

## Post-Deploy Checks

```sh
firebase functions:list --project pulsetracker-0000
gcloud tasks queues describe processSosNotifications --location us-central1 --project pulsetracker-0000
firebase functions:secrets:access SOS_ENVELOPE_KEK --project pulsetracker-0000 >/dev/null
```

