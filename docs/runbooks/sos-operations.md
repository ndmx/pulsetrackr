# SOS Operations Runbook

## Activation

1. Check `sos_sessions_private/{sessionId}` for `status`, `notificationSagaStatus`, `expiresAt`, and `deleteAfter`.
2. Exact location fields should be encrypted (`lastKnownLocationEncrypted`, `recentTrailEncrypted`, `finalLocationEncrypted`).
3. Cloud Tasks should enqueue `processSosNotifications`; task payloads must not contain exact coordinates.

## Notifications

1. Check `sos_notification_tasks_private/{sessionId}`.
2. Check `sos_notification_attempts_private` by `sessionId`.
3. Check `sos_notification_dlq_private` only for redacted error context.

## Disclosure

1. Law-enforcement access requires an approved, unexpired `sos_law_enforcement_requests_private` record.
2. Allowed access creates `sos_access_grants_private`, a hash-chained `sos_access_audit` record, and `sos_disclosure_key_releases_private`.
3. Law-enforcement users do not read the global audit collection directly.

