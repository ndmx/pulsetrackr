// ─── Push notification schemas ───
//
// Contract for the `register_push_device` callable and the private device registry
// (`user_push_devices_private`). Topic subscriptions are computed server-side from
// the reported watch region (the client has no H3 library), so the payload carries
// center + radius + alert preferences rather than topic names.

import { z } from 'zod';
import { boundedString, latitude, longitude } from './primitives';

/** Platforms that can register for push. */
export const pushPlatform = z.enum(['ios']);
export type PushPlatform = z.infer<typeof pushPlatform>;

// ─── registerPushDevicePayload ────────────────────────────────────────────────
// Client→server request for `register_push_device`. Re-sent whenever the FCM token
// rotates, the watch region moves materially, or alert preferences change; the
// server reconciles FCM topic subscriptions and upserts the registry doc.
export const registerPushDevicePayload = z.object({
  /** Current FCM registration token for this install. */
  fcm_token: boundedString(512),
  platform: pushPlatform,
  app_version: boundedString(40),
  /** Mirrors the `urgentAlerts` setting — subscribe to urgent-tier topics. */
  urgent_alerts: z.boolean(),
  /** Mirrors the `communityAlerts` setting — subscribe to community-tier topics. */
  community_alerts: z.boolean(),
  /** Watch-region center; used only to derive topic cells, never persisted raw. */
  latitude,
  longitude,
  /** Watch radius in kilometers (Settings slider range, generous upper bound). */
  watch_radius_km: z.number().gt(0).lte(100),
});
export type RegisterPushDevicePayload = z.infer<typeof registerPushDevicePayload>;

// ─── pushDeviceRecord ─────────────────────────────────────────────────────────
// Server-written registry doc at `user_push_devices_private/{uid}_{tokenHash}`.
// Holds no raw location — only the derived topic subscriptions — so the registry
// never becomes a queryable location ledger.
export const pushDeviceRecord = z.object({
  owner_uid: boundedString(128),
  fcm_token: boundedString(512),
  platform: pushPlatform,
  app_version: boundedString(40),
  /** FCM topic names this token is subscribed to (server-derived). */
  subscribed_topics: z.array(boundedString(96)).max(64),
});
export type PushDeviceRecord = z.infer<typeof pushDeviceRecord>;
