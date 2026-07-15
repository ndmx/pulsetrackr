// Community incident feed: public report submission, community signals, and concern
// reports. The public feed is read-only to clients (see firestore.rules); these
// callables are the only write path, and the server owns all derived state.

import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { db, FieldValue, Timestamp } from '../shared/admin';
import { callableOptions } from '../shared/config';
import {
  cleanString,
  numberOr,
  requireAuth,
  retentionDate,
  timestampToDate,
  withoutUndefined,
} from '../shared/util';
import {
  publicLocationDecisionForIncident,
  publicLocationFields,
  revealExistingPublicIncidentLocations,
} from '../shared/locationPrivacy';
import { h3QueryCellsForRadius } from '../shared/h3Feed';
// Type-only import from the shared contract: erased at compile time, so it adds no
// runtime dependency to the deployed function. The wire payload is snake_case, which
// is exactly what SubmitIncidentPayload models.
import type { SubmitIncidentPayload } from '@pulsetrackr/contract';

// Per-user throttles for the public community feed. Reports and signals are the
// only client-writable surfaces, so they are the primary abuse/spam vectors.
const SUBMISSION_RATE_LIMIT = Object.freeze({
  cooldownSeconds: 15,
  windowSeconds: 60 * 60,
  windowLimit: 20,
  cooldownMessage: 'Please wait a few seconds before submitting another report',
  windowMessage: 'Too many reports submitted in the last hour. Try again later.',
});
const SIGNAL_RATE_LIMIT = Object.freeze({
  cooldownSeconds: 2,
  windowSeconds: 60 * 60,
  windowLimit: 120,
  cooldownMessage: 'Please wait before sending another update',
  windowMessage: 'Too many community updates in the last hour. Try again later.',
});

// Wire signal -> public counter field. Keys match CommunitySignal.rawValue (iOS).
const SIGNAL_COUNTER_FIELD: Record<string, string> = Object.freeze({
  seen: 'confirmations',
  notSeen: 'disputes',
  unsafe: 'unsafe_reports',
  roadBlocked: 'blocked_reports',
  cleared: 'cleared_reports',
});
const COUNTER_FIELDS = Object.freeze([
  'confirmations',
  'disputes',
  'unsafe_reports',
  'blocked_reports',
  'cleared_reports',
  'official_updates',
]);
const COUNTER_SHARD_COUNT = 16;
const COUNTER_ROLLUP_LIMIT = 250;
const DAY_MS = 24 * 60 * 60 * 1000;
const CRITICAL_PUBLIC_ALERT_CATEGORIES = new Set(['security', 'fire', 'medical', 'structure']);
const CRITICAL_PUBLIC_ALERT_SUBTYPES = new Set([
  'armed_robbery',
  'kidnapping',
  'gunshots',
  'carjacking',
  'communal_clash',
  'building_fire',
  'market_fire',
  'gas_leak',
  'explosion',
  'pipeline_fire',
  'medical_emergency',
  'suspected_outbreak',
  'flooding',
  'building_collapse',
  'bridge_collapse',
  'road_collapse',
  'fallen_power_line',
  'missing_person',
]);
const PUBLIC_ALERT_TTL_SECONDS = Object.freeze({
  critical: 4 * 60 * 60,
  nonCritical: 3 * 60 * 60,
});

let incidentRepository: IncidentRepository;

export const submit_incident = onCall(callableOptions, async (request) => {
  const uid = requireAuth(request);
  const now = new Date();
  const payload = sanitizeIncidentPayload((request.data || {}) as Partial<SubmitIncidentPayload>, uid);
  return incidentRepository.submitIncident({ uid, now, payload });
});

export const record_incident_signal = onCall(callableOptions, async (request) => {
  const uid = requireAuth(request);
  const now = new Date();
  const incidentId = cleanString(request.data?.incident_id, 200);
  const signal = cleanString(request.data?.signal, 40);

  if (!incidentId) {
    throw new HttpsError('invalid-argument', 'incident_id is required');
  }
  if (!Object.prototype.hasOwnProperty.call(SIGNAL_COUNTER_FIELD, signal)) {
    throw new HttpsError('invalid-argument', 'Unsupported community signal');
  }

  const result = await incidentRepository.recordSignal({ uid, now, incidentId, signal });

  return {
    incident_id: incidentId,
    status: result.status,
    severity: result.severity,
    applied: result.applied,
    ...('reason' in result ? { reason: result.reason } : {}),
  };
});

export const rollupIncidentCounters = onSchedule({
  region: callableOptions.region,
  schedule: 'every 5 minutes',
  timeZone: 'Etc/UTC',
  retryCount: 3,
}, async () => {
  await incidentRepository.rollupQueuedCounters(new Date());
});

export const query_incidents_h3 = onCall(callableOptions, async (request) => {
  requireAuth(request);
  const latitude = Number(request.data?.latitude);
  const longitude = Number(request.data?.longitude);
  const radiusMeters = Math.min(Math.max(Number(request.data?.radius_meters) || 3000, 250), 15000);
  const limit = Math.min(Math.max(Number(request.data?.limit) || 100, 1), 200);

  if (!Number.isFinite(latitude) || latitude < -90 || latitude > 90
    || !Number.isFinite(longitude) || longitude < -180 || longitude > 180) {
    throw new HttpsError('invalid-argument', 'A valid latitude and longitude are required');
  }

  return incidentRepository.queryIncidentsByH3({ latitude, longitude, radiusMeters, limit, now: new Date() });
});

class IncidentRepository {
  private readonly database: any;

  constructor(database: any = db) {
    this.database = database;
  }

  async submitIncident({ uid, now, payload }: { uid: string; now: Date; payload: any }) {
    const privateRef = this.database.collection('safety_reports_private').doc();
    const reportsCollection = this.database.collection('safety_reports_private');
    const publicCollection = this.database.collection('safety_incidents_public');
    const publicRef = publicCollection.doc(privateRef.id);
    const rateRef = feedRateLimitRef(uid, 'submit', this.database);
    const reputationRef = this.database.collection('reporter_reputation_private').doc(uid);

    await this.database.runTransaction(async (transaction: any) => {
      const applyRateLimit = await prepareRateLimitUpdate(transaction, rateRef, now, SUBMISSION_RATE_LIMIT);
      const reputationSnapshot = await transaction.get(reputationRef);
      const locationDecision = await publicLocationDecisionForIncident({
        transaction,
        reportsCollection,
        uid,
        now,
        latitude: payload.latitude,
        longitude: payload.longitude,
      });
      const reporterTrustTier = reporterTrustTierFromSnapshot(reputationSnapshot);

      applyRateLimit();
      transaction.set(privateRef, withoutUndefined({
        ownerUid: uid,
        clientRef: payload.clientRef,
        title: payload.title,
        summary: payload.summary,
        category: payload.category,
        subtype: payload.subtype,
        severity: payload.severity,
        status: payload.status,
        neighborhood: payload.neighborhood,
        latitude: payload.latitude,
        longitude: payload.longitude,
        useApproximateLocation: payload.useApproximateLocation,
        privateH3Cell: locationDecision.privateH3Cell,
        privateH3Resolution: locationDecision.privateH3Resolution,
        privateH3ParentCell: locationDecision.privateH3ParentCell,
        privateH3ParentResolution: locationDecision.privateH3ParentResolution,
        evidence: payload.evidence,
        source: payload.source,
        createdAt: FieldValue.serverTimestamp(),
        deleteAfter: Timestamp.fromDate(retentionDate(now)),
      }));

      transaction.set(publicRef, withoutUndefined({
        title: payload.title,
        summary: payload.summary,
        category: payload.category,
        subtype: payload.subtype,
        severity: payload.severity,
        status: payload.status,
        neighborhood: payload.neighborhood || 'Nearby area',
        ...publicLocationFields(locationDecision),
        confirmations: 1,
        disputes: 0,
        unsafe_reports: 0,
        blocked_reports: 0,
        cleared_reports: 0,
        official_updates: 0,
        evidence_summary: {
          photo_count: payload.evidence.filter((item: any) => item.kind === 'photo').length,
          voice_count: payload.evidence.filter((item: any) => item.kind === 'voice').length,
        },
        reported_at: Timestamp.fromDate(now),
        updated_at: FieldValue.serverTimestamp(),
        deleteAfter: Timestamp.fromDate(publicIncidentDeleteAfter(now, payload)),
        source: payload.source,
        reporter_trust_tier: reporterTrustTier,
      }));
      incrementCounterShard(transaction, {
        database: this.database,
        incidentId: publicRef.id,
        counterField: 'confirmations',
        now,
        deleteAfter: publicIncidentDeleteAfter(now, payload),
      });
      revealExistingPublicIncidentLocations(transaction, locationDecision, publicCollection);
    });

    return {
      incident_id: publicRef.id,
      evidence_count: payload.evidence.length,
    };
  }

  async recordSignal({ uid, now, incidentId, signal }: { uid: string; now: Date; incidentId: string; signal: string }) {
    const publicRef = this.database.collection('safety_incidents_public').doc(incidentId);
    const rateRef = feedRateLimitRef(uid, 'signal', this.database);
    const voterRef = this.database.collection('safety_incident_signal_voters_private')
      .doc(`${incidentId}_${uid}`);

    return this.database.runTransaction(async (transaction: any) => {
      const snapshot = await transaction.get(publicRef);
      if (!snapshot.exists) {
        throw new HttpsError('not-found', 'Incident not found');
      }
      const voterSnapshot = await transaction.get(voterRef);

      const incident = snapshot.data() as any;
      if (voterSnapshot.exists) {
        return {
          status: incident.status,
          severity: incident.severity,
          applied: false,
          reason: 'already_signaled',
        };
      }

      const applyRateLimit = await prepareRateLimitUpdate(transaction, rateRef, now, SIGNAL_RATE_LIMIT);
      if (incident.status === 'Resolved') {
        applyRateLimit();
        return { status: incident.status, severity: incident.severity, applied: false };
      }

      const counterTotals = await counterTotalsForIncident(transaction, incidentId, [
        'confirmations',
        'disputes',
        'cleared_reports',
      ], this.database);
      const derived = deriveSignalOutcome(signal, {
        ...incident,
        ...counterTotals,
      });
      const deleteAfter = publicIncidentDeleteAfter(now, {
        ...incident,
        status: derived.status,
        severity: derived.severity,
      });
      const voterDeleteAfter = signalVoterDeleteAfter(now, incident.deleteAfter);
      applyRateLimit();
      transaction.create(voterRef, {
        incidentId,
        uid,
        signal,
        createdAt: FieldValue.serverTimestamp(),
        deleteAfter: Timestamp.fromDate(voterDeleteAfter),
      });
      transaction.update(publicRef, withoutUndefined({
        status: derived.status,
        severity: derived.severity,
        updated_at: FieldValue.serverTimestamp(),
        deleteAfter: Timestamp.fromDate(deleteAfter),
      }));
      incrementCounterShard(transaction, {
        database: this.database,
        incidentId,
        counterField: SIGNAL_COUNTER_FIELD[signal],
        now,
        deleteAfter,
      });

      return { status: derived.status, severity: derived.severity, applied: true };
    });
  }

  async rollupQueuedCounters(now: Date) {
    const queueSnapshot = await this.database.collection('safety_incident_counter_rollup_queue_private')
      .orderBy('updatedAt', 'asc')
      .limit(COUNTER_ROLLUP_LIMIT)
      .get();
    if (queueSnapshot.empty) return { rolled_up: 0 };

    let rolledUp = 0;
    for (const queueDoc of queueSnapshot.docs) {
      const incidentId = queueDoc.id;
      const shardSnapshot = await this.database.collection('safety_incident_counter_shards_private')
        .where('incidentId', '==', incidentId)
        .get();
      const totals = counterTotalsFromShardDocs(shardSnapshot.docs);
      const batch = this.database.batch();
      const publicRef = this.database.collection('safety_incidents_public').doc(incidentId);
      const rollupRef = this.database.collection('safety_incident_counter_rollups_private').doc(incidentId);
      batch.set(publicRef, {
        ...totals,
        countersRolledUpAt: FieldValue.serverTimestamp(),
        updated_at: FieldValue.serverTimestamp(),
      }, { merge: true });
      batch.set(rollupRef, {
        incidentId,
        ...totals,
        rolledUpAt: FieldValue.serverTimestamp(),
        deleteAfter: Timestamp.fromDate(retentionDate(now)),
      }, { merge: true });
      batch.delete(queueDoc.ref);
      await batch.commit();
      rolledUp += 1;
    }

    return { rolled_up: rolledUp };
  }

  async queryIncidentsByH3({ latitude, longitude, radiusMeters, limit, now }: any) {
    const cells = h3QueryCellsForRadius(latitude, longitude, radiusMeters);
    const incidents = new Map<string, any>();

    for (const chunk of chunks(cells, 30)) {
      const snapshot = await this.database.collection('safety_incidents_public')
        .where('public_h3_cell', 'in', chunk)
        .where('deleteAfter', '>', Timestamp.fromDate(now))
        .limit(limit)
        .get();
      for (const doc of snapshot.docs) {
        if (incidents.size >= limit) break;
        const data = doc.data();
        if (data.status === 'Resolved') continue;
        incidents.set(doc.id, { incident_id: doc.id, ...publicIncidentResponse(data) });
      }
      if (incidents.size >= limit) break;
    }

    return {
      incidents: Array.from(incidents.values()).slice(0, limit),
      query: {
        strategy: 'h3_hierarchical',
        cell_count: cells.length,
        radius_meters: radiusMeters,
      },
    };
  }
}

incidentRepository = new IncidentRepository();

function feedRateLimitRef(uid: string, action: string, database: any = db) {
  return database.collection('safety_feed_rate_limits_private').doc(`${uid}_${action}`);
}

function incrementCounterShard(
  transaction: any,
  { database = db, incidentId, counterField, now, deleteAfter }: any,
): void {
  const shard = Math.floor(Math.random() * COUNTER_SHARD_COUNT);
  const shardRef = counterShardRef(incidentId, counterField, shard, database);
  transaction.set(shardRef, {
    incidentId,
    counterField,
    shard,
    count: FieldValue.increment(1),
    updatedAt: FieldValue.serverTimestamp(),
    deleteAfter: Timestamp.fromDate(deleteAfter),
  }, { merge: true });
  transaction.set(database.collection('safety_incident_counter_rollup_queue_private').doc(incidentId), {
    incidentId,
    updatedAt: FieldValue.serverTimestamp(),
    deleteAfter: Timestamp.fromDate(deleteAfter),
  }, { merge: true });
}

function counterShardRef(incidentId: string, counterField: string, shard: number, database: any = db) {
  return database.collection('safety_incident_counter_shards_private')
    .doc(`${incidentId}_${counterField}_${String(shard).padStart(2, '0')}`);
}

async function counterTotalsForIncident(
  transaction: any,
  incidentId: string,
  fields: string[],
  database: any = db,
) {
  const totals: Record<string, number> = {};
  for (const counterField of fields) {
    totals[counterField] = 0;
  }
  const snapshot = await transaction.get(
    database.collection('safety_incident_counter_shards_private')
      .where('incidentId', '==', incidentId),
  );
  for (const doc of snapshot.docs || []) {
    const data = doc.data();
    if (fields.includes(data.counterField)) {
      totals[data.counterField] += numberOr(data.count, 0);
    }
  }
  return totals;
}

function counterTotalsFromShardDocs(docs: any[]) {
  const totals = Object.fromEntries(COUNTER_FIELDS.map((field) => [field, 0]));
  for (const doc of docs) {
    const data = doc.data();
    if (Object.prototype.hasOwnProperty.call(totals, data.counterField)) {
      totals[data.counterField] += numberOr(data.count, 0);
    }
  }
  return totals;
}

function publicIncidentResponse(data: any) {
  return withoutUndefined({
    title: data.title,
    summary: data.summary,
    category: data.category,
    subtype: data.subtype,
    severity: data.severity,
    status: data.status,
    neighborhood: data.neighborhood,
    latitude: data.latitude,
    longitude: data.longitude,
    geohash: data.geohash,
    public_h3_cell: data.public_h3_cell,
    public_h3_resolution: data.public_h3_resolution,
    location_reveal_status: data.location_reveal_status,
    location_privacy_policy: data.location_privacy_policy,
    k_anonymity_threshold: data.k_anonymity_threshold,
    k_anonymity_distinct_reporters: data.k_anonymity_distinct_reporters,
    confirmations: numberOr(data.confirmations, 0),
    disputes: numberOr(data.disputes, 0),
    unsafe_reports: numberOr(data.unsafe_reports, 0),
    blocked_reports: numberOr(data.blocked_reports, 0),
    cleared_reports: numberOr(data.cleared_reports, 0),
    official_updates: numberOr(data.official_updates, 0),
    reporter_trust_tier: data.reporter_trust_tier,
    reported_at: timestampToDate(data.reported_at)?.toISOString(),
    updated_at: timestampToDate(data.updated_at)?.toISOString(),
  });
}

function chunks<T>(values: T[], size: number): T[][] {
  const result: T[][] = [];
  for (let index = 0; index < values.length; index += size) {
    result.push(values.slice(index, index + size));
  }
  return result;
}

function reporterTrustTierFromSnapshot(snapshot: any): 'standard' | 'trusted' {
  const tier = snapshot.exists ? snapshot.data()?.tier : undefined;
  return tier === 'trusted' ? 'trusted' : 'standard';
}

function signalVoterDeleteAfter(now: Date, publicDeleteAfter: any): Date {
  const publicDeleteAfterDate = timestampToDate(publicDeleteAfter);
  if (publicDeleteAfterDate) {
    return new Date(publicDeleteAfterDate.getTime() + 35 * DAY_MS);
  }
  return new Date(now.getTime() + 60 * DAY_MS);
}

// Sliding-window + cooldown limiter. Must be called before any writes in the
// enclosing transaction (it issues a read), and persists the updated window.
async function enforceRateLimit(transaction: any, rateRef: any, now: Date, limit: any): Promise<void> {
  const applyRateLimit = await prepareRateLimitUpdate(transaction, rateRef, now, limit);
  applyRateLimit();
}

async function prepareRateLimitUpdate(
  transaction: any,
  rateRef: any,
  now: Date,
  limit: any,
): Promise<() => void> {
  const snap = await transaction.get(rateRef);
  const windowStartsAt = new Date(now.getTime() - limit.windowSeconds * 1000);
  const recentEvents = snap.exists
    ? (snap.data().recentEvents || [])
      .map(timestampToDate)
      .filter((date: Date | null) => date && date.getTime() >= windowStartsAt.getTime())
    : [];
  const latest = recentEvents.at(-1);

  if (latest && now.getTime() - latest.getTime() < limit.cooldownSeconds * 1000) {
    throw new HttpsError('resource-exhausted', limit.cooldownMessage);
  }
  if (recentEvents.length >= limit.windowLimit) {
    throw new HttpsError('resource-exhausted', limit.windowMessage);
  }

  recentEvents.push(now);
  return () => {
    transaction.set(rateRef, {
      recentEvents: recentEvents.map((date: Date) => Timestamp.fromDate(date)),
      updatedAt: FieldValue.serverTimestamp(),
      deleteAfter: Timestamp.fromDate(retentionDate(now)),
    }, { merge: true });
  };
}

// Server-authoritative port of the iOS IncidentStore signal rules. Counters are
// incremented separately via FieldValue.increment; the +1 here mirrors the
// post-increment state the client computes locally.
function deriveSignalOutcome(signal: string, incident: any) {
  let status = typeof incident.status === 'string' ? incident.status : 'Active';
  let severity = typeof incident.severity === 'string' ? incident.severity : 'Medium';
  const confirmations = numberOr(incident.confirmations, 1);
  const disputes = numberOr(incident.disputes, 0);
  const clearedReports = numberOr(incident.cleared_reports, 0);

  switch (signal) {
    case 'notSeen':
      if (status === 'Active' && disputes + 1 >= confirmations) {
        status = 'Watching';
      }
      break;
    case 'unsafe':
      status = 'Active';
      if (severity !== 'Urgent') {
        severity = 'High';
      }
      break;
    case 'roadBlocked':
      // Only raise the floor to Medium; never weaken an existing severity.
      if (severity === 'Low') {
        severity = 'Medium';
      }
      break;
    case 'cleared':
      status = clearedReports + 1 >= 3 ? 'Resolved' : 'Watching';
      break;
    case 'seen':
    default:
      break;
  }

  return { status, severity };
}

function sanitizeIncidentPayload(data: Partial<SubmitIncidentPayload>, uid: string) {
  const clientRef = cleanString(data.client_ref, 80) || '';
  if (!clientRef) {
    throw new HttpsError('invalid-argument', 'client_ref is required');
  }

  const title = cleanString(data.title, 120);
  const summary = cleanString(data.summary, 2000);
  if (!title || !summary) {
    throw new HttpsError('invalid-argument', 'title and summary are required');
  }

  const coordinate = sanitizeIncidentCoordinate(data);

  const evidence = Array.isArray(data.evidence)
    ? data.evidence.slice(0, 4).map((item: any) => sanitizeIncidentEvidence(item, uid, clientRef))
    : [];

  return {
    clientRef,
    title,
    summary,
    category: cleanString(data.category, 80) || 'community',
    subtype: cleanString(data.subtype, 80) || 'local_warning',
    severity: cleanString(data.severity, 40) || 'Medium',
    status: cleanString(data.status, 40) || 'Active',
    neighborhood: cleanString(data.neighborhood, 120) || 'Nearby area',
    latitude: coordinate.latitude,
    longitude: coordinate.longitude,
    useApproximateLocation: data.use_approximate_location !== false,
    source: cleanString(data.source, 40) || 'ios',
    evidence,
  };
}

function sanitizeIncidentCoordinate(data: any) {
  const hasLatitude = hasCoordinateValue(data.latitude);
  const hasLongitude = hasCoordinateValue(data.longitude);
  if (hasLatitude !== hasLongitude) {
    throw new HttpsError('invalid-argument', 'latitude and longitude must be provided together');
  }
  if (!hasLatitude) {
    throw new HttpsError('invalid-argument', 'A valid latitude and longitude are required');
  }

  const latitude = Number(data.latitude);
  const longitude = Number(data.longitude);
  if (!Number.isFinite(latitude) || latitude < -90 || latitude > 90
    || !Number.isFinite(longitude) || longitude < -180 || longitude > 180) {
    throw new HttpsError('invalid-argument', 'A valid latitude and longitude are required');
  }

  return { latitude, longitude };
}

function hasCoordinateValue(value: unknown): boolean {
  return value !== undefined
    && value !== null
    && !(typeof value === 'string' && value.trim() === '');
}

function publicIncidentCoordinate(payload: any) {
  return undefined;
}

function sanitizeIncidentEvidence(item: any, uid: string, clientRef: string) {
  const kind = cleanString(item?.kind, 20);
  const storagePath = cleanString(item?.storage_path, 500);
  const contentType = cleanString(item?.content_type, 120);
  const sizeBytes = Number(item?.size_bytes);
  const durationSeconds = Number(item?.duration_seconds);
  const requiredPrefix = `incident_reports/${uid}/${clientRef}/`;

  if (!['photo', 'voice'].includes(kind)) {
    throw new HttpsError('invalid-argument', 'Unsupported evidence kind');
  }
  if (!storagePath || !storagePath.startsWith(requiredPrefix)) {
    throw new HttpsError('permission-denied', 'Evidence path must belong to the signed-in reporter');
  }
  if (!Number.isFinite(sizeBytes) || sizeBytes <= 0 || sizeBytes > 10 * 1024 * 1024) {
    throw new HttpsError('invalid-argument', 'Evidence file size is invalid');
  }
  if (kind === 'photo' && !contentType.startsWith('image/')) {
    throw new HttpsError('invalid-argument', 'Photo evidence must be an image');
  }
  if (kind === 'voice' && !contentType.startsWith('audio/')) {
    throw new HttpsError('invalid-argument', 'Voice evidence must be audio');
  }

  return withoutUndefined({
    kind,
    storagePath,
    contentType,
    sizeBytes,
    durationSeconds: Number.isFinite(durationSeconds) ? durationSeconds : undefined,
  });
}

function publicIncidentDeleteAfter(now: Date, incident: any): Date {
  const ttlSeconds = isCriticalPublicAlert(incident)
    ? PUBLIC_ALERT_TTL_SECONDS.critical
    : PUBLIC_ALERT_TTL_SECONDS.nonCritical;
  return new Date(now.getTime() + ttlSeconds * 1000);
}

function isCriticalPublicAlert(incident: any): boolean {
  const severity = cleanString(incident?.severity, 40);
  if (severity === 'Urgent' || severity === 'High') {
    return true;
  }

  const category = cleanString(incident?.category, 80);
  if (CRITICAL_PUBLIC_ALERT_CATEGORIES.has(category)) {
    return true;
  }

  const subtype = cleanString(incident?.subtype, 80);
  return CRITICAL_PUBLIC_ALERT_SUBTYPES.has(subtype);
}

// Test-only surface (mirrors the original index.js __test export).
export const __test = {
  IncidentRepository,
  publicIncidentCoordinate,
  sanitizeIncidentPayload,
  publicIncidentDeleteAfter,
  isCriticalPublicAlert,
  PUBLIC_ALERT_TTL_SECONDS,
  deriveSignalOutcome,
  SIGNAL_COUNTER_FIELD,
  counterTotalsFromShardDocs,
  signalVoterDeleteAfter,
};
