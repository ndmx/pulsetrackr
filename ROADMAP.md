# PulseTrackr — Roadmap

> Sequenced around three futures: **neighborhood nervous system → trust layer →
> consented safety infrastructure**. Gated by the one rule the category punishes you
> for breaking: *never ship a safety promise you can't keep.*

---

## Phase 0 — Launch-blockers (before any public SOS)

Operational, not technical. The SOS code path is real (see `WIKI.md` §8); operations
must be too.

| Priority | Item | Why |
|---|---|---|
| P0 | Provision Twilio SMS/voice/email secrets + sender verification | SOS that silently fails kills the brand |
| P0 | Delivery-receipt monitoring + alerting | You must *know* a notification failed |
| P0 | Named incident-response owner + runbook | Accountability before lives depend on it |
| P0 | Deploy backend (functions + rules + `record_incident_concern`) | App ship ≠ backend deploy — avoid the geohash version-skew gotcha (`WIKI.md` §9) |
| P1 | App Store screenshots, all required device sizes | Submission gap (`APP_STORE_SUBMISSION.md`) |

---

## Phase 1 — Win one city (Neighborhood nervous system) · 0–3 mo

Goal: solve the cold-start problem in exactly one market. Density beats reach.

- **Pick one beachhead city** and concentrate everything there.
- **Push notifications for high-risk nearby incidents** — the reason people keep the
  app installed.
- **Seed credibility** — partner with existing local safety WhatsApp/Telegram groups;
  ingest one official feed (power outages or transit) so the map is never empty.
- **Frictionless reporting** — drive time-to-report to seconds; the classifier
  already does the heavy lifting.
- **Metric that matters** — daily active reporters per km², not total installs.

---

## Phase 2 — Make reports believable (Trust layer) · 3–9 mo

Goal: turn the verification bones into a moat competitors can't copy with a redesign.

- **Reputation-weighted reporters** — confirmed-accurate history raises signal weight.
- **Time decay** — stale incidents fade automatically; "is this still happening?"
  drives lifecycle.
- **Official-source ingestion** — utility, transit, weather, government feeds as a
  distinct high-confidence tier.
- **Human moderation operations** — staff the `record_incident_concern` pipeline;
  trust scales with people, not users.
- **Anti-weaponization** — detect coordinated false alarms (the failure mode that
  ends safety apps).

---

## Phase 3 — Consented safety infrastructure (SOS, matured) · 9–18 mo

Goal: the principled, audit-backed personal-safety protocol — never the fake-911.

- **Consent-first responder integrations** — campus security, building management,
  care teams, family circles — explicit, revocable, audited (the `sos_access_audit`
  bones already exist; see `WIKI.md` §8).
- **Provable restraint as the product** — surface the audit trail to users: who can
  see what, and when access expires.
- **Live SOS reliability SLAs** — redundant providers, automatic failover, tested end
  to end.

---

## Continuous — Technical debt (low risk, do between features)

From `WIKI.md` §7:
- Consolidate near-duplicate pin views → one `IncidentPin(incident:, style:)`.
- Merge the three panel modifiers (`detailPanel` / `reportPanel` / `settingsPanel`)
  → shared `cardPanel(backgroundOpacity:)`.
- Unify `CategoryChip` / `MapboxCategoryChip` with a `darkBackground` flag.
- Complete localization migration beyond the `es` worked example (`LOCALIZATION.md`).

---

## Standing constraints — the three traps

1. **Cold start** — go deep in one city, never wide. An empty map is a dead map.
2. **Moderation scales with trust, not users** — staff it before you scale.
3. **The SOS promise is sacred** — Phase 0 gates Phase 3. No exceptions.
