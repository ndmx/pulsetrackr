"use strict";
// ─── Push notification schemas ───
//
// Contract for the `register_push_device` callable and the private device registry
// (`user_push_devices_private`). Topic subscriptions are computed server-side from
// the reported watch region (the client has no H3 library), so the payload carries
// center + radius + alert preferences rather than topic names.
Object.defineProperty(exports, "__esModule", { value: true });
exports.pushDeviceRecord = exports.registerPushDevicePayload = exports.pushPlatform = void 0;
const zod_1 = require("zod");
const primitives_1 = require("./primitives");
/** Platforms that can register for push. */
exports.pushPlatform = zod_1.z.enum(['ios']);
// ─── registerPushDevicePayload ────────────────────────────────────────────────
// Client→server request for `register_push_device`. Re-sent whenever the FCM token
// rotates, the watch region moves materially, or alert preferences change; the
// server reconciles FCM topic subscriptions and upserts the registry doc.
exports.registerPushDevicePayload = zod_1.z.object({
    /** Current FCM registration token for this install. */
    fcm_token: (0, primitives_1.boundedString)(512),
    platform: exports.pushPlatform,
    app_version: (0, primitives_1.boundedString)(40),
    /** Mirrors the `urgentAlerts` setting — subscribe to urgent-tier topics. */
    urgent_alerts: zod_1.z.boolean(),
    /** Mirrors the `communityAlerts` setting — subscribe to community-tier topics. */
    community_alerts: zod_1.z.boolean(),
    /** Watch-region center; used only to derive topic cells, never persisted raw. */
    latitude: primitives_1.latitude,
    longitude: primitives_1.longitude,
    /** Watch radius in kilometers (Settings slider range, generous upper bound). */
    watch_radius_km: zod_1.z.number().gt(0).lte(100),
});
// ─── pushDeviceRecord ─────────────────────────────────────────────────────────
// Server-written registry doc at `user_push_devices_private/{uid}_{tokenHash}`.
// Holds no raw location — only the derived topic subscriptions — so the registry
// never becomes a queryable location ledger.
exports.pushDeviceRecord = zod_1.z.object({
    owner_uid: (0, primitives_1.boundedString)(128),
    fcm_token: (0, primitives_1.boundedString)(512),
    platform: exports.pushPlatform,
    app_version: (0, primitives_1.boundedString)(40),
    /** FCM topic names this token is subscribed to (server-derived). */
    subscribed_topics: zod_1.z.array((0, primitives_1.boundedString)(96)).max(64),
});
//# sourceMappingURL=push.js.map