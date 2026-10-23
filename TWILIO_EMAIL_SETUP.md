# Retired Twilio SOS delivery

PulseTrackr now sends SOS alerts only to accepted PulseTrackr app contacts. The
backend no longer sends SOS SMS, automated calls, or email, even if old Twilio
credentials remain in Secret Manager. Do not provision new Twilio senders for SOS.

The signed `twilio_sms_webhook` remains available to record STOP/START replies
to messages sent before the cutover. It uses `TWILIO_AUTH_TOKEN` only for webhook
signature validation. Remove the webhook and historical secrets only after any
existing Twilio sender has stopped receiving replies and retention requirements
have been reviewed.

See [SOS operations](docs/runbooks/sos-operations.md) for current delivery checks.
