# ADR 0004: Scaled Incident Read Model

## Status

Accepted

## Context

Directly incrementing counters on a public incident document creates a write hotspot as reports become popular.

## Decision

Community signal writes increment private sharded counter documents in `safety_incident_counter_shards_private` and enqueue the incident for rollup in `safety_incident_counter_rollup_queue_private`.

`rollupIncidentCounters` runs every five minutes and writes aggregate counts back to `safety_incidents_public`, which remains the app read model. A server-side `query_incidents_h3` callable provides an H3 hierarchical read path for future clients while the existing app continues to use geohash listeners.

## Consequences

Public counters are eventually consistent. Status/severity derivation reads shard totals during signal writes, so moderation/urgency state does not depend solely on lagging public counters.

