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
firebase functions:secrets:set TWILIO_ACCOUNT_SID --project pulsetracker-0000
firebase functions:secrets:set TWILIO_API_KEY_SID --project pulsetracker-0000
firebase functions:secrets:set TWILIO_API_KEY_SECRET --project pulsetracker-0000
firebase functions:secrets:set TWILIO_AUTH_TOKEN --project pulsetracker-0000
firebase functions:secrets:set TWILIO_FROM_NUMBER --project pulsetracker-0000
firebase functions:secrets:set TWILIO_EMAIL_FROM_ADDRESS --project pulsetracker-0000
firebase functions:secrets:set SOS_ENVELOPE_KEK --project pulsetracker-0000
```

## Deploy

```sh
firebase deploy --only functions:pulsetrackr-sos,firestore:rules,firestore:indexes,storage --project pulsetracker-0000
```

## Post-Deploy Checks

```sh
firebase functions:list --project pulsetracker-0000
gcloud tasks queues describe processSosNotifications --location us-central1 --project pulsetracker-0000
firebase functions:secrets:access SOS_ENVELOPE_KEK --project pulsetracker-0000 >/dev/null
```

