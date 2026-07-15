# Secrets Rotation Runbook

## Twilio Secrets

1. Add a new Firebase Secret Manager version with `firebase functions:secrets:set`.
2. Deploy `functions:pulsetrackr-sos`.
3. Send an internal test notification.
4. Disable the old provider credential in Twilio after successful verification.

## SOS Envelope Key

Generate a new key:

```sh
openssl rand -base64 32 | firebase functions:secrets:set SOS_ENVELOPE_KEK --project pulsetracker-0000 --data-file -
```

Then:

1. Update `SOS_ENVELOPE_KEY_VERSION` for future writes.
2. Deploy functions.
3. Verify new SOS activations encrypt/decrypt through notification and disclosure paths.
4. Keep old secret versions until sessions written with the previous key age out of retention.
5. Disable old secret versions after retention.

