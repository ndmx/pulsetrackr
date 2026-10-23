import { z } from 'zod';
/** Pulse tier shown to users. Scores compare a cell against its own baseline. */
export declare const pulseTier: z.ZodEnum<["calm", "elevated", "active"]>;
export type PulseTier = z.infer<typeof pulseTier>;
export declare const neighborhoodPulse: z.ZodObject<{
    /** H3 cell index (hex string) this pulse describes. */
    cell: z.ZodString;
    /** H3 resolution of `cell` (pulse aggregates at res 7). */
    resolution: z.ZodNumber;
    tier: z.ZodEnum<["calm", "elevated", "active"]>;
    /** 0–100: trailing-week activity relative to the cell's own 28-day baseline. */
    score: z.ZodNumber;
    /** Coarse trailing-7-day counts by category (only categories with activity). */
    trailing_counts: z.ZodRecord<z.ZodString, z.ZodNumber>;
    /** True until the cell has enough baseline history for an honest tier. */
    baseline_building: z.ZodBoolean;
    updated_at: z.ZodString;
}, "strip", z.ZodTypeAny, {
    cell: string;
    resolution: number;
    tier: "calm" | "elevated" | "active";
    score: number;
    trailing_counts: Record<string, number>;
    baseline_building: boolean;
    updated_at: string;
}, {
    cell: string;
    resolution: number;
    tier: "calm" | "elevated" | "active";
    score: number;
    trailing_counts: Record<string, number>;
    baseline_building: boolean;
    updated_at: string;
}>;
export type NeighborhoodPulse = z.infer<typeof neighborhoodPulse>;
//# sourceMappingURL=pulse.d.ts.map