"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.uuid = exports.clientRef = exports.isoTimestamp = exports.geohash = exports.coordinate = exports.longitude = exports.latitude = void 0;
exports.boundedString = boundedString;
exports.optionalBoundedString = optionalBoundedString;
const zod_1 = require("zod");
// Shared schema building blocks. Everything in the contract composes from these so
// validation rules (bounds, formats) live in exactly one place.
/** A required string: trimmed, non-empty, bounded to `max` characters. */
function boundedString(max) {
    return zod_1.z.string().trim().min(1).max(max);
}
/** An optional string: trimmed and bounded; empty/absent collapses to `undefined`. */
function optionalBoundedString(max) {
    return zod_1.z
        .string()
        .trim()
        .max(max)
        .transform((value) => (value.length === 0 ? undefined : value))
        .optional();
}
exports.latitude = zod_1.z.number().gte(-90).lte(90);
exports.longitude = zod_1.z.number().gte(-180).lte(180);
exports.coordinate = zod_1.z.object({
    latitude: exports.latitude,
    longitude: exports.longitude,
});
/** Geohash cell string — base-32 alphabet (excludes a, i, l, o), lowercase. */
exports.geohash = zod_1.z.string().regex(/^[0-9b-hjkmnp-z]+$/);
/** ISO-8601 timestamp string with offset (the wire format for all timestamps). */
exports.isoTimestamp = zod_1.z.string().datetime({ offset: true });
/** Opaque client-generated reference used for idempotency / dedupe. */
exports.clientRef = zod_1.z.string().trim().min(1).max(128);
exports.uuid = zod_1.z.string().uuid();
//# sourceMappingURL=primitives.js.map