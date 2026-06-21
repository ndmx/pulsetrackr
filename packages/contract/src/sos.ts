// ─── [Wave 1 · Step 4] SOS / disclosure / notification schemas — OWNER: sos-schema agent ───
//
// Source of truth: functions/src/sosShared.js (the sanitize* functions + HARD_LIMITS,
// DEFAULT_POLICY, PRIVILEGED_ROLES, DISCLOSURE_SCOPES, LEGAL_PROCESS_TYPES,
// ALLOWED_CHANNELS, ALLOWED_RESOLUTION_REASONS, redactedContact) and the iOS SOS stores.
//
// These schemas model the *sanitized / canonical* shape (camelCase) — i.e. the output of
// the sanitize* functions, which is the typed contract both client and server agree on.
// The raw wire input uses snake_case keys; sanitization maps it onto these shapes.

import { z } from 'zod';

import {
  boundedString,
  optionalBoundedString,
  latitude,
  longitude,
  isoTimestamp,
} from './primitives';

// ─────────────────────────────────────────────────────────────────────────────
// Numeric limits — re-declared from sosShared.js HARD_LIMITS so the contract
// documents the exact bounds the sanitizers enforce.
// ─────────────────────────────────────────────────────────────────────────────

/** Mirrors `HARD_LIMITS` in functions/src/sosShared.js. */
export const HARD_LIMITS = {
  recentTrailMaxPoints: 24,
  recentTrailMaxAgeSeconds: 30 * 60,
  liveLocationUpdateIntervalSeconds: 15,
  adminAccessExpiresAfterSeconds: 2 * 60 * 60,
  retentionSeconds: 30 * 24 * 60 * 60,
  activationCooldownSeconds: 60,
  activationWindowSeconds: 60 * 60,
  activationWindowLimit: 5,
} as const;

/** Mirrors `DEFAULT_POLICY` in functions/src/sosShared.js. */
export const DEFAULT_POLICY = {
  includeRecentTrail: true,
  recentTrailMaxPoints: 12,
  recentTrailMaxAgeSeconds: 15 * 60,
  liveLocationUpdateIntervalSeconds: 30,
  shareExactLocationWithTrustedContacts: true,
  adminAccessExpiresAfterSeconds: 60 * 60,
  lawEnforcementAccessRequiresActiveSession: true,
  auditPrivilegedAccess: true,
} as const;

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
export const privilegedRole = z.enum(['sosAdmin', 'careTeam', 'lawEnforcement']);
export type PrivilegedRole = z.infer<typeof privilegedRole>;

/** Mirrors `DISCLOSURE_SCOPES` in sosShared.js. */
export const disclosureScope = z.enum([
  'last_known_location',
  'direction_of_travel',
  'redacted_trusted_contacts',
  'recent_trail',
]);
export type DisclosureScope = z.infer<typeof disclosureScope>;

/** Mirrors `LEGAL_PROCESS_TYPES` in sosShared.js. */
export const legalProcessType = z.enum([
  'warrant',
  'court_order',
  'subpoena',
  'emergency_disclosure_request',
  'other',
]);
export type LegalProcessType = z.infer<typeof legalProcessType>;

/** Mirrors `ALLOWED_CHANNELS` in sosShared.js. */
export const notificationChannel = z.enum(['sms', 'phone_call', 'email', 'app_push']);
export type NotificationChannel = z.infer<typeof notificationChannel>;

/** Mirrors `ALLOWED_RESOLUTION_REASONS` in sosShared.js. */
export const resolutionReason = z.enum([
  'user_resolved',
  'false_alarm',
  'timed_out',
  'transferred_to_care_team',
]);
export type ResolutionReason = z.infer<typeof resolutionReason>;

// ─────────────────────────────────────────────────────────────────────────────
// Location snapshot — mirrors sanitizeLocationSnapshot()
// Output keys: latitude, longitude, capturedAt (required); horizontalAccuracyMeters,
// altitudeMeters, speedMetersPerSecond, courseDegrees (optional, nullish-stripped).
// ─────────────────────────────────────────────────────────────────────────────

/** Mirrors `sanitizeLocationSnapshot()` output. */
export const sosLocation = z.object({
  latitude,
  longitude,
  /** >= 0 (nonNegative). */
  horizontalAccuracyMeters: z.number().gte(0).optional(),
  /** Any finite number. */
  altitudeMeters: z.number().optional(),
  /** >= 0 (nonNegative). */
  speedMetersPerSecond: z.number().gte(0).optional(),
  /** Normalized to [0, 360). */
  courseDegrees: z.number().gte(0).lt(360).optional(),
  capturedAt: isoTimestamp,
});
export type SosLocation = z.infer<typeof sosLocation>;

// ─────────────────────────────────────────────────────────────────────────────
// Direction of travel — mirrors sanitizeDirectionOfTravel()
// ─────────────────────────────────────────────────────────────────────────────

/** Mirrors `sanitizeDirectionOfTravel()` output (null when absent). */
export const directionOfTravel = z.object({
  /** Normalized to [0, 360). */
  bearingDegrees: z.number().gte(0).lt(360).optional(),
  /** >= 0 (nonNegative). */
  speedMetersPerSecond: z.number().gte(0).optional(),
  /** clampInteger(.., 0, 0, 1000). */
  computedFromPointCount: z.number().int().gte(0).lte(1000).optional(),
});
export type DirectionOfTravel = z.infer<typeof directionOfTravel>;

// ─────────────────────────────────────────────────────────────────────────────
// Device — mirrors sanitizeDevice()
// ─────────────────────────────────────────────────────────────────────────────

/** Mirrors `sanitizeDevice()` output (all keys optional, nullish-stripped). */
export const sosDevice = z.object({
  /** clampInteger(.., null, 0, 100). */
  batteryLevelPercent: z.number().int().gte(0).lte(100).optional(),
  batteryState: optionalBoundedString(64),
  /** Only present when `=== true`. */
  lowPowerModeEnabled: z.boolean().optional(),
  networkStatus: optionalBoundedString(64),
  /** sliced to max 6 non-empty strings. */
  networkInterfaceTypes: z.array(boundedString(64)).max(MAX_NETWORK_INTERFACE_TYPES).optional(),
  appVersion: optionalBoundedString(64),
  buildNumber: optionalBoundedString(64),
  deviceModel: optionalBoundedString(128),
  systemVersion: optionalBoundedString(64),
});
export type SosDevice = z.infer<typeof sosDevice>;

// ─────────────────────────────────────────────────────────────────────────────
// Privacy policy — mirrors sanitizePrivacyPolicy()
// ─────────────────────────────────────────────────────────────────────────────

/** Mirrors `sanitizePrivacyPolicy()` output. */
export const privacyPolicy = z.object({
  includeRecentTrail: z.boolean(),
  /** clampInteger 0..HARD_LIMITS.recentTrailMaxPoints. */
  recentTrailMaxPoints: z.number().int().gte(0).lte(HARD_LIMITS.recentTrailMaxPoints),
  /** clampInteger 0..HARD_LIMITS.recentTrailMaxAgeSeconds. */
  recentTrailMaxAgeSeconds: z.number().int().gte(0).lte(HARD_LIMITS.recentTrailMaxAgeSeconds),
  /** clampInteger HARD_LIMITS.liveLocationUpdateIntervalSeconds..300. */
  liveLocationUpdateIntervalSeconds: z
    .number()
    .int()
    .gte(HARD_LIMITS.liveLocationUpdateIntervalSeconds)
    .lte(LIVE_INTERVAL_MAX_SECONDS),
  shareExactLocationWithTrustedContacts: z.boolean(),
  /** clampInteger 60..HARD_LIMITS.adminAccessExpiresAfterSeconds. */
  adminAccessExpiresAfterSeconds: z.number().int().gte(60).lte(HARD_LIMITS.adminAccessExpiresAfterSeconds),
  lawEnforcementAccessRequiresActiveSession: z.boolean(),
  auditPrivilegedAccess: z.boolean(),
});
export type PrivacyPolicy = z.infer<typeof privacyPolicy>;

// ─────────────────────────────────────────────────────────────────────────────
// Trusted contacts — mirrors sanitizeTrustedContacts() and redactedContact()
// ─────────────────────────────────────────────────────────────────────────────

/** Mirrors a single entry of `sanitizeTrustedContacts()` output. */
export const trustedContact = z.object({
  contactId: boundedString(128),
  displayName: boundedString(200),
  relationshipLabel: optionalBoundedString(128),
  phoneNumber: optionalBoundedString(64),
  emailAddress: optionalBoundedString(256),
  appUserUid: optionalBoundedString(128),
  appRelationshipId: optionalBoundedString(128),
  /** Deliverable channels only, de-duplicated; at least one is required to survive. */
  channels: z.array(notificationChannel).min(1),
  consentedAt: isoTimestamp.optional(),
});
export type TrustedContact = z.infer<typeof trustedContact>;

/** Mirrors `redactedContact()` output (no raw phone/email/uid leaked). */
export const redactedTrustedContact = z.object({
  contactId: boundedString(128),
  displayName: boundedString(200),
  relationshipLabel: optionalBoundedString(128),
  channels: z.array(notificationChannel),
  /** Last 4 digits of the phone number only. */
  phoneLast4: optionalBoundedString(4),
  hasEmailAddress: z.boolean(),
  appRelationshipId: optionalBoundedString(128),
  hasAppRoute: z.boolean(),
  consentedAt: isoTimestamp.optional(),
});
export type RedactedTrustedContact = z.infer<typeof redactedTrustedContact>;

// ─────────────────────────────────────────────────────────────────────────────
// Activation — mirrors sanitizeActivationPayload()
// ─────────────────────────────────────────────────────────────────────────────

/** Mirrors `sanitizeActivationPayload()` output. */
export const activationPayload = z.object({
  clientSessionId: boundedString(200),
  /** `optionalString(source) || 'ios'`. */
  source: boundedString(64),
  activatedAt: isoTimestamp,
  lastKnownLocation: sosLocation,
  /** limitRecentTrail(): capped at privacy.recentTrailMaxPoints (<= HARD_LIMITS). */
  recentTrail: z.array(sosLocation).max(HARD_LIMITS.recentTrailMaxPoints),
  /** null when absent. */
  directionOfTravel: directionOfTravel.nullable(),
  /** Capped at 10 deliverable contacts. */
  trustedContacts: z.array(trustedContact).max(MAX_TRUSTED_CONTACTS),
  device: sosDevice,
  privacy: privacyPolicy,
});
export type ActivationPayload = z.infer<typeof activationPayload>;

// ─────────────────────────────────────────────────────────────────────────────
// Location update — mirrors sanitizeLocationUpdatePayload()
// ─────────────────────────────────────────────────────────────────────────────

/** Mirrors `sanitizeLocationUpdatePayload()` output. */
export const locationUpdatePayload = z.object({
  sessionId: boundedString(200),
  location: sosLocation,
  /** clampInteger(.., 0, 0, MAX_SAFE_INTEGER). */
  sequenceNumber: z.number().int().gte(0).lte(Number.MAX_SAFE_INTEGER),
  capturedAt: isoTimestamp,
  directionOfTravel: directionOfTravel.nullable(),
  device: sosDevice,
});
export type LocationUpdatePayload = z.infer<typeof locationUpdatePayload>;

// ─────────────────────────────────────────────────────────────────────────────
// Resolution — mirrors sanitizeResolutionPayload()
// ─────────────────────────────────────────────────────────────────────────────

/** Mirrors `sanitizeResolutionPayload()` output. */
export const resolutionPayload = z.object({
  sessionId: boundedString(200),
  reason: resolutionReason,
  resolvedAt: isoTimestamp,
  /** null when no final location supplied. */
  finalLocation: sosLocation.nullable(),
});
export type ResolutionPayload = z.infer<typeof resolutionPayload>;

// ─────────────────────────────────────────────────────────────────────────────
// Law enforcement request — mirrors sanitizeLawEnforcementRequestPayload()
// ─────────────────────────────────────────────────────────────────────────────

/** Mirrors `sanitizeLawEnforcementRequestPayload()` output. */
export const lawEnforcementRequestPayload = z.object({
  sessionId: boundedString(200),
  agencyName: boundedString(200),
  requesterName: boundedString(200),
  requesterTitle: optionalBoundedString(200),
  requesterEmail: optionalBoundedString(256),
  requesterPhone: optionalBoundedString(64),
  legalProcessType,
  legalReference: boundedString(500),
  documentReference: optionalBoundedString(500),
  /** sanitizeDisclosureScope(): de-duplicated subset of disclosureScope. */
  requestedScope: z.array(disclosureScope),
  /** `optionalString(urgency) || 'active_sos'`. */
  urgency: boundedString(64),
  notes: optionalBoundedString(2000),
  receivedAt: isoTimestamp,
});
export type LawEnforcementRequestPayload = z.infer<typeof lawEnforcementRequestPayload>;

// ─────────────────────────────────────────────────────────────────────────────
// Law enforcement review — mirrors sanitizeLawEnforcementReviewPayload()
// ─────────────────────────────────────────────────────────────────────────────

/** Mirrors `sanitizeLawEnforcementReviewPayload()` output. */
export const lawEnforcementReviewPayload = z.object({
  legalRequestId: boundedString(200),
  /** decision must be 'approved' or 'denied'. */
  decision: z.enum(['approved', 'denied']),
  /** sanitizeDisclosureScope(): de-duplicated subset of disclosureScope. */
  approvedScope: z.array(disclosureScope),
  reviewNote: boundedString(2000),
  /** null when no expiry supplied. */
  expiresAt: isoTimestamp.nullable(),
  reviewedAt: isoTimestamp,
});
export type LawEnforcementReviewPayload = z.infer<typeof lawEnforcementReviewPayload>;
