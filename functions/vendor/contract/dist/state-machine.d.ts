import { z } from 'zod';
import { communitySignal } from './enums';
import type { CommunitySignal, IncidentSeverity, IncidentStatus } from './enums';
/**
 * Full incident counter/state shape that the transition rules read and write.
 * `status`/`severity` use the wire enum values ("Active", "High", …); the report
 * counters are non-negative integers.
 */
export declare const incidentState: z.ZodObject<{
    status: z.ZodEnum<["Active", "Watching", "Resolved"]>;
    severity: z.ZodEnum<["Low", "Medium", "High", "Urgent"]>;
    confirmations: z.ZodNumber;
    disputes: z.ZodNumber;
    unsafeReports: z.ZodNumber;
    blockedReports: z.ZodNumber;
    clearedReports: z.ZodNumber;
}, "strip", z.ZodTypeAny, {
    status: "Active" | "Watching" | "Resolved";
    severity: "Low" | "Medium" | "High" | "Urgent";
    confirmations: number;
    disputes: number;
    unsafeReports: number;
    blockedReports: number;
    clearedReports: number;
}, {
    status: "Active" | "Watching" | "Resolved";
    severity: "Low" | "Medium" | "High" | "Urgent";
    confirmations: number;
    disputes: number;
    unsafeReports: number;
    blockedReports: number;
    clearedReports: number;
}>;
export type IncidentCountersState = z.infer<typeof incidentState>;
/**
 * Pure transition: returns the NEW state after applying `signal`. Never mutates
 * the input. Encodes the server's deriveSignalOutcome rules exactly, including
 * the counter increments the iOS client applies locally.
 *
 * NOTE on `cleared` while Resolved: the server's deriveSignalOutcome has no early
 * return, so a `cleared` on an already-Resolved incident keeps it Resolved (the
 * count is < threshold only if it was never raised). The iOS client guards with an
 * early `status != .resolved` return before recording any signal; that guard lives
 * at the call site, not inside the rule, so it is intentionally not replicated here.
 */
export declare function applySignal(state: IncidentCountersState, signal: CommunitySignal): IncidentCountersState;
export { communitySignal };
export type { CommunitySignal, IncidentSeverity, IncidentStatus };
//# sourceMappingURL=state-machine.d.ts.map