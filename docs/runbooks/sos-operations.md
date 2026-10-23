# SOS Operations Runbook

## Activation

1. Check `sos_sessions_private/{sessionId}` for `status`, `notificationSagaStatus`, `expiresAt`, and `deleteAfter`.
2. Exact location fields should be encrypted (`lastKnownLocationEncrypted`, `recentTrailEncrypted`, `finalLocationEncrypted`).
3. Cloud Tasks should enqueue `processSosNotifications`; task payloads must not contain exact coordinates.

## Notifications

1. Check `sos_notification_tasks_private/{sessionId}`.
2. Check `sos_app_alerts_private` for one active alert per accepted relationship. `sent` means the Firestore in-app alert was written; it does not prove the person opened it.
3. Check `sos_notification_attempts_private` by `sessionId` and `user_push_devices_private` for recipient FCM tokens. A push is a wake-up prompt and contains no location; its failure does not remove the in-app alert.
4. Verify the recipient accepted a one-way app invite. Old local phone/email contacts cannot receive SOS.
5. Check `sos_notification_dlq_private` only for redacted error context.

Before releasing the iPhone build, enable Push Notifications for its App ID,
configure an APNs authentication key in Firebase Cloud Messaging, and verify
foreground, background, and terminated delivery on two real devices. Keep the
old production SOS behavior until this build is distributed and verified.

## Disclosure

1. Law-enforcement access requires an approved, unexpired `sos_law_enforcement_requests_private` record.
2. Allowed access creates `sos_access_grants_private`, a hash-chained `sos_access_audit` record, and `sos_disclosure_key_releases_private`.
3. Law-enforcement users do not read the global audit collection directly.

