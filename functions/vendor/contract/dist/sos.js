"use strict";
// ─── [Wave 1 · Step 4] SOS / disclosure / notification schemas — OWNER: sos-schema agent ───
//
// Source of truth: functions/src/sosShared.js (the sanitize* functions + HARD_LIMITS,
// DEFAULT_POLICY, PRIVILEGED_ROLES, DISCLOSURE_SCOPES, LEGAL_PROCESS_TYPES,
// ALLOWED_CHANNELS, ALLOWED_RESOLUTION_REASONS, redactedContact) and the iOS SOS stores.
//
// These schemas model the *sanitized / canonical* shape (camelCase) — i.e. the output of
// the sanitize* functions, which is the typed contract both client and server agree on.
// The raw wire input uses snake_case keys; sanitization maps it onto these shapes.
Object.defineProperty(exports, "__esModule", { value: true });
exports.lawEnforcementReviewPayload = exports.lawEnforcementRequestPayload = exports.resolutionPayload = exports.locationUpdatePayload = exports.activationPayload = exports.redactedTrustedContact = exports.trustedContact = exports.privacyPolicy = exports.sosDevice = exports.directionOfTravel = exports.sosLocation = exports.sessionKind = exports.resolutionReason = exports.notificationChannel = exports.legalProcessType = exports.disclosureScope = exports.privilegedRole = exports.DEFAULT_POLICY = exports.HARD_LIMITS = void 0;
const zod_1 = require("zod");
const primitives_1 = require("./primitives");
// ─────────────────────────────────────────────────────────────────────────────
// Numeric limits — re-declared from sosShared.js HARD_LIMITS so the contract
// documents the exact bounds the sanitizers enforce.
// ─────────────────────────────────────────────────────────────────────────────
/** Mirrors `HARD_LIMITS` in functions/src/sosShared.js. */
exports.HARD_LIMITS = {
    recentTrailMaxPoints: 24,
    recentTrailMaxAgeSeconds: 30 * 60,
    liveLocationUpdateIntervalSeconds: 15,
    adminAccessExpiresAfterSeconds: 2 * 60 * 60,
    retentionSeconds: 30 * 24 * 60 * 60,
    activationCooldownSeconds: 60,
    activationWindowSeconds: 60 * 60,
    activationWindowLimit: 5,
};
/** Mirrors `DEFAULT_POLICY` in functions/src/sosShared.js. */
exports.DEFAULT_POLICY = {
    includeRecentTrail: true,
    recentTrailMaxPoints: 12,
    recentTrailMaxAgeSeconds: 15 * 60,
    liveLocationUpdateIntervalSeconds: 30,
    shareExactLocationWithTrustedContacts: true,
    adminAccessExpiresAfterSeconds: 60 * 60,
    lawEnforcementAccessRequiresActiveSession: true,
    auditPrivilegedAccess: true,
};
/** Upper bound for `liveLocationUpdateIntervalSeconds` clamp in sanitizePrivacyPolicy (5 min). */
const LIVE_INTERVAL_MAX_SECONDS = 5 * 60;
/** Max trusted contacts retained by sanitizeTrustedContacts. */
const MAX_TRUSTED_CONTACTS = 10;
/** Max network interface types retained by sanitizeDevice. */
const MAX_NETWORK_INTERFACE_TYPES = 6;
// ─────────────────────────────────────────────────────────────────────────────
// SOS-specific enums
// ─────────────────────────────────────────────────────────────────────────────
/** Mirrors `PRIVILEGED_ROLES` in sosShared.js. */
exports.privilegedRole = zod_1.z.enum(['sosAdmin', 'careTeam', 'lawEnforcement']);
/** Mirrors `DISCLOSURE_SCOPES` in sosShared.js. */
exports.disclosureScope = zod_1.z.enum([
    'last_known_location',
    'direction_of_travel',
    'redacted_trusted_contacts',
    'recent_trail',
]);
/** Mirrors `LEGAL_PROCESS_TYPES` in sosShared.js. */
exports.legalProcessType = zod_1.z.enum([
    'warrant',
    'court_order',
    'subpoena',
    'emergency_disclosure_request',
    'other',
]);
/** Mirrors `ALLOWED_CHANNELS` in sosShared.js. */
exports.notificationChannel = zod_1.z.enum(['sms', 'phone_call', 'email', 'app_push']);
/** Mirrors `ALLOWED_RESOLUTION_REASONS` in sosShared.js. */
exports.resolutionReason = zod_1.z.enum([
    'user_resolved',
    'false_alarm',
    'timed_out',
    'transferred_to_care_team',
    'arrived_safely',
]);
/**
 * Session kind: a real SOS emergency vs a "walk with me" escort session. Escort
 * sessions reuse the SOS trail machinery but alert exactly one app trusted
 * contact and never trigger the Twilio fan-out.
 */
exports.sessionKind = zod_1.z.enum(['sos', 'escort']);
// ─────────────────────────────────────────────────────────────────────────────
// Location snapshot — mirrors sanitizeLocationSnapshot()
// Output keys: latitude, longitude, capturedAt (required); horizontalAccuracyMeters,
// altitudeMeters, speedMetersPerSecond, courseDegrees (optional, nullish-stripped).
// ─────────────────────────────────────────────────────────────────────────────
/** Mirrors `sanitizeLocationSnapshot()` output. */
exports.sosLocation = zod_1.z.object({
    latitude: primitives_1.latitude,
    longitude: primitives_1.longitude,
    /** >= 0 (nonNegative). */
    horizontalAccuracyMeters: zod_1.z.number().gte(0).optional(),
    /** Any finite number. */
    altitudeMeters: zod_1.z.number().optional(),
    /** >= 0 (nonNegative). */
    speedMetersPerSecond: zod_1.z.number().gte(0).optional(),
    /** Normalized to [0, 360). */
    courseDegrees: zod_1.z.number().gte(0).lt(360).optional(),
    capturedAt: primitives_1.isoTimestamp,
});
// ─────────────────────────────────────────────────────────────────────────────
// Direction of travel — mirrors sanitizeDirectionOfTravel()
// ─────────────────────────────────────────────────────────────────────────────
/** Mirrors `sanitizeDirectionOfTravel()` output (null when absent). */
exports.directionOfTravel = zod_1.z.object({
    /** Normalized to [0, 360). */
    bearingDegrees: zod_1.z.number().gte(0).lt(360).optional(),
    /** >= 0 (nonNegative). */
    speedMetersPerSecond: zod_1.z.number().gte(0).optional(),
    /** clampInteger(.., 0, 0, 1000). */
    computedFromPointCount: zod_1.z.number().int().gte(0).lte(1000).optional(),
});
// ─────────────────────────────────────────────────────────────────────────────
// Device — mirrors sanitizeDevice()
// ─────────────────────────────────────────────────────────────────────────────
/** Mirrors `sanitizeDevice()` output (all keys optional, nullish-stripped). */
exports.sosDevice = zod_1.z.object({
    /** clampInteger(.., null, 0, 100). */
    batteryLevelPercent: zod_1.z.number().int().gte(0).lte(100).optional(),
    batteryState: (0, primitives_1.optionalBoundedString)(64),
    /** Only present when `=== true`. */
    lowPowerModeEnabled: zod_1.z.boolean().optional(),
    networkStatus: (0, primitives_1.optionalBoundedString)(64),
    /** sliced to max 6 non-empty strings. */
    networkInterfaceTypes: zod_1.z.array((0, primitives_1.boundedString)(64)).max(MAX_NETWORK_INTERFACE_TYPES).optional(),
    appVersion: (0, primitives_1.optionalBoundedString)(64),
    buildNumber: (0, primitives_1.optionalBoundedString)(64),
    deviceModel: (0, primitives_1.optionalBoundedString)(128),
    systemVersion: (0, primitives_1.optionalBoundedString)(64),
});
// ─────────────────────────────────────────────────────────────────────────────
// Privacy policy — mirrors sanitizePrivacyPolicy()
// ─────────────────────────────────────────────────────────────────────────────
/** Mirrors `sanitizePrivacyPolicy()` output. */
exports.privacyPolicy = zod_1.z.object({
    includeRecentTrail: zod_1.z.boolean(),
    /** clampInteger 0..HARD_LIMITS.recentTrailMaxPoints. */
    recentTrailMaxPoints: zod_1.z.number().int().gte(0).lte(exports.HARD_LIMITS.recentTrailMaxPoints),
    /** clampInteger 0..HARD_LIMITS.recentTrailMaxAgeSeconds. */
    recentTrailMaxAgeSeconds: zod_1.z.number().int().gte(0).lte(exports.HARD_LIMITS.recentTrailMaxAgeSeconds),
    /** clampInteger HARD_LIMITS.liveLocationUpdateIntervalSeconds..300. */
    liveLocationUpdateIntervalSeconds: zod_1.z
        .number()
        .int()
        .gte(exports.HARD_LIMITS.liveLocationUpdateIntervalSeconds)
        .lte(LIVE_INTERVAL_MAX_SECONDS),
    shareExactLocationWithTrustedContacts: zod_1.z.boolean(),
    /** clampInteger 60..HARD_LIMITS.adminAccessExpiresAfterSeconds. */
    adminAccessExpiresAfterSeconds: zod_1.z.number().int().gte(60).lte(exports.HARD_LIMITS.adminAccessExpiresAfterSeconds),
    lawEnforcementAccessRequiresActiveSession: zod_1.z.boolean(),
    auditPrivilegedAccess: zod_1.z.boolean(),
});
// ─────────────────────────────────────────────────────────────────────────────
// Trusted contacts — mirrors sanitizeTrustedContacts() and redactedContact()
// ─────────────────────────────────────────────────────────────────────────────
/** Mirrors a single entry of `sanitizeTrustedContacts()` output. */
exports.trustedContact = zod_1.z.object({
    contactId: (0, primitives_1.boundedString)(128),
    displayName: (0, primitives_1.boundedString)(200),
    relationshipLabel: (0, primitives_1.optionalBoundedString)(128),
    phoneNumber: (0, primitives_1.optionalBoundedString)(64),
    emailAddress: (0, primitives_1.optionalBoundedString)(256),
    appUserUid: (0, primitives_1.optionalBoundedString)(128),
    appRelationshipId: (0, primitives_1.optionalBoundedString)(128),
    /** Deliverable channels only, de-duplicated; at least one is required to survive. */
    channels: zod_1.z.array(exports.notificationChannel).min(1),
    consentedAt: primitives_1.isoTimestamp.optional(),
});
/** Mirrors `redactedContact()` output (no raw phone/email/uid leaked). */
exports.redactedTrustedContact = zod_1.z.object({
    contactId: (0, primitives_1.boundedString)(128),
    displayName: (0, primitives_1.boundedString)(200),
    relationshipLabel: (0, primitives_1.optionalBoundedString)(128),
    channels: zod_1.z.array(exports.notificationChannel),
    /** Last 4 digits of the phone number only. */
    phoneLast4: (0, primitives_1.optionalBoundedString)(4),
    hasEmailAddress: zod_1.z.boolean(),
    appRelationshipId: (0, primitives_1.optionalBoundedString)(128),
    hasAppRoute: zod_1.z.boolean(),
    consentedAt: primitives_1.isoTimestamp.optional(),
});
// ─────────────────────────────────────────────────────────────────────────────
// Activation — mirrors sanitizeActivationPayload()
// ─────────────────────────────────────────────────────────────────────────────
/** Mirrors `sanitizeActivationPayload()` output. */
exports.activationPayload = zod_1.z.object({
    clientSessionId: (0, primitives_1.boundedString)(200),
    /** `optionalString(source) || 'ios'`. */
    source: (0, primitives_1.boundedString)(64),
    activatedAt: primitives_1.isoTimestamp,
    lastKnownLocation: exports.sosLocation,
    /** limitRecentTrail(): capped at privacy.recentTrailMaxPoints (<= HARD_LIMITS). */
    recentTrail: zod_1.z.array(exports.sosLocation).max(exports.HARD_LIMITS.recentTrailMaxPoints),
    /** null when absent. */
    directionOfTravel: exports.directionOfTravel.nullable(),
    /** Capped at 10 deliverable contacts. Must be empty for escort sessions. */
    trustedContacts: zod_1.z.array(exports.trustedContact).max(MAX_TRUSTED_CONTACTS),
    device: exports.sosDevice,
    privacy: exports.privacyPolicy,
    /** Absent means 'sos' (legacy clients predate escort sessions). */
    sessionKind: exports.sessionKind.optional(),
    /** Required iff sessionKind is 'escort': the accepted app relationship to alert. */
    escortRelationshipId: (0, primitives_1.optionalBoundedString)(160),
});
// ─────────────────────────────────────────────────────────────────────────────
// Location update — mirrors sanitizeLocationUpdatePayload()
// ─────────────────────────────────────────────────────────────────────────────
/** Mirrors `sanitizeLocationUpdatePayload()` output. */
exports.locationUpdatePayload = zod_1.z.object({
    sessionId: (0, primitives_1.boundedString)(200),
    location: exports.sosLocation,
    /** clampInteger(.., 0, 0, MAX_SAFE_INTEGER). */
    sequenceNumber: zod_1.z.number().int().gte(0).lte(Number.MAX_SAFE_INTEGER),
    capturedAt: primitives_1.isoTimestamp,
    directionOfTravel: exports.directionOfTravel.nullable(),
    device: exports.sosDevice,
});
// ─────────────────────────────────────────────────────────────────────────────
// Resolution — mirrors sanitizeResolutionPayload()
// ─────────────────────────────────────────────────────────────────────────────
/** Mirrors `sanitizeResolutionPayload()` output. */
exports.resolutionPayload = zod_1.z.object({
    sessionId: (0, primitives_1.boundedString)(200),
    reason: exports.resolutionReason,
    resolvedAt: primitives_1.isoTimestamp,
    /** null when no final location supplied. */
    finalLocation: exports.sosLocation.nullable(),
});
// ─────────────────────────────────────────────────────────────────────────────
// Law enforcement request — mirrors sanitizeLawEnforcementRequestPayload()
// ─────────────────────────────────────────────────────────────────────────────
/** Mirrors `sanitizeLawEnforcementRequestPayload()` output. */
exports.lawEnforcementRequestPayload = zod_1.z.object({
    sessionId: (0, primitives_1.boundedString)(200),
    agencyName: (0, primitives_1.boundedString)(200),
    requesterName: (0, primitives_1.boundedString)(200),
    requesterTitle: (0, primitives_1.optionalBoundedString)(200),
    requesterEmail: (0, primitives_1.optionalBoundedString)(256),
    requesterPhone: (0, primitives_1.optionalBoundedString)(64),
    legalProcessType: exports.legalProcessType,
    legalReference: (0, primitives_1.boundedString)(500),
    documentReference: (0, primitives_1.optionalBoundedString)(500),
    /** sanitizeDisclosureScope(): de-duplicated subset of disclosureScope. */
    requestedScope: zod_1.z.array(exports.disclosureScope),
    /** `optionalString(urgency) || 'active_sos'`. */
    urgency: (0, primitives_1.boundedString)(64),
    notes: (0, primitives_1.optionalBoundedString)(2000),
    receivedAt: primitives_1.isoTimestamp,
});
// ─────────────────────────────────────────────────────────────────────────────
// Law enforcement review — mirrors sanitizeLawEnforcementReviewPayload()
// ─────────────────────────────────────────────────────────────────────────────
/** Mirrors `sanitizeLawEnforcementReviewPayload()` output. */
exports.lawEnforcementReviewPayload = zod_1.z.object({
    legalRequestId: (0, primitives_1.boundedString)(200),
    /** decision must be 'approved' or 'denied'. */
    decision: zod_1.z.enum(['approved', 'denied']),
    /** sanitizeDisclosureScope(): de-duplicated subset of disclosureScope. */
    approvedScope: zod_1.z.array(exports.disclosureScope),
    reviewNote: (0, primitives_1.boundedString)(2000),
    /** null when no expiry supplied. */
    expiresAt: primitives_1.isoTimestamp.nullable(),
    reviewedAt: primitives_1.isoTimestamp,
});
//# sourceMappingURL=sos.js.map