# ADR 0001: Contract-First Client/Backend Boundary

## Status

Accepted

## Context

PulseTrackr has iOS clients, Firebase callable functions, Firestore read models, and privileged SOS/disclosure workflows. Hand-maintained DTOs and duplicated state-machine rules made release risk too high.

## Decision

Use `packages/contract` as the source of truth for shared payload schemas, public read models, and incident signal state transitions.

The contract emits:

- TypeScript types/runtime validators from Zod.
- Swift Codable DTOs under `app/Generated/PulseTrackrContract.generated.swift`.
- Generated API docs under `docs/api/contract.md`.

CI runs codegen and fails on generated-file drift.

## Consequences

Schema changes must start in `packages/contract/src`. Firebase functions and iOS remote stores should consume generated DTOs rather than inventing parallel field decoders.

