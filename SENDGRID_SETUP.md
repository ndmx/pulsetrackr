# PulseTrackr SendGrid Setup

SendGrid is optional for SOS email alerts. Twilio handles SMS and phone calls; SendGrid handles only the `email` trusted-contact channel.

## 1. Verify a sender

For the first test, use Single Sender Verification in the Twilio SendGrid console:

1. Open the Twilio SendGrid console.
2. Go to Settings > Sender Authentication.
3. Choose Single Sender Verification.
4. Verify the exact email address you want PulseTrackr to send from.

For production, use Domain Authentication instead so any approved address on the domain can send with better deliverability.

## 2. Create an API key

Create a SendGrid API key with Custom Access and only the permission PulseTrackr needs:

```text
Mail Send: Full Access
```

Avoid Full Access keys for production. PulseTrackr only calls the v3 Mail Send API with a Bearer token.

## 3. Configure local emulator secrets

Put secret values in `functions/.secret.local`:

```sh
SENDGRID_API_KEY=SG...
SENDGRID_FROM_EMAIL=sos@example.com
```

Put non-secret display values in `functions/.env.local`:

```sh
SENDGRID_FROM_NAME=PulseTrackr SOS
```

## 4. Configure Firebase production secrets

Before deploying production functions:

```sh
firebase functions:secrets:set SENDGRID_API_KEY
firebase functions:secrets:set SENDGRID_FROM_EMAIL
```

`SENDGRID_FROM_NAME` is non-secret and can remain an environment variable if needed.

## 5. Expected behavior

- If SendGrid is not configured, email notification attempts are recorded as `provider_unconfigured`.
- SMS and phone-call alerts still work without SendGrid.
- Once `SENDGRID_API_KEY` and `SENDGRID_FROM_EMAIL` are present, trusted contacts with email enabled can receive SOS email alerts.
