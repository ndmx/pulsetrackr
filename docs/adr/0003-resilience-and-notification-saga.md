# ADR 0003: Durable Outbox and SOS Notification Saga

## Status

Accepted

## Context

Mobile clients can be killed mid-report or lose connectivity. SOS notification fan-out should not depend on a single callable invocation completing every provider send.

## Decision

The iOS app routes report, signal, concern, SOS activation, live location, and resolution actions through a durable JSON outbox. The backend enqueues SOS notification fan-out onto Cloud Tasks and records saga status on the private SOS session.

Terminal delivery failures go to `sos_notification_dlq_private` with redacted payloads and session compensation state.

## Consequences

The app can replay on reconnect/foreground. Operators should inspect saga status, notification attempts, and DLQ records instead of assuming a callable response proves every trusted contact was reached.

