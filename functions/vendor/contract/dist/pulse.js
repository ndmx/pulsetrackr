"use strict";
// ─── Neighborhood pulse schemas ───
//
// Public read model for the area "pulse" — a calm/elevated/active indicator per H3
// cell, computed by scheduled jobs from durable private aggregates (public incident
// docs TTL out in hours, so scores are never derived from the live feed directly).
// Collection: neighborhood_pulse_public/{cell} (client-readable, server-written).
Object.defineProperty(exports, "__esModule", { value: true });
exports.neighborhoodPulse = exports.pulseTier = void 0;
const zod_1 = require("zod");
const primitives_1 = require("./primitives");
/** Pulse tier shown to users. Scores compare a cell against its own baseline. */
exports.pulseTier = zod_1.z.enum(['calm', 'elevated', 'active']);
exports.neighborhoodPulse = zod_1.z.object({
    /** H3 cell index (hex string) this pulse describes. */
    cell: (0, primitives_1.boundedString)(32),
    /** H3 resolution of `cell` (pulse aggregates at res 7). */
    resolution: zod_1.z.number().int().min(0).max(15),
    tier: exports.pulseTier,
    /** 0–100: trailing-week activity relative to the cell's own 28-day baseline. */
    score: zod_1.z.number().int().min(0).max(100),
    /** Coarse trailing-7-day counts by category (only categories with activity). */
    trailing_counts: zod_1.z.record(zod_1.z.string(), zod_1.z.number().int().nonnegative()),
    /** True until the cell has enough baseline history for an honest tier. */
    baseline_building: zod_1.z.boolean(),
    updated_at: primitives_1.isoTimestamp,
});
//# sourceMappingURL=pulse.js.map