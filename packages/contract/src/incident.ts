// ─── [Wave 1 · Step 2] Incident payload schemas ───
//
// Incident-domain Zod schemas, composed from ./primitives and ./enums. This is the
// single source of truth for the incident client/server contract. rawValues mirror
// the iOS enums in app/Incident.swift and the wire field names in
// functions/src/index.js (sanitizeIncidentPayload / sanitizeIncidentEvidence) and
// app/SafetyIncidentRemoteStore.swift (submitIncident / incident(from:)).

import { z } from 'zod';
import { boundedString, latitude, longitude, geohash, isoTimestamp } from './primitives';
import { incidentCategory, incidentSeverity, incidentStatus } from './enums';
import type { IncidentCategory } from './enums';

// ─── incidentSubtype ───────────────────────────────────────────────────────────
// Every IncidentSubtype rawValue, in declaration order (app/Incident.swift:64-119).
export const incidentSubtype = z.enum([
  // security
  'armed_robbery',
  'kidnapping',
  'gunshots',
  'carjacking',
  'one_chance',
  'suspicious_activity',
  'checkpoint_issue',
  'communal_clash',
  // traffic
  'crash',
  'roadblock',
  'gridlock',
  'flooded_road',
  'bad_road',
  'broken_down_vehicle',
  // fire
  'building_fire',
  'market_fire',
  'gas_leak',
  'explosion',
  'electrical_fire',
  'pipeline_fire',
  // medical
  'medical_emergency',
  'suspected_outbreak',
  'hospital_issue',
  'medicine_shortage',
  'contaminated_water',
  'food_poisoning',
  // weather
  'flooding',
  'heavy_rain',
  'storm_damage',
  'erosion_landslide',
  'drought_water_scarcity',
  // utilities
  'power_outage',
  'water_outage',
  'fuel_scarcity',
  'bridge_damage',
  'rail_issue',
  // structure
  'building_collapse',
  'bridge_collapse',
  'road_collapse',
  'unsafe_building',
  'fallen_power_line',
  // community
  'missing_person',
  'local_warning',
  'safe_route',
  'community_watch',
  'public_gathering',
  'aid_needed',
]);
export type IncidentSubtype = z.infer<typeof incidentSubtype>;

// ─── category ↔ subtype mapping ──────────────────────────────────────────────────
// Mirrors IncidentSubtype.category (app/Incident.swift:122-141). Each subtype belongs
// to exactly one category; declaration order is preserved so the "first" subtype per
// category matches Swift's `defaultSubtype(for:)` (the first allCases element).
export const subtypesByCategory: Record<IncidentCategory, IncidentSubtype[]> = {
  security: [
    'armed_robbery',
    'kidnapping',
    'gunshots',
    'carjacking',
    'one_chance',
    'suspicious_activity',
    'checkpoint_issue',
    'communal_clash',
  ],
  traffic: ['crash', 'roadblock', 'gridlock', 'flooded_road', 'bad_road', 'broken_down_vehicle'],
  fire: ['building_fire', 'market_fire', 'gas_leak', 'explosion', 'electrical_fire', 'pipeline_fire'],
  medical: [
    'medical_emergency',
    'suspected_outbreak',
    'hospital_issue',
    'medicine_shortage',
    'contaminated_water',
    'food_poisoning',
  ],
  weather: ['flooding', 'heavy_rain', 'storm_damage', 'erosion_landslide', 'drought_water_scarcity'],
  utilities: ['power_outage', 'water_outage', 'fuel_scarcity', 'bridge_damage', 'rail_issue'],
  structure: ['building_collapse', 'bridge_collapse', 'road_collapse', 'unsafe_building', 'fallen_power_line'],
  community: ['missing_person', 'local_warning', 'safe_route', 'community_watch', 'public_gathering', 'aid_needed'],
};

/**
 * The default subtype for a category — the first subtype in declaration order.
 * Mirrors IncidentSubtype.defaultSubtype(for:) (app/Incident.swift:266), which falls
 * back to `.localWarning` when a category has no subtypes (cannot happen here, but the
 * fallback is kept for parity).
 */
export function defaultSubtypeForCategory(category: IncidentCategory): IncidentSubtype {
  const [first] = subtypesByCategory[category];
  return first ?? 'local_warning';
}

// ─── incidentEvidence ────────────────────────────────────────────────────────────
// One uploaded evidence item. Wire keys are snake_case to match
// UploadedIncidentEvidence.payload (app/IncidentEvidenceAttachment.swift:23) and
// sanitizeIncidentEvidence (functions/src/index.js:1802). Server bounds: size_bytes
// is > 0 and <= 10 MiB; content_type is bounded to 120 chars.
export const incidentEvidenceKind = z.enum(['photo', 'voice']);
export type IncidentEvidenceKind = z.infer<typeof incidentEvidenceKind>;

const MAX_EVIDENCE_BYTES = 10 * 1024 * 1024;

export const incidentEvidence = z.object({
  kind: incidentEvidenceKind,
  storage_path: boundedString(500),
  content_type: boundedString(120),
  size_bytes: z.number().int().gt(0).lte(MAX_EVIDENCE_BYTES),
  duration_seconds: z.number().nonnegative().optional(),
});
export type IncidentEvidence = z.infer<typeof incidentEvidence>;

// ─── submitIncidentPayload ───────────────────────────────────────────────────────
// The client→server request for the `submit_incident` callable. Field names and bounds
// mirror sanitizeIncidentPayload (functions/src/index.js:1731) and the payload built in
// SafetyIncidentRemoteStore.submitIncident (app/SafetyIncidentRemoteStore.swift:118).
// Snake_case on the wire: client_ref, use_approximate_location.
//
// Bounds (server cleanString limits): title 120, summary 2000, client_ref 80,
// neighborhood 120, source 40. latitude/longitude must be sent together (the server
// rejects one without the other) — modeled here as both-or-neither via superRefine.
// Evidence is capped at 4 items (server slices to 4).
export const submitIncidentPayload = z
  .object({
    title: boundedString(120),
    summary: boundedString(2000),
    category: incidentCategory,
    subtype: incidentSubtype,
    severity: incidentSeverity,
    status: incidentStatus,
    neighborhood: boundedString(120),
    latitude: latitude.optional(),
    longitude: longitude.optional(),
    use_approximate_location: z.boolean(),
    client_ref: boundedString(80),
    source: boundedString(40),
    evidence: z.array(incidentEvidence).max(4),
  })
  .superRefine((value, ctx) => {
    // Server: "latitude and longitude must be provided together" (index.js:1769).
    const hasLatitude = value.latitude !== undefined;
    const hasLongitude = value.longitude !== undefined;
    if (hasLatitude !== hasLongitude) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: 'latitude and longitude must be provided together',
        path: [hasLatitude ? 'longitude' : 'latitude'],
      });
    }
  });
export type SubmitIncidentPayload = z.infer<typeof submitIncidentPayload>;

// ─── publicIncident ──────────────────────────────────────────────────────────────
// The read model from the `safety_incidents_public` collection. Field names mirror the
// document written by submit_incident (functions/src/index.js:158) and read back in
// SafetyIncidentRemoteStore.incident(from:) (app/SafetyIncidentRemoteStore.swift:247).
// Counters are non-negative ints; coordinates/geohash are optional (absent when the
// reporter shared no location). evidence_summary holds derived per-kind counts.
export const incidentEvidenceSummary = z.object({
  photo_count: z.number().int().nonnegative(),
  voice_count: z.number().int().nonnegative(),
});
export type IncidentEvidenceSummary = z.infer<typeof incidentEvidenceSummary>;

// ─── reporterTrustTier ───────────────────────────────────────────────────────────
// Reputation tier stamped onto public incidents at submit time. Derived server-side
// from `reporter_reputation_private` (confirmed-accurate history — never volume);
// absent means 'standard'. Deliberately a tier, not a score: the public read model
// must never leak reporter identity or a fingerprintable value.
export const reporterTrustTier = z.enum(['standard', 'trusted']);
export type ReporterTrustTier = z.infer<typeof reporterTrustTier>;

export const publicIncident = z.object({
  title: boundedString(120),
  summary: boundedString(2000),
  category: incidentCategory,
  subtype: incidentSubtype,
  severity: incidentSeverity,
  status: incidentStatus,
  neighborhood: boundedString(120),
  latitude: latitude.optional(),
  longitude: longitude.optional(),
  geohash: geohash.optional(),
  public_h3_cell: boundedString(32).optional(),
  public_h3_resolution: z.number().int().min(0).max(15).optional(),
  location_reveal_status: z.enum(['revealed', 'pending_k_anonymity']).optional(),
  location_privacy_policy: z.enum(['h3_k_anonymous']).optional(),
  k_anonymity_threshold: z.number().int().positive().optional(),
  k_anonymity_distinct_reporters: z.number().int().nonnegative().optional(),
  confirmations: z.number().int().nonnegative(),
  disputes: z.number().int().nonnegative(),
  unsafe_reports: z.number().int().nonnegative(),
  blocked_reports: z.number().int().nonnegative(),
  cleared_reports: z.number().int().nonnegative(),
  official_updates: z.number().int().nonnegative(),
  evidence_summary: incidentEvidenceSummary.optional(),
  reported_at: isoTimestamp,
  source: boundedString(40).optional(),
  /** Reporter reputation tier at submit time — tier only, never an identity. */
  reporter_trust_tier: reporterTrustTier.optional(),
  /** Attribution for officially ingested incidents (e.g. a weather-alert feed). */
  official_source_name: boundedString(120).optional(),
});
export type PublicIncident = z.infer<typeof publicIncident>;
