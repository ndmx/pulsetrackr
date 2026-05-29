'use strict';

const { initializeApp } = require('firebase-admin/app');
const { FieldValue, Timestamp, getFirestore } = require('firebase-admin/firestore');
const { HttpsError, onCall } = require('firebase-functions/v2/https');
const { logger } = require('firebase-functions');
const { defineSecret } = require('firebase-functions/params');
const {
  providerReadiness,
  sendNotificationAttempt,
} = require('./notificationProviders');
const {
  HARD_LIMITS,
  makeIdempotencyKey,
  makeLocationUpdateId,
  privilegedRoleFromClaims,
  redactedContact,
  sanitizeActivationPayload,
  sanitizeLocationUpdatePayload,
  sanitizeResolutionPayload,
} = require('./sosShared');

initializeApp();

const db = getFirestore();
const twilioAccountSid = defineSecret('TWILIO_ACCOUNT_SID');
const twilioApiKeySid = defineSecret('TWILIO_API_KEY_SID');
const twilioApiKeySecret = defineSecret('TWILIO_API_KEY_SECRET');
const twilioFromNumber = defineSecret('TWILIO_FROM_NUMBER');
const sendgridApiKey = defineSecret('SENDGRID_API_KEY');
const sendgridFromEmail = defineSecret('SENDGRID_FROM_EMAIL');
const callableOptions = {
  region: process.env.PULSETRACKR_FUNCTION_REGION || 'us-central1',
  enforceAppCheck: process.env.FUNCTIONS_EMULATOR !== 'true',
  maxInstances: 20,
  secrets: [
    twilioAccountSid,
    twilioApiKeySid,
    twilioApiKeySecret,
    twilioFromNumber,
    sendgridApiKey,
    sendgridFromEmail,
  ],
};

exports.activate_sos = onCall(callableOptions, async (request) => {
  const uid = requireAuth(request);
  const now = new Date();
  const payload = translateErrors(() => sanitizeActivationPayload(request.data || {}, now));
  const idempotencyKey = makeIdempotencyKey(uid, payload.clientSessionId);
  const idempotencyRef = db.collection('sos_idempotency_private').doc(idempotencyKey);
  const rateRef = db.collection('sos_rate_limits_private').doc(uid);
  const sessionRef = db.collection('sos_sessions_private').doc();
  const expiresAt = new Date(now.getTime() + payload.privacy.adminAccessExpiresAfterSeconds * 1000);
  const deleteAfter = retentionDate(now);

  const transactionResult = await db.runTransaction(async (transaction) => {
    const existing = await transaction.get(idempotencyRef);
    if (existing.exists) {
      const data = existing.data();
      return {
        alreadyExisted: true,
        sessionId: data.sessionId,
        trustedContactsNotified: data.trustedContactsAccepted || [],
        expiresAt: data.expiresAt.toDate(),
      };
    }

    await applyActivationRateLimit(transaction, rateRef, now);

    const trustedContactsAccepted = payload.trustedContacts.map((contact) => contact.contactId);
    transaction.set(sessionRef, {
      ownerUid: uid,
      clientSessionId: payload.clientSessionId,
      status: 'active',
      source: payload.source,
      activatedAt: Timestamp.fromDate(payload.activatedAt),
      serverActivatedAt: FieldValue.serverTimestamp(),
      expiresAt: Timestamp.fromDate(expiresAt),
      deleteAfter: Timestamp.fromDate(deleteAfter),
      lastKnownLocation: firestoreLocation(payload.lastKnownLocation),
      recentTrail: payload.recentTrail.map(firestoreLocation),
      directionOfTravel: payload.directionOfTravel,
      trustedContacts: payload.trustedContacts,
      trustedContactsRedacted: payload.trustedContacts.map(redactedContact),
      trustedContactsAccepted,
      notificationSummary: {
        queued: trustedContactsAccepted.length,
        sent: 0,
        failed: 0,
      },
      device: payload.device,
      privacy: payload.privacy,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      lastLocationAt: Timestamp.fromDate(payload.lastKnownLocation.capturedAt),
    });

    transaction.set(idempotencyRef, {
      uid,
      clientSessionId: payload.clientSessionId,
      sessionId: sessionRef.id,
      trustedContactsAccepted,
      expiresAt: Timestamp.fromDate(expiresAt),
      createdAt: FieldValue.serverTimestamp(),
      deleteAfter: Timestamp.fromDate(deleteAfter),
    });

    transaction.set(auditRef(), auditEvent({
      eventType: 'sos_activated',
      actorUid: uid,
      role: 'owner',
      sessionId: sessionRef.id,
      decision: 'allowed',
      reason: 'user_activated_sos',
      redacted: {
        trustedContactCount: payload.trustedContacts.length,
        recentTrailCount: payload.recentTrail.length,
      },
      deleteAfter,
    }));

    return {
      alreadyExisted: false,
      sessionId: sessionRef.id,
      trustedContactsNotified: trustedContactsAccepted,
      expiresAt,
      contacts: payload.trustedContacts,
      deleteAfter,
    };
  });

  if (!transactionResult.alreadyExisted) {
    await enqueueTrustedContactNotifications({
    sessionId: transactionResult.sessionId,
    ownerUid: uid,
    contacts: transactionResult.contacts,
    deleteAfter: transactionResult.deleteAfter,
  });
  }

  return {
    session_id: transactionResult.sessionId,
    trusted_contacts_notified: transactionResult.trustedContactsNotified,
    expires_at: transactionResult.expiresAt.toISOString(),
  };
});

exports.append_sos_location = onCall(callableOptions, async (request) => {
  const uid = requireAuth(request);
  const payload = translateErrors(() => sanitizeLocationUpdatePayload(request.data || {}));
  const sessionRef = db.collection('sos_sessions_private').doc(payload.sessionId);
  const updateRef = db.collection('sos_location_updates_private')
    .doc(makeLocationUpdateId(payload.sessionId, payload.sequenceNumber));
  const now = new Date();

  const result = await db.runTransaction(async (transaction) => {
    const sessionSnap = await transaction.get(sessionRef);
    assertOwnedActiveSession(sessionSnap, uid, now);

    const existingUpdate = await transaction.get(updateRef);
    if (existingUpdate.exists) {
      return { accepted: true, duplicate: true };
    }

    const session = sessionSnap.data();
    transaction.set(updateRef, {
      sessionId: payload.sessionId,
      ownerUid: uid,
      sequenceNumber: payload.sequenceNumber,
      location: firestoreLocation(payload.location),
      capturedAt: Timestamp.fromDate(payload.capturedAt),
      directionOfTravel: payload.directionOfTravel,
      device: payload.device,
      createdAt: FieldValue.serverTimestamp(),
      deleteAfter: session.deleteAfter || Timestamp.fromDate(retentionDate(now)),
    });
    transaction.update(sessionRef, {
      lastKnownLocation: firestoreLocation(payload.location),
      directionOfTravel: payload.directionOfTravel,
      device: payload.device,
      lastLocationAt: Timestamp.fromDate(payload.location.capturedAt),
      updatedAt: FieldValue.serverTimestamp(),
      updateCount: FieldValue.increment(1),
    });
    transaction.set(auditRef(), auditEvent({
      eventType: 'sos_location_appended',
      actorUid: uid,
      role: 'owner',
      sessionId: payload.sessionId,
      decision: 'allowed',
      reason: `sequence:${payload.sequenceNumber}`,
      redacted: { sequenceNumber: payload.sequenceNumber },
      deleteAfter: timestampToDate(session.deleteAfter) || retentionDate(now),
    }));

    return { accepted: true, duplicate: false };
  });

  return { accepted: result.accepted, duplicate: result.duplicate };
});

exports.resolve_sos = onCall(callableOptions, async (request) => {
  const uid = requireAuth(request);
  const payload = translateErrors(() => sanitizeResolutionPayload(request.data || {}));
  const sessionRef = db.collection('sos_sessions_private').doc(payload.sessionId);
  const now = new Date();

  await db.runTransaction(async (transaction) => {
    const sessionSnap = await transaction.get(sessionRef);
    if (!sessionSnap.exists) {
      throw new HttpsError('not-found', 'SOS session not found');
    }
    const session = sessionSnap.data();
    if (session.ownerUid !== uid) {
      throw new HttpsError('permission-denied', 'Only the activating user can resolve this SOS session');
    }

    if (session.status !== 'resolved') {
      transaction.update(sessionRef, withoutUndefined({
        status: 'resolved',
        resolutionReason: payload.reason,
        resolvedAt: Timestamp.fromDate(payload.resolvedAt),
        finalLocation: payload.finalLocation ? firestoreLocation(payload.finalLocation) : undefined,
        updatedAt: FieldValue.serverTimestamp(),
      }));
    }

    transaction.set(auditRef(), auditEvent({
      eventType: 'sos_resolved',
      actorUid: uid,
      role: 'owner',
      sessionId: payload.sessionId,
      decision: 'allowed',
      reason: payload.reason,
      redacted: { wasAlreadyResolved: session.status === 'resolved' },
      deleteAfter: timestampToDate(session.deleteAfter) || retentionDate(now),
    }));
  });

  return { resolved: true };
});

exports.request_sos_session_access = onCall(callableOptions, async (request) => {
  const uid = requireAuth(request);
  const role = privilegedRoleFromClaims(request.auth.token || {});
  const sessionId = typeof request.data?.session_id === 'string' ? request.data.session_id : '';
  const reason = typeof request.data?.reason === 'string' ? request.data.reason.slice(0, 240) : '';
  const now = new Date();

  if (!role) {
    await logAudit({
      eventType: 'privileged_access_requested',
      actorUid: uid,
      role: 'unknown',
      sessionId,
      decision: 'denied',
      reason: reason || 'missing_privileged_claim',
      redacted: {},
      deleteAfter: retentionDate(now),
    });
    throw new HttpsError('permission-denied', 'Privileged SOS access requires an approved responder/admin claim');
  }
  if (!sessionId || !reason) {
    throw new HttpsError('invalid-argument', 'session_id and reason are required');
  }

  const sessionSnap = await db.collection('sos_sessions_private').doc(sessionId).get();
  if (!sessionSnap.exists) {
    await logAudit({
      eventType: 'privileged_access_requested',
      actorUid: uid,
      role,
      sessionId,
      decision: 'denied',
      reason: `${reason}:session_not_found`,
      redacted: {},
      deleteAfter: retentionDate(now),
    });
    throw new HttpsError('not-found', 'SOS session not found');
  }

  const session = sessionSnap.data();
  const expiresAt = timestampToDate(session.expiresAt);
  const active = session.status === 'active' && expiresAt && expiresAt.getTime() > now.getTime();
  if (!active) {
    await logAudit({
      eventType: 'privileged_access_requested',
      actorUid: uid,
      role,
      sessionId,
      decision: 'denied',
      reason: `${reason}:inactive_or_expired`,
      redacted: { status: session.status },
      deleteAfter: timestampToDate(session.deleteAfter) || retentionDate(now),
    });
    throw new HttpsError('failed-precondition', 'Exact SOS access is limited to active, unexpired sessions');
  }

  const grantExpiresAt = new Date(Math.min(
    expiresAt.getTime(),
    now.getTime() + 15 * 60 * 1000,
  ));
  await db.collection('sos_access_grants_private').add({
    actorUid: uid,
    role,
    sessionId,
    reason,
    expiresAt: Timestamp.fromDate(grantExpiresAt),
    createdAt: FieldValue.serverTimestamp(),
    deleteAfter: session.deleteAfter || Timestamp.fromDate(retentionDate(now)),
  });
  await logAudit({
    eventType: 'privileged_access_requested',
    actorUid: uid,
    role,
    sessionId,
    decision: 'allowed',
    reason,
    redacted: { grantExpiresAt: grantExpiresAt.toISOString() },
    deleteAfter: timestampToDate(session.deleteAfter) || retentionDate(now),
  });

  return {
    session_id: sessionId,
    status: session.status,
    activated_at: timestampToIso(session.activatedAt),
    expires_at: timestampToIso(session.expiresAt),
    last_known_location: plainLocation(session.lastKnownLocation),
    direction_of_travel: session.directionOfTravel || null,
    trusted_contacts: session.trustedContactsRedacted || [],
    grant_expires_at: grantExpiresAt.toISOString(),
  };
});

async function enqueueTrustedContactNotifications({ sessionId, ownerUid, contacts, deleteAfter }) {
  if (!contacts.length) {
    return;
  }

  const batch = db.batch();
  const attempts = [];
  for (const contact of contacts) {
    for (const channel of contact.channels) {
      const attemptRef = db.collection('sos_notification_attempts_private').doc();
      const destination = destinationForChannel(contact, channel);
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

  await deliverQueuedNotifications({ sessionId, attempts });
}

async function deliverQueuedNotifications({ sessionId, attempts }) {
  if (!attempts.length) return;

  const results = await Promise.all(attempts.map(async (attempt) => {
    const sentAt = new Date();
    const result = await sendNotificationAttempt({
      sessionId,
      contact: attempt.contact,
      channel: attempt.channel,
      destination: attempt.destination,
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

    return result;
  }));

  const summary = results.reduce((counts, result) => {
    if (result.status === 'sent') counts.sent += 1;
    else if (result.status === 'failed') counts.failed += 1;
    else counts.skipped += 1;
    return counts;
  }, { sent: 0, failed: 0, skipped: 0 });

  await db.collection('sos_sessions_private').doc(sessionId).set({
    notificationSummary: {
      queued: attempts.length,
      sent: summary.sent,
      failed: summary.failed,
      skipped: summary.skipped,
    },
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });

  logger.info('Processed SOS trusted-contact notifications', { sessionId, ...summary });
}

function destinationForChannel(contact, channel) {
  if (channel === 'email') return contact.emailAddress;
  return contact.phoneNumber;
}

function providerNameForChannel(channel) {
  if (channel === 'email') return 'sendgrid';
  if (channel === 'sms' || channel === 'phone_call') return 'twilio';
  return 'unknown';
}

function notificationProviderEnv() {
  return {
    TWILIO_ACCOUNT_SID: secretValue(twilioAccountSid) || process.env.TWILIO_ACCOUNT_SID,
    TWILIO_API_KEY_SID: secretValue(twilioApiKeySid) || process.env.TWILIO_API_KEY_SID,
    TWILIO_API_KEY_SECRET: secretValue(twilioApiKeySecret) || process.env.TWILIO_API_KEY_SECRET,
    TWILIO_AUTH_TOKEN: process.env.TWILIO_AUTH_TOKEN,
    TWILIO_FROM_NUMBER: secretValue(twilioFromNumber) || process.env.TWILIO_FROM_NUMBER,
    TWILIO_VOICE_TWIML: process.env.TWILIO_VOICE_TWIML,
    SENDGRID_API_KEY: secretValue(sendgridApiKey) || process.env.SENDGRID_API_KEY,
    SENDGRID_FROM_EMAIL: secretValue(sendgridFromEmail) || process.env.SENDGRID_FROM_EMAIL,
    SENDGRID_FROM_NAME: process.env.SENDGRID_FROM_NAME,
  };
}

function secretValue(secret) {
  try {
    return secret.value();
  } catch {
    return null;
  }
}

async function applyActivationRateLimit(transaction, rateRef, now) {
  const snap = await transaction.get(rateRef);
  const windowStartsAt = new Date(now.getTime() - HARD_LIMITS.activationWindowSeconds * 1000);
  const recentActivations = snap.exists
    ? (snap.data().recentActivations || [])
      .map(timestampToDate)
      .filter((date) => date && date.getTime() >= windowStartsAt.getTime())
    : [];
  const latest = recentActivations.at(-1);

  if (latest && now.getTime() - latest.getTime() < HARD_LIMITS.activationCooldownSeconds * 1000) {
    throw new HttpsError('resource-exhausted', 'Please wait before starting another SOS session');
  }
  if (recentActivations.length >= HARD_LIMITS.activationWindowLimit) {
    throw new HttpsError('resource-exhausted', 'Too many SOS activations in the last hour');
  }

  recentActivations.push(now);
  transaction.set(rateRef, {
    recentActivations: recentActivations.map((date) => Timestamp.fromDate(date)),
    updatedAt: FieldValue.serverTimestamp(),
    deleteAfter: Timestamp.fromDate(retentionDate(now)),
  }, { merge: true });
}

function assertOwnedActiveSession(sessionSnap, uid, now) {
  if (!sessionSnap.exists) {
    throw new HttpsError('not-found', 'SOS session not found');
  }
  const session = sessionSnap.data();
  if (session.ownerUid !== uid) {
    throw new HttpsError('permission-denied', 'This SOS session belongs to another user');
  }
  if (session.status !== 'active') {
    throw new HttpsError('failed-precondition', 'SOS session is no longer active');
  }
  const expiresAt = timestampToDate(session.expiresAt);
  if (!expiresAt || expiresAt.getTime() <= now.getTime()) {
    throw new HttpsError('failed-precondition', 'SOS session has expired');
  }
}

function requireAuth(request) {
  if (!request.auth?.uid) {
    throw new HttpsError('unauthenticated', 'Sign in is required for SOS');
  }
  return request.auth.uid;
}

function translateErrors(callback) {
  try {
    return callback();
  } catch (error) {
    if (error instanceof HttpsError) {
      throw error;
    }
    if (error.code === 'invalid-argument') {
      throw new HttpsError('invalid-argument', error.message);
    }
    throw error;
  }
}

function auditRef() {
  return db.collection('sos_access_audit').doc();
}

function auditEvent({ eventType, actorUid, role, sessionId, decision, reason, redacted, deleteAfter }) {
  return withoutUndefined({
    eventType,
    actorUid,
    role,
    sessionId,
    decision,
    reason,
    redacted,
    createdAt: FieldValue.serverTimestamp(),
    deleteAfter: Timestamp.fromDate(deleteAfter),
  });
}

async function logAudit(event) {
  await auditRef().set(auditEvent(event));
}

function firestoreLocation(location) {
  return withoutUndefined({
    latitude: location.latitude,
    longitude: location.longitude,
    horizontalAccuracyMeters: location.horizontalAccuracyMeters,
    altitudeMeters: location.altitudeMeters,
    speedMetersPerSecond: location.speedMetersPerSecond,
    courseDegrees: location.courseDegrees,
    capturedAt: Timestamp.fromDate(location.capturedAt),
  });
}

function plainLocation(location) {
  if (!location) return null;
  return withoutUndefined({
    latitude: location.latitude,
    longitude: location.longitude,
    horizontal_accuracy_meters: location.horizontalAccuracyMeters,
    altitude_meters: location.altitudeMeters,
    speed_meters_per_second: location.speedMetersPerSecond,
    course_degrees: location.courseDegrees,
    captured_at: timestampToIso(location.capturedAt),
  });
}

function retentionDate(now) {
  return new Date(now.getTime() + HARD_LIMITS.retentionSeconds * 1000);
}

function timestampToDate(value) {
  if (!value) return null;
  if (value instanceof Date) return value;
  if (typeof value.toDate === 'function') return value.toDate();
  if (typeof value === 'string') {
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? null : date;
  }
  return null;
}

function timestampToIso(value) {
  const date = timestampToDate(value);
  return date ? date.toISOString() : null;
}

function withoutUndefined(object) {
  return Object.fromEntries(Object.entries(object).filter(([, value]) => value !== undefined));
}
