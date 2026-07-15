// ─── [Wave 1 · Step 3] Incident state machine — OWNER: state-machine agent ───
//
// The single source for the status/severity transition rules previously DUPLICATED in:
//   • functions/src/index.js  → deriveSignalOutcome(signal, incident)   (authoritative)
//   • app/IncidentStore.swift → record(_ signal:, for:)                 (optimistic UI)
//
// `applySignal(state, signal)` is the canonical, pure port of those rules. It is
// dependency-free (only the enum types from './enums' + zod for the schema) so it
// ports cleanly to Swift codegen.

import { z } from 'zod';
import { communitySignal, incidentSeverity, incidentStatus } from './enums';
import type { CommunitySignal, IncidentSeverity, IncidentStatus } from './enums';

/**
 * Full incident counter/state shape that the transition rules read and write.
 * `status`/`severity` use the wire enum values ("Active", "High", …); the report
 * counters are non-negative integers.
 */
export const incidentState = z.object({
  status: incidentStatus,
  severity: incidentSeverity,
  confirmations: z.number().int().nonnegative(),
  disputes: z.number().int().nonnegative(),
  unsafeReports: z.number().int().nonnegative(),
  blockedReports: z.number().int().nonnegative(),
  clearedReports: z.number().int().nonnegative(),
});
export type IncidentCountersState = z.infer<typeof incidentState>;

// Threshold: this many cleared reports flips an incident to Resolved.
const CLEARED_RESOLVE_THRESHOLD = 3;

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
export function applySignal(
  state: IncidentCountersState,
  signal: CommunitySignal,
): IncidentCountersState {
  // Copy first so the input is never mutated.
  const next: IncidentCountersState = { ...state };

  switch (signal) {
    case 'seen':
      // seen -> confirmations + 1 (no status/severity change).
      next.confirmations = state.confirmations + 1;
      break;

    case 'notSeen':
      // notSeen -> disputes + 1; if Active and the (post-increment) disputes now
      // meet or exceed confirmations, demote Active -> Watching.
      next.disputes = state.disputes + 1;
      if (state.status === 'Active' && next.disputes >= state.confirmations) {
        next.status = 'Watching';
      }
      break;

    case 'unsafe':
      // unsafe -> unsafeReports + 1; force status Active; floor severity to High,
      // but never downgrade an existing Urgent.
      next.unsafeReports = state.unsafeReports + 1;
      next.status = 'Active';
      if (state.severity !== 'Urgent') {
        next.severity = 'High';
      }
      break;

    case 'roadBlocked':
      // roadBlocked -> blockedReports + 1; raise the floor to Medium ONLY when
      // currently Low — never weaken an existing higher severity.
      next.blockedReports = state.blockedReports + 1;
      if (state.severity === 'Low') {
        next.severity = 'Medium';
      }
      break;

    case 'cleared':
      // cleared -> clearedReports + 1; once cleared reports reach the threshold the
      // incident is Resolved, otherwise it moves to Watching.
      next.clearedReports = state.clearedReports + 1;
      next.status =
        next.clearedReports >= CLEARED_RESOLVE_THRESHOLD ? 'Resolved' : 'Watching';
      break;

    default: {
      // Exhaustiveness guard — adding a CommunitySignal without a case is a compile error.
      const _exhaustive: never = signal;
      return _exhaustive;
    }
  }

  return next;
}

// Re-export the enum value/type so consumers of the state machine get the signal
// vocabulary without a second import. Keeps Swift codegen co-located with the rules.
export { communitySignal };
export type { CommunitySignal, IncidentSeverity, IncidentStatus };
