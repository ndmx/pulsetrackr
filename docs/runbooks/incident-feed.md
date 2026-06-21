# Incident Feed Runbook

## Symptoms

- New reports do not appear on the map.
- Counters lag or look stale.
- High-volume incidents show write contention.

## Checks

1. Confirm `submit_incident` is deployed and writes `safety_reports_private`.
2. For privacy-snapped reports, confirm `safety_incidents_public.location_reveal_status`.
3. If `pending_k_anonymity`, verify distinct reporter count and private H3 cells; do not backfill exact coordinates into public docs.
4. For counters, inspect `safety_incident_counter_rollup_queue_private/{incidentId}` and `safety_incident_counter_shards_private`.
5. Confirm `rollupIncidentCounters` exists in `firebase functions:list`.

## Manual Rollup Recovery

Deploying `rollupIncidentCounters` is normally enough. If the scheduler is delayed, wait for the next run or temporarily trigger a targeted rollup from an admin script that sums shard docs and writes only aggregate public counts.

