"use strict";
// ─── [Wave 1 · Step 2] Incident payload schemas ───
//
// Incident-domain Zod schemas, composed from ./primitives and ./enums. This is the
// single source of truth for the incident client/server contract. rawValues mirror
// the iOS enums in app/Incident.swift and the wire field names in
// functions/src/index.js (sanitizeIncidentPayload / sanitizeIncidentEvidence) and
// app/SafetyIncidentRemoteStore.swift (submitIncident / incident(from:)).
Object.defineProperty(exports, "__esModule", { value: true });
exports.publicIncident = exports.reporterTrustTier = exports.incidentEvidenceSummary = exports.submitIncidentPayload = exports.incidentEvidence = exports.incidentEvidenceKind = exports.subtypesByCategory = exports.incidentSubtype = void 0;
exports.defaultSubtypeForCategory = defaultSubtypeForCategory;
const zod_1 = require("zod");
const primitives_1 = require("./primitives");
const enums_1 = require("./enums");
// ─── incidentSubtype ───────────────────────────────────────────────────────────
// Every IncidentSubtype rawValue, in declaration order (app/Incident.swift:64-119).
exports.incidentSubtype = zod_1.z.enum([
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
// ─── category ↔ subtype mapping ──────────────────────────────────────────────────
// Mirrors IncidentSubtype.category (app/Incident.swift:122-141). Each subtype belongs
// to exactly one category; declaration order is preserved so the "first" subtype per
// category matches Swift's `defaultSubtype(for:)` (the first allCases element).
exports.subtypesByCategory = {
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
function defaultSubtypeForCategory(category) {
    const [first] = exports.subtypesByCategory[category];
    return first ?? 'local_warning';
}
// ─── incidentEvidence ────────────────────────────────────────────────────────────
// One uploaded evidence item. Wire keys are snake_case to match
// UploadedIncidentEvidence.payload (app/IncidentEvidenceAttachment.swift:23) and
// sanitizeIncidentEvidence (functions/src/index.js:1802). Server bounds: size_bytes
// is > 0 and <= 10 MiB; content_type is bounded to 120 chars.
exports.incidentEvidenceKind = zod_1.z.enum(['photo', 'voice']);
const MAX_EVIDENCE_BYTES = 10 * 1024 * 1024;
exports.incidentEvidence = zod_1.z.object({
    kind: exports.incidentEvidenceKind,
    storage_path: (0, primitives_1.boundedString)(500),
    content_type: (0, primitives_1.boundedString)(120),
    size_bytes: zod_1.z.number().int().gt(0).lte(MAX_EVIDENCE_BYTES),
    duration_seconds: zod_1.z.number().nonnegative().optional(),
});
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
exports.submitIncidentPayload = zod_1.z
    .object({
    title: (0, primitives_1.boundedString)(120),
    summary: (0, primitives_1.boundedString)(2000),
    category: enums_1.incidentCategory,
    subtype: exports.incidentSubtype,
    severity: enums_1.incidentSeverity,
    status: enums_1.incidentStatus,
    neighborhood: (0, primitives_1.boundedString)(120),
    latitude: primitives_1.latitude.optional(),
    longitude: primitives_1.longitude.optional(),
    use_approximate_location: zod_1.z.boolean(),
    client_ref: (0, primitives_1.boundedString)(80),
    source: (0, primitives_1.boundedString)(40),
    evidence: zod_1.z.array(exports.incidentEvidence).max(4),
})
    .superRefine((value, ctx) => {
    // Server: "latitude and longitude must be provided together" (index.js:1769).
    const hasLatitude = value.latitude !== undefined;
    const hasLongitude = value.longitude !== undefined;
    if (hasLatitude !== hasLongitude) {
        ctx.addIssue({
            code: zod_1.z.ZodIssueCode.custom,
            message: 'latitude and longitude must be provided together',
            path: [hasLatitude ? 'longitude' : 'latitude'],
        });
    }
});
// ─── publicIncident ──────────────────────────────────────────────────────────────
// The read model from the `safety_incidents_public` collection. Field names mirror the
// document written by submit_incident (functions/src/index.js:158) and read back in
// SafetyIncidentRemoteStore.incident(from:) (app/SafetyIncidentRemoteStore.swift:247).
// Counters are non-negative ints; coordinates/geohash are optional (absent when the
// reporter shared no location). evidence_summary holds derived per-kind counts.
exports.incidentEvidenceSummary = zod_1.z.object({
    photo_count: zod_1.z.number().int().nonnegative(),
    voice_count: zod_1.z.number().int().nonnegative(),
});
// ─── reporterTrustTier ───────────────────────────────────────────────────────────
// Reputation tier stamped onto public incidents at submit time. Derived server-side
// from `reporter_reputation_private` (confirmed-accurate history — never volume);
// absent means 'standard'. Deliberately a tier, not a score: the public read model
// must never leak reporter identity or a fingerprintable value.
exports.reporterTrustTier = zod_1.z.enum(['standard', 'trusted']);
exports.publicIncident = zod_1.z.object({
    title: (0, primitives_1.boundedString)(120),
    summary: (0, primitives_1.boundedString)(2000),
    category: enums_1.incidentCategory,
    subtype: exports.incidentSubtype,
    severity: enums_1.incidentSeverity,
    status: enums_1.incidentStatus,
    neighborhood: (0, primitives_1.boundedString)(120),
    latitude: primitives_1.latitude.optional(),
    longitude: primitives_1.longitude.optional(),
    geohash: primitives_1.geohash.optional(),
    public_h3_cell: (0, primitives_1.boundedString)(32).optional(),
    public_h3_resolution: zod_1.z.number().int().min(0).max(15).optional(),
    location_reveal_status: zod_1.z.enum(['revealed', 'pending_k_anonymity']).optional(),
    location_privacy_policy: zod_1.z.enum(['h3_k_anonymous']).optional(),
    k_anonymity_threshold: zod_1.z.number().int().positive().optional(),
    k_anonymity_distinct_reporters: zod_1.z.number().int().nonnegative().optional(),
    confirmations: zod_1.z.number().int().nonnegative(),
    disputes: zod_1.z.number().int().nonnegative(),
    unsafe_reports: zod_1.z.number().int().nonnegative(),
    blocked_reports: zod_1.z.number().int().nonnegative(),
    cleared_reports: zod_1.z.number().int().nonnegative(),
    official_updates: zod_1.z.number().int().nonnegative(),
    evidence_summary: exports.incidentEvidenceSummary.optional(),
    reported_at: primitives_1.isoTimestamp,
    source: (0, primitives_1.boundedString)(40).optional(),
    /** Reporter reputation tier at submit time — tier only, never an identity. */
    reporter_trust_tier: exports.reporterTrustTier.optional(),
    /** Attribution for officially ingested incidents (e.g. a weather-alert feed). */
    official_source_name: (0, primitives_1.boundedString)(120).optional(),
});
//# sourceMappingURL=incident.js.map