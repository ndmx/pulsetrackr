import { z } from 'zod';
/** A required string: trimmed, non-empty, bounded to `max` characters. */
export declare function boundedString(max: number): z.ZodString;
/** An optional string: trimmed and bounded; empty/absent collapses to `undefined`. */
export declare function optionalBoundedString(max: number): z.ZodOptional<z.ZodEffects<z.ZodString, string | undefined, string>>;
export declare const latitude: z.ZodNumber;
export declare const longitude: z.ZodNumber;
export declare const coordinate: z.ZodObject<{
    latitude: z.ZodNumber;
    longitude: z.ZodNumber;
}, "strip", z.ZodTypeAny, {
    latitude: number;
    longitude: number;
}, {
    latitude: number;
    longitude: number;
}>;
export type Coordinate = z.infer<typeof coordinate>;
/** Geohash cell string — base-32 alphabet (excludes a, i, l, o), lowercase. */
export declare const geohash: z.ZodString;
/** ISO-8601 timestamp string with offset (the wire format for all timestamps). */
export declare const isoTimestamp: z.ZodString;
/** Opaque client-generated reference used for idempotency / dedupe. */
export declare const clientRef: z.ZodString;
export declare const uuid: z.ZodString;
//# sourceMappingURL=primitives.d.ts.map