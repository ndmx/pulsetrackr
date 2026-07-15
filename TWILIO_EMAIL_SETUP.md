# PulseTrackr Twilio Email Setup

PulseTrackr uses Twilio for SOS SMS, voice, and Comms Email delivery. The `email`
trusted-contact channel is handled by `TWILIO_EMAIL_FROM_ADDRESS`.

## 1. Verify a sender

Use the Twilio Comms Email sender/domain flow for production sender identity.
For early testing, verify one sender address first; before launch, prefer a
domain-authenticated sender so delivery is tied to a PulseTrackr-controlled domain.

## 2. Configure local emulator values

Put provider secrets in `functions/.secret.local`:

```sh
TWILIO_ACCOUNT_SID=AC...
TWILIO_API_KEY_SID=SK...
TWILIO_API_KEY_SECRET=...
TWILIO_AUTH_TOKEN=...
TWILIO_FROM_NUMBER=+15551234567
TWILIO_EMAIL_FROM_ADDRESS=sos@example.com
```

Put non-secret display values in `functions/.env.local`:

```sh
TWILIO_EMAIL_FROM_NAME=PulseTrackr SOS
TWILIO_VOICE_TWIML=https://handler.twilio.com/twiml/...
TWILIO_WEBHOOK_PUBLIC_URL=https://...
```

`TWILIO_AUTH_TOKEN` is required for validating inbound STOP/START webhooks. For
production sends, use the API key SID/secret pair.

## 3. Configure Firebase production secrets

Before deploying production functions:

```sh
firebase functions:secrets:set TWILIO_ACCOUNT_SID
firebase functions:secrets:set TWILIO_API_KEY_SID
firebase functions:secrets:set TWILIO_API_KEY_SECRET
firebase functions:secrets:set TWILIO_AUTH_TOKEN
firebase functions:secrets:set TWILIO_FROM_NUMBER
firebase functions:secrets:set TWILIO_EMAIL_FROM_ADDRESS
```

`TWILIO_EMAIL_FROM_NAME`, `TWILIO_VOICE_TWIML`, and
`TWILIO_WEBHOOK_PUBLIC_URL` are non-secret environment values.

## 4. Expected behavior

- If Twilio Email is not configured, email notification attempts are recorded as
  `provider_unconfigured`.
- SMS and phone-call alerts can still work when email is unconfigured, as long as
  their Twilio sender credentials are present.
- Once `TWILIO_EMAIL_FROM_ADDRESS` and the Twilio API credentials are present,
  trusted contacts with email enabled can receive SOS email alerts.
