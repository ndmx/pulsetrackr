import { onRequest } from 'firebase-functions/v2/https';
import { onTaskDispatched } from 'firebase-functions/v2/tasks';
import { logger } from 'firebase-functions';
import { getFunctions } from 'firebase-admin/functions';
import { db, FieldValue, Timestamp } from '../shared/admin';
import {
  webhookOptions,
  taskQueueOptions,
  secretValue,
  twilioAccountSid,
  twilioApiKeySid,
  twilioApiKeySecret,
  twilioFromNumber,
  twilioEmailFromAddress,
  twilioAuthToken,
} from '../shared/config';
import { withoutUndefined, cleanString, retentionDate, firestoreLocation, numberOr } from '../shared/util';
import { decryptPrivateJson } from '../shared/envelope';
import { providerReadiness, sendNotificationAttempt } from '../notificationProviders';
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
    contacts,
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
      notificationSummary: { queued: contacts.length, sent: 0, failed: 0, skipped: 0, optedOut: 0 },
    };
  }

  try {
    await getFunctions().taskQueue(TASK_QUEUE_FUNCTION_NAME).enqueue(taskPayload);
    logger.info('Enqueued SOS notification worker task', { sessionId, contactCount: contacts.length });
    return {
      enqueued: true,
      notificationSummary: { queued: contacts.length, sent: 0, failed: 0, skipped: 0, optedOut: 0 },
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

    const contacts = Array.isArray(payload.contacts) ? payload.contacts : (session.trustedContacts || []);
    const location = sessionPlainLocation(session, sessionId, ownerUid);
    const directionOfTravel = payload.directionOfTravel || session.directionOfTravel;

    const delivery = await enqueueTrustedContactNotifications({
      sessionId,
      ownerUid,
      contacts,
      location,
      deleteAfter,
    });
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

export async function enqueueTrustedContactNotifications({ sessionId, ownerUid, contacts, location, deleteAfter }: any) {
  if (!contacts.length) {
    return {
      trustedContactsNotified: [],
      trustedContactsOptedOut: [],
      notificationSummary: { queued: 0, sent: 0, failed: 0, skipped: 0, optedOut: 0 },
    };
  }

  const batch = db.batch();
  const attempts: any[] = [];
  const immediateResults: any[] = [];
  for (const contact of contacts) {
    for (const channel of contact.channels) {
      if (channel === 'app_push') {
        continue;
      }
      const attemptRef = db.collection('sos_notification_attempts_private').doc();
      const destination = destinationForChannel(contact, channel);
      if (channel === 'sms' && await isSmsOptedOut(destination)) {
        batch.set(attemptRef, withoutUndefined({
          sessionId,
          ownerUid,
          contactId: contact.contactId,
          channel,
          destination,
          status: 'recipient_opted_out',
          provider: providerNameForChannel(channel),
          errorMessage: 'recipient_previously_opted_out',
          createdAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
          deleteAfter: Timestamp.fromDate(deleteAfter),
        }));
        immediateResults.push({
          status: 'recipient_opted_out',
          provider: providerNameForChannel(channel),
          providerMessageId: null,
          errorMessage: 'recipient_previously_opted_out',
          contactId: contact.contactId,
          destination,
        });
        continue;
      }
      batch.set(attemptRef, withoutUndefined({
        sessionId,
        ownerUid,
        contactId: contact.contactId,
        channel,
        destination,
        status: 'queued',
        provider: providerNameForChannel(channel),
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        deleteAfter: Timestamp.fromDate(deleteAfter),
      }));
      attempts.push({ attemptRef, contact, channel, destination });
    }
  }
  await batch.commit();

  logger.info('Queued SOS trusted-contact notifications', {
    sessionId,
    contactCount: contacts.length,
    providerReadiness: providerReadiness(),
  });

  return deliverQueuedNotifications({ sessionId, attempts, location, initialResults: immediateResults });
}

async function deliverQueuedNotifications({ sessionId, attempts, location, initialResults = [] }: any) {
  const deliveryResults = await Promise.all(attempts.map(async (attempt: any) => {
    const sentAt = new Date();
    const result = await sendNotificationAttempt({
      sessionId,
      contact: attempt.contact,
      channel: attempt.channel,
      destination: attempt.destination,
      location,
      env: notificationProviderEnv(),
    });

    await attempt.attemptRef.set(withoutUndefined({
      status: result.status,
      provider: result.provider,
      providerMessageId: result.providerMessageId,
      errorMessage: result.errorMessage,
      sentAt: result.status === 'sent' ? Timestamp.fromDate(sentAt) : undefined,
      updatedAt: FieldValue.serverTimestamp(),
    }), { merge: true });

    if (result.status === 'recipient_opted_out') {
      await recordSmsOptOutFromDelivery({
        destination: attempt.destination,
        errorMessage: result.errorMessage,
      });
    }

    return { ...result, contactId: attempt.contact.contactId };
  }));

  const results = [...initialResults, ...deliveryResults];
  const summary = results.reduce((counts, result) => {
    if (result.status === 'sent') counts.sent += 1;
    else if (result.status === 'failed') counts.failed += 1;
    else if (result.status === 'recipient_opted_out') counts.optedOut += 1;
    else counts.skipped += 1;
    return counts;
  }, { sent: 0, failed: 0, skipped: 0, optedOut: 0 });
  const trustedContactsNotified = [...new Set(
    results
      .filter((result) => result.status === 'sent')
      .map((result) => result.contactId)
  )];
  const trustedContactsOptedOut = [...new Set(
    results
      .filter((result) => result.status === 'recipient_opted_out')
      .map((result) => result.contactId)
  )];
  const notificationSummary = {
    queued: attempts.length + initialResults.length,
    sent: summary.sent,
    failed: summary.failed,
    skipped: summary.skipped,
    optedOut: summary.optedOut,
  };

  await db.collection('sos_sessions_private').doc(sessionId).set({
    trustedContactsNotified,
    trustedContactsOptedOut,
    notificationSummary,
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });

  logger.info('Processed SOS trusted-contact notifications', { sessionId, ...summary });
  return { trustedContactsNotified, trustedContactsOptedOut, notificationSummary };
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

function destinationForChannel(contact: any, channel: string) {
  if (channel === 'app_push') return contact.appUserUid;
  if (channel === 'email') return contact.emailAddress;
  return contact.phoneNumber;
}

async function isSmsOptedOut(destination: unknown) {
  const docId = smsOptOutDocId(destination);
  if (!docId) return false;

  const snapshot = await db.collection('sos_sms_opt_outs_private').doc(docId).get();
  return snapshot.exists && snapshot.data()?.status === 'opted_out';
}

async function recordSmsOptOutFromDelivery({ destination, errorMessage }: any) {
  const normalized = normalizePhoneNumberForSMS(destination);
  const docId = smsOptOutDocId(normalized);
  if (!docId || !normalized) return;

  const now = new Date();
  await db.collection('sos_sms_opt_outs_private').doc(docId).set(withoutUndefined({
    status: 'opted_out',
    phoneLast4: normalized.slice(-4),
    keyword: 'TWILIO_API_BLOCK',
    errorMessage: cleanString(errorMessage, 500),
    optedOutAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
    deleteAfter: FieldValue.delete(),
  }), { merge: true });
}

export function providerNameForChannel(channel: string) {
  if (channel === 'sms' || channel === 'phone_call' || channel === 'email') return 'twilio';
  if (channel === 'app_push') return 'firestore_app_alert';
  return 'unknown';
}

function notificationProviderEnv() {
  return {
    TWILIO_ACCOUNT_SID: secretValue(twilioAccountSid) || process.env.TWILIO_ACCOUNT_SID,
    TWILIO_API_KEY_SID: secretValue(twilioApiKeySid) || process.env.TWILIO_API_KEY_SID,
    TWILIO_API_KEY_SECRET: secretValue(twilioApiKeySecret) || process.env.TWILIO_API_KEY_SECRET,
    TWILIO_AUTH_TOKEN: secretValue(twilioAuthToken) || process.env.TWILIO_AUTH_TOKEN,
    TWILIO_FROM_NUMBER: secretValue(twilioFromNumber) || process.env.TWILIO_FROM_NUMBER,
    TWILIO_VOICE_TWIML: process.env.TWILIO_VOICE_TWIML,
    TWILIO_EMAIL_FROM_ADDRESS: secretValue(twilioEmailFromAddress) || process.env.TWILIO_EMAIL_FROM_ADDRESS,
    TWILIO_EMAIL_FROM_NAME: process.env.TWILIO_EMAIL_FROM_NAME,
  };
}

function publicWebhookUrl(request: any) {
  const forwardedProto = request.get('x-forwarded-proto');
  const protocol = forwardedProto || request.protocol || 'https';
  const host = request.get('host');
  const path = request.originalUrl || request.url || '';
  return `${protocol}://${host}${path}`;
}
