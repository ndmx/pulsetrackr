# ADR 0002: Privacy-First Location Pipeline

## Status

Accepted

## Context

Community reports and SOS flows both need location, but exact location should not become a public or broadly readable artifact.

## Decision

Community incident submissions store exact coordinates only in `safety_reports_private`. Public incident coordinates are revealed only after the H3 k-anonymity threshold is met. The public point is the H3 cell center and is indexed by geohash for existing app listeners.

SOS exact location, recent trail, live updates, and final location are envelope-encrypted in server-only collections. Disclosure decrypts only inside an approved, audited access flow and records a key-release ledger entry tied to the audit hash.

## Consequences

Low-density community reports may not appear on the map until enough distinct nearby reporters exist. SOS notification workers may decrypt location just in time, but Cloud Tasks and DLQ payloads must not persist exact coordinates.

