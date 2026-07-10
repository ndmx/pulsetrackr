import { createHash } from 'node:crypto';
import { logger } from 'firebase-functions';
import { getFunctions } from 'firebase-admin/functions';
import { getMessaging } from 'firebase-admin/messaging';
import { onDocumentWritten } from 'firebase-functions/v2/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { onTaskDispatched } from 'firebase-functions/v2/tasks';
import { cellToParent, gridDisk, latLngToCell } from 'h3-js';
import {
  pushDeviceRecord,
  registerPushDevicePayload,
  type RegisterPushDevicePayload,
} from '@pulsetrackr/contract';
import { db, FieldValue, Timestamp } from '../shared/admin';
import { callableOptions, taskQueueOptions } from '../shared/config';
import { cleanString, numberOr, requireAuth, retentionDate, timestampToDate, withoutUndefined } from '../shared/util';

const PUSH_REGISTER_RATE_LIMIT = Object.freeze({
  cooldownSeconds: 5,
  windowSeconds: 60 * 60,
  windowLimit: 30,
  cooldownMessage: 'Please wait before updating push settings again',
  windowMessage: 'Too many push registration updates in the last hour. Try again later.',
});
const PUSH_DEVICE_TTL_DAYS = 60;
const PUSH_MARKER_EXTRA_TTL_DAYS = 7;
const PUSH_ATTEMPT_TTL_DAYS = 30;
const PUSH_H3_RESOLUTION = 6;
const PUSH_MAX_TOPIC_CELLS = 32;
const INCIDENT_PUSH_TASK_QUEUE_FUNCTION_NAME = 'processIncidentAlerts';
const TASK_MAX_ATTEMPTS = 5;
const URGENT_CATEGORIES = new Set(['security', 'fire', 'medical']);
const CATEGORY_LABELS: Record<string, string> = Object.freeze({
  security: 'Security',
  traffic: 'Traffic',
  fire: 'Fire',
  medical: 'Medical',
  weather: 'Weather',
  utilities: 'Utilities',
  structure: 'Structure',
  community: 'Community',
});
const SEVERITY_RANK: Record<string, number> = Object.freeze({
  low: 1,
  medium: 2,
  high: 3,
  urgent: 4,
});

type AlertKind = 'reveal' | 'escalation';
type AlertTier = 'urgent' | 'community';

let pushRepository: PushRepository;

export const register_push_device = onCall(callableOptions, async (request) => {
  const uid = requireAuth(request);
  const now = new Date();
  const payload = sanitizeRegisterPushDevicePayload(request.data);

  return pushRepository.registerPushDevice({ uid, now, payload });
});

export const onIncidentPublicWritten = onDocumentWritten({
  region: callableOptions.region,
  document: 'safety_incidents_public/{incidentId}',
}, async (event) => {
  const incidentId = cleanString(event.params.incidentId, 200);
  const before = event.data?.before.exists ? event.data.before.data() : null;
  const after = event.data?.after.exists ? event.data.after.data() : null;
  if (!incidentId || !after) return;

  const alertKinds = candidateAlertKindsForPublicWrite(before, after);
  for (const alertKind of alertKinds) {
    const claimed = await pushRepository.claimIncidentAlertMarker({
      incidentId,
      alertKind,
      incident: after,
      now: new Date(),
    });
    if (!claimed) continue;
    await enqueueIncidentAlertTask({
      incidentId,
      alertKind,
      incident: after,
    });
  }
});

export const processIncidentAlerts = onTaskDispatched(taskQueueOptions, async (request) => {
  await processIncidentAlertTask(request.data || {}, {
    retryCount: numberOr(request.retryCount, 0),
  });
});

class PushRepository {
  async registerPushDevice({ uid, now, payload }: {
    uid: string;
    now: Date;
    payload: RegisterPushDevicePayload;
  }): Promise<{ subscribedTopicCount: number }> {
    const rateRef = feedRateLimitRef(uid, 'push_device');
    const deviceRef = pushDeviceRef(uid, payload.fcm_token);
    const newTopics = topicNamesForPreferences(payload);

    let oldTopics: string[] = [];
    await db.runTransaction(async (transaction) => {
      await enforceRateLimit(transaction, rateRef, now, PUSH_REGISTER_RATE_LIMIT);
      const snapshot = await transaction.get(deviceRef);
      oldTopics = snapshot.exists ? stringArray(snapshot.data()?.subscribed_topics) : [];

      const record = registryRecordForDevice({ uid, payload, subscribedTopics: newTopics });

      transaction.set(deviceRef, {
        ...record,
        updatedAt: FieldValue.serverTimestamp(),
        deleteAfter: Timestamp.fromDate(daysFrom(now, PUSH_DEVICE_TTL_DAYS)),
      }, { merge: true });
    });

    await reconcileTopicSubscriptions({
      fcmToken: payload.fcm_token,
      previousTopics: oldTopics,
      nextTopics: newTopics,
    });

    return { subscribedTopicCount: newTopics.length };
  }

  async claimIncidentAlertMarker({ incidentId, alertKind, incident, now }: {
    incidentId: string;
    alertKind: AlertKind;
    incident: any;
    now: Date;
  }): Promise<boolean> {
    const markerRef = db.collection('incident_push_markers_private').doc(incidentId);
    const markerField = alertMarkerField(alertKind);
    const deleteAfter = markerDeleteAfter(incident, now);

    return db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(markerRef);
      if (snapshot.exists && snapshot.data()?.[markerField]) {
        return false;
      }

      transaction.set(markerRef, {
        incidentId,
        [markerField]: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        deleteAfter: Timestamp.fromDate(deleteAfter),
      }, { merge: true });
      return true;
    });
  }
}

pushRepository = new PushRepository();

async function enqueueIncidentAlertTask({ incidentId, alertKind, incident }: {
  incidentId: string;
  alertKind: AlertKind;
  incident: any;
}) {
  const taskPayload = {
    incidentId,
    alertKind,
    incident: publicIncidentTaskPayload(incident),
  };

  if (process.env.FUNCTIONS_EMULATOR === 'true' || process.env.PULSETRACKR_DISABLE_CLOUD_TASKS === 'true') {
    await processIncidentAlertTask(taskPayload, { retryCount: 0 });
    return;
  }

  try {
    await getFunctions().taskQueue(INCIDENT_PUSH_TASK_QUEUE_FUNCTION_NAME).enqueue(taskPayload);
    logger.info('Enqueued incident push alert task', { incidentId, alertKind });
  } catch (error: any) {
    await recordIncidentPushDLQ({
      incidentId,
      alertKind,
      reason: 'task_enqueue_failed',
      error,
      payload: taskPayload,
      terminal: true,
      deleteAfter: daysFrom(new Date(), PUSH_ATTEMPT_TTL_DAYS),
    });
    throw error;
  }
}

export async function processIncidentAlertTask(payload: any, context: any = {}) {
  const incidentId = cleanString(payload.incidentId, 200);
  const alertKind = cleanString(payload.alertKind, 40) as AlertKind;
  if (!incidentId || !isAlertKind(alertKind)) {
    throw new Error('incident push task missing incidentId or alertKind');
  }

  const now = new Date();
  const publicSnap = await db.collection('safety_incidents_public').doc(incidentId).get();
  if (!publicSnap.exists) return;

  const incident = publicSnap.data() as any;
  if (isResolved(incident) || normalizedRevealStatus(incident.location_reveal_status) !== 'revealed') return;
  if (!incident.public_h3_cell) return;

  try {
    const tier = incidentAlertTier(incident);
    const topic = topicNameForTier(tier, cellToParent(String(incident.public_h3_cell), PUSH_H3_RESOLUTION));
    const message = buildIncidentPushMessage({ incidentId, incident, tier });
    await getMessaging().send({ topic, ...message });
    await recordIncidentPushAttempt({
      incidentId,
      alertKind,
      topic,
      status: 'sent',
      now,
    });
  } catch (error: any) {
    const topic = safeAttemptTopic(incident);
    await recordIncidentPushAttempt({
      incidentId,
      alertKind,
      topic,
      status: 'failed',
      error,
      now,
    });

    const terminal = numberOr(context.retryCount, 0) >= TASK_MAX_ATTEMPTS - 1;
    if (terminal) {
      await recordIncidentPushDLQ({
        incidentId,
        alertKind,
        reason: 'task_retries_exhausted',
        error,
        payload,
        terminal,
        deleteAfter: daysFrom(now, PUSH_ATTEMPT_TTL_DAYS),
      });
      return;
    }
    throw error;
  }
}

function sanitizeRegisterPushDevicePayload(data: unknown): RegisterPushDevicePayload {
  const result = registerPushDevicePayload.safeParse(data || {});
  if (!result.success) {
    throw new HttpsError('invalid-argument', result.error.issues[0]?.message || 'Invalid push device payload');
  }
  return result.data;
}

function topicCellsForWatchRegion(latitude: number, longitude: number, watchRadiusKm: number): string[] {
  const center = latLngToCell(latitude, longitude, PUSH_H3_RESOLUTION);
  const ring = Math.max(0, Math.ceil(watchRadiusKm / 6));
  return [...new Set(gridDisk(center, ring))].slice(0, PUSH_MAX_TOPIC_CELLS);
}

function topicNamesForPreferences(payload: Pick<RegisterPushDevicePayload,
  'latitude' | 'longitude' | 'watch_radius_km' | 'urgent_alerts' | 'community_alerts'>): string[] {
  const cells = topicCellsForWatchRegion(payload.latitude, payload.longitude, payload.watch_radius_km);
  const topics: string[] = [];
  if (payload.urgent_alerts) {
    topics.push(...cells.map((cell) => topicNameForTier('urgent', cell)));
  }
  if (payload.community_alerts) {
    topics.push(...cells.map((cell) => topicNameForTier('community', cell)));
  }
  return topics;
}

function diffTopicSubscriptions(previousTopics: string[], nextTopics: string[]) {
  const previous = new Set(previousTopics);
  const next = new Set(nextTopics);
  return {
    subscribe: [...next].filter((topic) => !previous.has(topic)).sort(),
    unsubscribe: [...previous].filter((topic) => !next.has(topic)).sort(),
  };
}

function registryRecordForDevice({ uid, payload, subscribedTopics }: {
  uid: string;
  payload: RegisterPushDevicePayload;
  subscribedTopics: string[];
}) {
  return pushDeviceRecord.parse({
    owner_uid: uid,
    fcm_token: payload.fcm_token,
    platform: payload.platform,
    app_version: payload.app_version,
    subscribed_topics: subscribedTopics,
  });
}

async function reconcileTopicSubscriptions({ fcmToken, previousTopics, nextTopics }: {
  fcmToken: string;
  previousTopics: string[];
  nextTopics: string[];
}) {
  const diff = diffTopicSubscriptions(previousTopics, nextTopics);
  const messaging = getMessaging();
  for (const topic of diff.unsubscribe) {
    await messaging.unsubscribeFromTopic([fcmToken], topic);
  }
  for (const topic of diff.subscribe) {
    await messaging.subscribeToTopic([fcmToken], topic);
  }
}

function candidateAlertKindsForPublicWrite(before: any, after: any): AlertKind[] {
  if (!after || isResolved(after)) return [];

  const alertKinds: AlertKind[] = [];
  if (isRevealTransition(before, after)) {
    alertKinds.push('reveal');
  }
  if (isEscalationTransition(before, after)) {
    alertKinds.push('escalation');
  }
  return alertKinds;
}

function pendingAlertKindsForPublicWrite(before: any, after: any, marker: any = {}): AlertKind[] {
  return candidateAlertKindsForPublicWrite(before, after)
    .filter((alertKind) => !marker?.[alertMarkerField(alertKind)]);
}

function isRevealTransition(before: any, after: any): boolean {
  return normalizedRevealStatus(after?.location_reveal_status) === 'revealed'
    && normalizedRevealStatus(before?.location_reveal_status) !== 'revealed';
}

function isEscalationTransition(before: any, after: any): boolean {
  if (normalizedRevealStatus(after?.location_reveal_status) !== 'revealed') return false;
  const afterRank = severityRank(after?.severity);
  if (afterRank < SEVERITY_RANK.high) return false;
  const beforeRank = before ? severityRank(before.severity) : 0;
  return beforeRank < afterRank;
}

function incidentAlertTier(incident: any): AlertTier {
  if (severityRank(incident?.severity) >= SEVERITY_RANK.high) return 'urgent';
  if (URGENT_CATEGORIES.has(cleanString(incident?.category, 80).toLowerCase())) return 'urgent';
  return 'community';
}

function buildIncidentPushMessage({ incidentId, incident, tier }: {
  incidentId: string;
  incident: any;
  tier: AlertTier;
}) {
  const category = cleanString(incident?.category, 80).toLowerCase();
  const label = CATEGORY_LABELS[category] || 'Community';
  const title = cleanString(incident?.title, 120) || 'Nearby safety alert';
  const neighborhood = cleanString(incident?.neighborhood, 120) || 'Nearby area';
  const summary = truncate(cleanString(incident?.summary, 500), 120);
  return withoutUndefined({
    notification: {
      title: `${label}: ${title}`,
      body: `${neighborhood} — ${summary}`,
    },
    data: {
      incident_id: incidentId,
      deep_link: `pulsetrackr://incident/${incidentId}`,
    },
    apns: tier === 'urgent' ? {
      payload: {
        aps: {
          contentAvailable: true,
          sound: 'default',
        },
      },
    } : undefined,
  });
}

function publicIncidentTaskPayload(incident: any) {
  return withoutUndefined({
    title: incident?.title,
    summary: incident?.summary,
    category: incident?.category,
    severity: incident?.severity,
    status: incident?.status,
    neighborhood: incident?.neighborhood,
    public_h3_cell: incident?.public_h3_cell,
    public_h3_resolution: incident?.public_h3_resolution,
    location_reveal_status: incident?.location_reveal_status,
    deleteAfter: timestampToDate(incident?.deleteAfter)?.toISOString(),
  });
}

async function recordIncidentPushAttempt({ incidentId, alertKind, topic, status, error, now }: {
  incidentId: string;
  alertKind: AlertKind;
  topic: string | null;
  status: 'sent' | 'failed';
  error?: any;
  now: Date;
}) {
  await db.collection('incident_push_attempts_private').doc().set(withoutUndefined({
    incidentId,
    alertKind,
    topic,
    status,
    errorMessage: error ? String(error?.message || error).slice(0, 500) : undefined,
    createdAt: FieldValue.serverTimestamp(),
    deleteAfter: Timestamp.fromDate(daysFrom(now, PUSH_ATTEMPT_TTL_DAYS)),
  }));
}

async function recordIncidentPushDLQ({ incidentId, alertKind, reason, error, payload, terminal, deleteAfter }: any) {
  await db.collection('incident_push_dlq_private').doc(`${incidentId}_${alertKind}_${Date.now()}`).set(withoutUndefined({
    incidentId,
    alertKind,
    reason,
    terminal,
    errorMessage: String(error?.message || error).slice(0, 500),
    payload: redactedIncidentPushDlqPayload(payload),
    createdAt: FieldValue.serverTimestamp(),
    deleteAfter: Timestamp.fromDate(deleteAfter || daysFrom(new Date(), PUSH_ATTEMPT_TTL_DAYS)),
  }));
  logger.error('Incident push task moved to DLQ', { incidentId, alertKind, reason, terminal });
}

function redactedIncidentPushDlqPayload(payload: any) {
  return withoutUndefined({
    incidentId: payload?.incidentId,
    alertKind: payload?.alertKind,
    incident: payload?.incident ? publicIncidentTaskPayload(payload.incident) : undefined,
  });
}

function alertMarkerField(alertKind: AlertKind): string {
  return alertKind === 'reveal' ? 'revealAlertSentAt' : 'escalationAlertSentAt';
}

function pushDeviceRef(uid: string, fcmToken: string) {
  return db.collection('user_push_devices_private').doc(pushDeviceDocId(uid, fcmToken));
}

function pushDeviceDocId(uid: string, fcmToken: string): string {
  const tokenHash = createHash('sha256').update(fcmToken).digest('hex').slice(0, 16);
  return `${uid}_${tokenHash}`;
}

function topicNameForTier(tier: AlertTier, cell: string): string {
  return `incident_${tier}_${cell}`;
}

function safeAttemptTopic(incident: any): string | null {
  try {
    if (!incident?.public_h3_cell) return null;
    return topicNameForTier(incidentAlertTier(incident), cellToParent(String(incident.public_h3_cell), PUSH_H3_RESOLUTION));
  } catch {
    return null;
  }
}

function isAlertKind(value: string): value is AlertKind {
  return value === 'reveal' || value === 'escalation';
}

function normalizedRevealStatus(value: unknown): string {
  return cleanString(value, 80).toLowerCase();
}

function severityRank(value: unknown): number {
  return SEVERITY_RANK[cleanString(value, 40).toLowerCase()] || 0;
}

function isResolved(incident: any): boolean {
  return cleanString(incident?.status, 40).toLowerCase() === 'resolved';
}

function markerDeleteAfter(incident: any, now: Date): Date {
  const publicDeleteAfter = timestampToDate(incident?.deleteAfter) || retentionDate(now);
  return daysFrom(publicDeleteAfter, PUSH_MARKER_EXTRA_TTL_DAYS);
}

function feedRateLimitRef(uid: string, action: string) {
  return db.collection('safety_feed_rate_limits_private').doc(`${uid}_${action}`);
}

async function enforceRateLimit(transaction: any, rateRef: any, now: Date, limit: any): Promise<void> {
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
  transaction.set(rateRef, {
    recentEvents: recentEvents.map((date: Date) => Timestamp.fromDate(date)),
    updatedAt: FieldValue.serverTimestamp(),
    deleteAfter: Timestamp.fromDate(retentionDate(now)),
  }, { merge: true });
}

function truncate(value: string, maxLength: number): string {
  if (value.length <= maxLength) return value;
  return `${value.slice(0, Math.max(0, maxLength - 3)).trimEnd()}...`;
}

function daysFrom(date: Date, days: number): Date {
  return new Date(date.getTime() + days * 24 * 60 * 60 * 1000);
}

function stringArray(value: unknown): string[] {
  return Array.isArray(value)
    ? value.map((item) => cleanString(item, 96)).filter(Boolean)
    : [];
}

export const __test = {
  PUSH_H3_RESOLUTION,
  PUSH_MAX_TOPIC_CELLS,
  sanitizeRegisterPushDevicePayload,
  topicCellsForWatchRegion,
  topicNamesForPreferences,
  diffTopicSubscriptions,
  registryRecordForDevice,
  candidateAlertKindsForPublicWrite,
  pendingAlertKindsForPublicWrite,
  incidentAlertTier,
  buildIncidentPushMessage,
  publicIncidentTaskPayload,
  pushDeviceDocId,
  alertMarkerField,
};
