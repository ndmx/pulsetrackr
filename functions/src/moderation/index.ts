// Moderation callables for public incident content. Kept separate from the
// incident feed mutation module so reporting abuse can evolve independently.

import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { db, FieldValue, Timestamp } from '../shared/admin';
import { callableOptions } from '../shared/config';
import { cleanString, requireAuth, retentionDate, timestampToDate } from '../shared/util';

const CONCERN_RATE_LIMIT = Object.freeze({
  cooldownSeconds: 10,
  windowSeconds: 60 * 60,
  windowLimit: 30,
  cooldownMessage: 'Please wait before reporting another concern',
  windowMessage: 'Too many concerns submitted in the last hour. Try again later.',
});

const INCIDENT_CONCERN_REASONS = new Set([
  'false_report',
  'offensive_content',
  'private_information',
  'dangerous_advice',
  'spam_or_abuse',
]);

let moderationRepository: ModerationRepository;

export const record_incident_concern = onCall(callableOptions, async (request) => {
  const uid = requireAuth(request);
  const now = new Date();
  const incidentId = cleanString(request.data?.incident_id, 200);
  const reason = cleanString(request.data?.reason, 80);

  if (!incidentId) {
    throw new HttpsError('invalid-argument', 'incident_id is required');
  }
  if (!INCIDENT_CONCERN_REASONS.has(reason)) {
    throw new HttpsError('invalid-argument', 'Unsupported concern reason');
  }

  await moderationRepository.recordIncidentConcern({ uid, now, incidentId, reason });

  return {
    incident_id: incidentId,
    recorded: true,
  };
});

class ModerationRepository {
  async recordIncidentConcern({
    uid,
    now,
    incidentId,
    reason,
  }: {
    uid: string;
    now: Date;
    incidentId: string;
    reason: string;
  }): Promise<void> {
    const publicRef = db.collection('safety_incidents_public').doc(incidentId);
    const concernRef = db.collection('safety_incident_concerns_private').doc();
    const rateRef = db.collection('safety_feed_rate_limits_private').doc(`${uid}_concern`);

    await db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(publicRef);
      if (!snapshot.exists) {
        throw new HttpsError('not-found', 'Incident not found');
      }

      await enforceRateLimit(transaction, rateRef, now, CONCERN_RATE_LIMIT);

      transaction.set(concernRef, {
        incidentId,
        reporterUid: uid,
        reason,
        source: 'ios',
        createdAt: FieldValue.serverTimestamp(),
        deleteAfter: Timestamp.fromDate(retentionDate(now)),
      });
      transaction.update(publicRef, {
        concern_count: FieldValue.increment(1),
        last_concern_at: FieldValue.serverTimestamp(),
        updated_at: FieldValue.serverTimestamp(),
      });
    });
  }
}

moderationRepository = new ModerationRepository();

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

export const __test = {
  INCIDENT_CONCERN_REASONS,
};
