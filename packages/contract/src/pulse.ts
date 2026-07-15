// ─── Neighborhood pulse schemas ───
//
// Public read model for the area "pulse" — a calm/elevated/active indicator per H3
// cell, computed by scheduled jobs from durable private aggregates (public incident
// docs TTL out in hours, so scores are never derived from the live feed directly).
// Collection: neighborhood_pulse_public/{cell} (client-readable, server-written).

import { z } from 'zod';
import { boundedString, isoTimestamp } from './primitives';

/** Pulse tier shown to users. Scores compare a cell against its own baseline. */
export const pulseTier = z.enum(['calm', 'elevated', 'active']);
export type PulseTier = z.infer<typeof pulseTier>;

export const neighborhoodPulse = z.object({
  /** H3 cell index (hex string) this pulse describes. */
  cell: boundedString(32),
  /** H3 resolution of `cell` (pulse aggregates at res 7). */
  resolution: z.number().int().min(0).max(15),
  tier: pulseTier,
  /** 0–100: trailing-week activity relative to the cell's own 28-day baseline. */
  score: z.number().int().min(0).max(100),
  /** Coarse trailing-7-day counts by category (only categories with activity). */
  trailing_counts: z.record(z.string(), z.number().int().nonnegative()),
  /** True until the cell has enough baseline history for an honest tier. */
  baseline_building: z.boolean(),
  updated_at: isoTimestamp,
});
export type NeighborhoodPulse = z.infer<typeof neighborhoodPulse>;
