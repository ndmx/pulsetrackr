import { z } from 'zod';

// Shared schema building blocks. Everything in the contract composes from these so
// validation rules (bounds, formats) live in exactly one place.

/** A required string: trimmed, non-empty, bounded to `max` characters. */
export function boundedString(max: number) {
  return z.string().trim().min(1).max(max);
}

/** An optional string: trimmed and bounded; empty/absent collapses to `undefined`. */
export function optionalBoundedString(max: number) {
  return z
    .string()
    .trim()
    .max(max)
    .transform((value) => (value.length === 0 ? undefined : value))
    .optional();
}

export const latitude = z.number().gte(-90).lte(90);
export const longitude = z.number().gte(-180).lte(180);

export const coordinate = z.object({
  latitude,
  longitude,
});
export type Coordinate = z.infer<typeof coordinate>;

/** Geohash cell string — base-32 alphabet (excludes a, i, l, o), lowercase. */
export const geohash = z.string().regex(/^[0-9b-hjkmnp-z]+$/);

/** ISO-8601 timestamp string with offset (the wire format for all timestamps). */
export const isoTimestamp = z.string().datetime({ offset: true });

/** Opaque client-generated reference used for idempotency / dedupe. */
export const clientRef = z.string().trim().min(1).max(128);

export const uuid = z.string().uuid();
