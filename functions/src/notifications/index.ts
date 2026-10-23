import { onRequest } from 'firebase-functions/v2/https';
import { onTaskDispatched } from 'firebase-functions/v2/tasks';
import { logger } from 'firebase-functions';
import { getFunctions } from 'firebase-admin/functions';
import { db, FieldValue, Timestamp } from '../shared/admin';
import { webhookOptions, taskQueueOptions, secretValue, twilioAuthToken } from '../shared/config';
import { withoutUndefined, cleanString, retentionDate, firestoreLocation, numberOr } from '../shared/util';
import { decryptPrivateJson } from '../shared/envelope';
import { sendFcmPush } from '../notificationProviders';
import {
  normalizePhoneNumberForSMS,
  parseInboundOptCommand,
  smsOptOutDocId,
  validateTwilioSignature,
} from '../twilioOptOut';

const TASK_QUEUE_FUNCTION_NAME = 'processSosNotifications';
const TASK_MAX_ATTEMPTS = 5;
const APP_TRUSTED_CONTACT_ALERT_LIMIT = 10;

export const processSosNotifications = onTaskDispatched(taskQueueOptions, async (request) => {
  await processSosNotificationTask(request.data || {}, {
    retryCount: numberOr(request.retryCount, 0),
  });
});

export const twilio_sms_webhook = onRequest(webhookOptions, async (request, response) => {
  if (request.method !== 'POST') {
    response.set('Allow', 'POST').status(405).send('Method Not Allowed');
    return;
  }

  const authToken = secretValue(twilioAuthToken) || process.env.TWILIO_AUTH_TOKEN;
  const signature = request.get('x-twilio-signature') || '';
  const params = request.body && typeof request.body === 'object' ? request.body : {};
  const url = process.env.TWILIO_WEBHOOK_PUBLIC_URL || publicWebhookUrl(request);
  if (!validateTwilioSignature({ url, params, signature, authToken })) {
    logger.warn('Rejected Twilio webhook with invalid signature');
    response.status(403).send('Forbidden');
    return;
  }

  const from = normalizePhoneNumberForSMS(params.From || params.from);
  const docId = smsOptOutDocId(from);
  const command = parseInboundOptCommand(params);
  if (!docId || command.action === 'none' || command.action === 'help') {
    response.status(204).send('');
    return;
  }

  const now = new Date();
  const ref = db.collection('sos_sms_opt_outs_private').doc(docId);
  if (command.action === 'opt_out') {
    await ref.set(withoutUndefined({
      status: 'opted_out',
      phoneLast4: from ? from.slice(-4) : undefined,
      keyword: command.keyword,
      messagingServiceSid: cleanString(params.MessagingServiceSid, 80),
      sender: cleanString(params.To, 40),
      optedOutAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      deleteAfter: FieldValue.delete(),
    }), { merge: true });
    logger.info('Recorded trusted-contact SMS opt-out', { phoneLast4: from?.slice(-4), keyword: command.keyword });
  } else if (command.action === 'opt_in') {
    await ref.set(withoutUndefined({
      status: 'opted_in',
      phoneLast4: from ? from.slice(-4) : undefined,
      keyword: command.keyword,
      messagingServiceSid: cleanString(params.MessagingServiceSid, 80),
      sender: cleanString(params.To, 40),
      optedInAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      deleteAfter: Timestamp.fromDate(retentionDate(now)),
    }), { merge: true });
    logger.info('Recorded trusted-contact SMS opt-in', { phoneLast4: from?.slice(-4), keyword: command.keyword });
  }

  response.status(204).send('');
});

export async function enqueueSosNotificationTask({ sessionId, ownerUid, contacts, location, directionOfTravel, deleteAfter }: any) {
  const taskPayload = {
    sessionId,
    ownerUid,
    directionOfTravel,
    deleteAfter: deleteAfter.toISOString(),
  };
  const taskRef = db.collection('sos_notification_tasks_private').doc(sessionId);
  await taskRef.set({
    sessionId,
    ownerUid,
    status: 'enqueued',
    attemptCount: 0,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
    deleteAfter: Timestamp.fromDate(deleteAfter),
  }, { merge: true });

  if (process.env.FUNCTIONS_EMULATOR === 'true' || process.env.PULSETRACKR_DISABLE_CLOUD_TASKS === 'true') {
    await processSosNotificationTask(taskPayload, { retryCount: 0 });
    return {
      enqueued: true,
      notificationSummary: { queued: 0, sent: 0, failed: 0, skipped: 0, optedOut: 0 },
    };
  }

  try {
    await getFunctions().taskQueue(TASK_QUEUE_FUNCTION_NAME).enqueue(taskPayload);
    logger.info('Enqueued SOS in-app alert task', { sessionId });
    return {
      enqueued: true,
      notificationSummary: { queued: 0, sent: 0, failed: 0, skipped: 0, optedOut: 0 },
    };
  } catch (error: any) {
    await recordNotificationDLQ({
      sessionId,
      ownerUid,
      reason: 'task_enqueue_failed',
      error,
      payload: taskPayload,
      terminal: true,
      deleteAfter,
    });
    throw error;
  }
}

export async function processSosNotificationTask(payload: any, context: any = {}) {
  const sessionId = cleanString(payload.sessionId, 160);
  const ownerUid = cleanString(payload.ownerUid, 160);
  if (!sessionId || !ownerUid) {
    throw new Error('notification task missing sessionId or ownerUid');
  }

  const deleteAfter = payload.deleteAfter ? new Date(payload.deleteAfter) : retentionDate(new Date());
  const taskRef = db.collection('sos_notification_tasks_private').doc(sessionId);
  const sessionRef = db.collection('sos_sessions_private').doc(sessionId);

  try {
    await taskRef.set({
      status: 'processing',
      attemptCount: FieldValue.increment(1),
      lastAttemptAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      deleteAfter: Timestamp.fromDate(deleteAfter),
    }, { merge: true });

    const sessionSnap = await sessionRef.get();
    if (!sessionSnap.exists) {
      throw new Error('sos session not found for notification task');
    }
    const session = sessionSnap.data() as any;
    if (session.notificationSagaStatus === 'completed') {
      return;
    }

    const location = sessionPlainLocation(session, sessionId, ownerUid);
    const directionOfTravel = payload.directionOfTravel || session.directionOfTravel;

    // Ignore legacy task payloads containing SMS, call, or email routes. The
    // accepted relationship query below is the sole source of recipients.
    const delivery = emptyLegacyDelivery();
    const appDelivery = await enqueueAppTrustedContactAlerts({
      sessionId,
      ownerUid,
      location,
      directionOfTravel,
      deleteAfter,
    });
    const notificationSummary = combineNotificationSummaries(delivery.notificationSummary, appDelivery.notificationSummary);

    await sessionRef.set({
      trustedContactsNotified: delivery.trustedContactsNotified,
      trustedContactsOptedOut: delivery.trustedContactsOptedOut,
      appTrustedContactsNotified: appDelivery.appTrustedContactsNotified,
      notificationSummary,
      notificationSagaStatus: 'completed',
      notificationSagaCompletedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    await taskRef.set({
      status: 'completed',
      completedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
  } catch (error: any) {
    const terminal = numberOr(context.retryCount, 0) >= TASK_MAX_ATTEMPTS - 1;
    await taskRef.set(withoutUndefined({
      status: terminal ? 'dead_lettered' : 'retrying',
      lastError: String(error?.message || error),
      updatedAt: FieldValue.serverTimestamp(),
    }), { merge: true });
    if (terminal) {
      await recordNotificationDLQ({
        sessionId,
        ownerUid,
        reason: 'task_retries_exhausted',
        error,
        payload,
        terminal,
        deleteAfter,
      });
      return;
    }
    throw error;
  }
}

export async function enqueueTrustedContactNotifications(_args: any) {
  // Kept as a compatibility entry point for already queued tasks. No external
  // provider is allowed to send from the SOS worker after the in-app cutover.
  return emptyLegacyDelivery();
}

function emptyLegacyDelivery() {
  return {
    trustedContactsNotified: [],
    trustedContactsOptedOut: [],
    notificationSummary: { queued: 0, sent: 0, failed: 0, skipped: 0, optedOut: 0 },
  };
}

async function enqueueAppTrustedContactAlerts({ sessionId, ownerUid, location, directionOfTravel, deleteAfter }: any) {
  const relationships = await acceptedOutgoingAppTrustedContacts(ownerUid);
  if (!relationships.length) {
    return {
      appTrustedContactsNotified: [],
      notificationSummary: { queued: 0, sent: 0, failed: 0, skipped: 0, optedOut: 0 },
    };
  }

  const batch = db.batch();
  const appTrustedContactsNotified: string[] = [];
  for (const relationship of relationships.slice(0, APP_TRUSTED_CONTACT_ALERT_LIMIT)) {
    const alertRef = appAlertRef(sessionId, relationship.id);
    const attemptRef = db.collection('sos_notification_attempts_private').doc();
    const alert = appAlertPayload({
      sessionId,
      relationship,
      location,
      directionOfTravel,
      status: 'active',
      deleteAfter,
      kind: 'sos',
    });
    batch.set(alertRef, alert, { merge: true });
    batch.set(attemptRef, withoutUndefined({
      sessionId,
      ownerUid,
      contactId: relationship.id,
      channel: 'app_push',
      destination: relationship.trustedContactUid,
      status: 'sent',
      provider: providerNameForChannel('app_push'),
      providerMessageId: alertRef.id,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      sentAt: FieldValue.serverTimestamp(),
      deleteAfter: Timestamp.fromDate(deleteAfter),
    }));
    appTrustedContactsNotified.push(relationship.id);
  }
  await batch.commit();

  // The Firestore document is the durable in-app alert. Push only wakes a
  // recipient whose app is closed; no location is included in the push.
  await Promise.all(relationships.map(async (relationship: any) => {
    try {
      const devices = await db.collection('user_push_devices_private')
        .where('owner_uid', '==', relationship.trustedContactUid).limit(5).get();
      await Promise.all(devices.docs.map(async (device: any) => {
        const token = cleanString(device.data()?.fcm_token, 4096);
        if (!token) return;
        await sendFcmPush({
          token,
          title: `${relationship.ownerDisplayName || 'PulseTrackr user'} activated SOS`,
          body: 'Open PulseTrackr to view the live alert.',
          data: { session_id: sessionId, kind: 'sos' },
        });
      }));
    } catch (error: any) {
      logger.warn('SOS app push nudge failed', {
        sessionId,
        relationshipId: relationship.id,
        error: String(error?.message || error),
      });
    }
  }));

  logger.info('Created SOS app trusted-contact alerts', {
    sessionId,
    appTrustedContactCount: appTrustedContactsNotified.length,
  });

  return {
    appTrustedContactsNotified,
    notificationSummary: {
      queued: appTrustedContactsNotified.length,
      sent: appTrustedContactsNotified.length,
      failed: 0,
      skipped: 0,
      optedOut: 0,
    },
  };
}

async function acceptedOutgoingAppTrustedContacts(ownerUid: string) {
  const snapshot = await db.collection('sos_app_trusted_contacts_private').where('ownerUid', '==', ownerUid).get();
  return snapshot.docs
    .map((doc) => ({ id: doc.id, ...doc.data() }) as any)
    .filter((relationship: any) => relationship.status === 'accepted' && relationship.trustedContactUid)
    .slice(0, APP_TRUSTED_CONTACT_ALERT_LIMIT);
}

function appAlertRef(sessionId: string, relationshipId: string) {
  return db.collection('sos_app_alerts_private').doc(`${sessionId}_${relationshipId}`);
}

export function appAlertPayload({ sessionId, relationship, location, directionOfTravel, status, deleteAfter, kind = 'sos' }: any) {
  return withoutUndefined({
    sessionId,
    kind,
    ownerUid: relationship.ownerUid,
    recipientUid: relationship.trustedContactUid,
    relationshipId: relationship.id,
    ownerDisplayName: relationship.ownerDisplayName,
    trustedContactDisplayName: relationship.trustedContactDisplayName,
    status,
    lastKnownLocation: firestoreLocation(location),
    directionOfTravel,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
    deleteAfter: Timestamp.fromDate(deleteAfter),
  });
}

function sessionPlainLocation(session: any, sessionId: string, ownerUid: string) {
  if (session.lastKnownLocationEncrypted) {
    return decryptPrivateJson(
      session.lastKnownLocationEncrypted,
      encryptedLocationAad(sessionId, ownerUid, 'lastKnownLocation'),
    );
  }
  return session.lastKnownLocation || null;
}

function encryptedLocationAad(sessionId: string, ownerUid: string, field: string, extra: Record<string, unknown> = {}) {
  return {
    domain: 'pulsetrackr.sos.location',
    sessionId,
    ownerUid,
    field,
    ...extra,
  };
}

async function recordNotificationDLQ({ sessionId, ownerUid, reason, error, payload, terminal, deleteAfter }: any) {
  await db.collection('sos_notification_dlq_private').doc(`${sessionId}_${Date.now()}`).set(withoutUndefined({
    sessionId,
    ownerUid,
    reason,
    terminal,
    errorMessage: String(error?.message || error),
    payload: redactedDlqPayload(payload),
    createdAt: FieldValue.serverTimestamp(),
    deleteAfter: Timestamp.fromDate(deleteAfter || retentionDate(new Date())),
  }));
  await db.collection('sos_sessions_private').doc(sessionId).set({
    notificationSagaStatus: 'failed',
    notificationSagaFailureReason: reason,
    notificationSagaFailedAt: FieldValue.serverTimestamp(),
    notificationSummary: {
      queued: Array.isArray(payload?.contacts) ? payload.contacts.length : 0,
      sent: 0,
      failed: Array.isArray(payload?.contacts) ? payload.contacts.length : 1,
      skipped: 0,
      optedOut: 0,
    },
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  logger.error('SOS notification task moved to DLQ', { sessionId, reason, terminal });
}

function redactedDlqPayload(payload: any) {
  return withoutUndefined({
    sessionId: payload?.sessionId,
    ownerUid: payload?.ownerUid,
    contactCount: Array.isArray(payload?.contacts) ? payload.contacts.length : undefined,
    deleteAfter: payload?.deleteAfter,
  });
}

function combineNotificationSummaries(first: any, second: any) {
  return {
    queued: numberOr(first?.queued, 0) + numberOr(second?.queued, 0),
    sent: numberOr(first?.sent, 0) + numberOr(second?.sent, 0),
    failed: numberOr(first?.failed, 0) + numberOr(second?.failed, 0),
    skipped: numberOr(first?.skipped, 0) + numberOr(second?.skipped, 0),
    optedOut: numberOr(first?.optedOut ?? first?.opted_out, 0) + numberOr(second?.optedOut ?? second?.opted_out, 0),
  };
}

export function providerNameForChannel(channel: string) {
  return channel === 'app_push' ? 'firestore_app_alert' : 'unsupported';
}

function publicWebhookUrl(request: any) {
  const forwardedProto = request.get('x-forwarded-proto');
  const protocol = forwardedProto || request.protocol || 'https';
  const host = request.get('host');
  const path = request.originalUrl || request.url || '';
  return `${protocol}://${host}${path}`;
}
