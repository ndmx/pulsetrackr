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
const { encodeGeohash } = require('./geohash');
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
const CONCERN_RATE_LIMIT = Object.freeze({
  cooldownSeconds: 10,
  windowSeconds: 60 * 60,
  windowLimit: 30,
  cooldownMessage: 'Please wait before reporting another concern',
  windowMessage: 'Too many concerns submitted in the last hour. Try again later.',
});

// Wire signal -> public counter field. Keys match CommunitySignal.rawValue (iOS).
const SIGNAL_COUNTER_FIELD = Object.freeze({
  seen: 'confirmations',
  notSeen: 'disputes',
  unsafe: 'unsafe_reports',
  roadBlocked: 'blocked_reports',
  cleared: 'cleared_reports',
});
const INCIDENT_CONCERN_REASONS = new Set([
  'false_report',
  'offensive_content',
  'private_information',
  'dangerous_advice',
  'spam_or_abuse',
]);

exports.submit_incident = onCall(callableOptions, async (request) => {
  const uid = requireAuth(request);
  const now = new Date();
  const payload = sanitizeIncidentPayload(request.data || {}, uid);
  const privateRef = db.collection('safety_reports_private').doc();
  const publicRef = db.collection('safety_incidents_public').doc(privateRef.id);
  const rateRef = feedRateLimitRef(uid, 'submit');
  const publicCoordinate = publicIncidentCoordinate(payload);

  await db.runTransaction(async (transaction) => {
    await enforceRateLimit(transaction, rateRef, now, SUBMISSION_RATE_LIMIT);

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
      latitude: publicCoordinate?.latitude,
      longitude: publicCoordinate?.longitude,
      geohash: publicCoordinate
        ? encodeGeohash(publicCoordinate.latitude, publicCoordinate.longitude)
        : undefined,
      confirmations: 1,
      disputes: 0,
      unsafe_reports: 0,
      blocked_reports: 0,
      cleared_reports: 0,
      official_updates: 0,
      evidence_summary: {
        photo_count: payload.evidence.filter((item) => item.kind === 'photo').length,
        voice_count: payload.evidence.filter((item) => item.kind === 'voice').length,
      },
      reported_at: Timestamp.fromDate(now),
      updated_at: FieldValue.serverTimestamp(),
      source: payload.source,
    }));
  });

  return {
    incident_id: publicRef.id,
    evidence_count: payload.evidence.length,
  };
});

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

exports.record_incident_signal = onCall(callableOptions, async (request) => {
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

  const publicRef = db.collection('safety_incidents_public').doc(incidentId);
  const rateRef = feedRateLimitRef(uid, 'signal');

  const result = await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(publicRef);
    if (!snapshot.exists) {
      throw new HttpsError('not-found', 'Incident not found');
    }
    await enforceRateLimit(transaction, rateRef, now, SIGNAL_RATE_LIMIT);

    const incident = snapshot.data();
    if (incident.status === 'Resolved') {
      return { status: incident.status, severity: incident.severity, applied: false };
    }

    // Status/severity are derived server-side from the stored counters; the
    // client is not trusted to set them. See firestore.rules (public feed is
    // read-only to clients) — this callable is the only write path.
    const derived = deriveSignalOutcome(signal, incident);
    transaction.update(publicRef, withoutUndefined({
      [SIGNAL_COUNTER_FIELD[signal]]: FieldValue.increment(1),
      status: derived.status,
      severity: derived.severity,
      updated_at: FieldValue.serverTimestamp(),
    }));

    return { status: derived.status, severity: derived.severity, applied: true };
  });

  return {
    incident_id: incidentId,
    status: result.status,
    severity: result.severity,
    applied: result.applied,
  };
});

exports.record_incident_concern = onCall(callableOptions, async (request) => {
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

  const publicRef = db.collection('safety_incidents_public').doc(incidentId);
  const concernRef = db.collection('safety_incident_concerns_private').doc();
  const rateRef = feedRateLimitRef(uid, 'concern');

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

  return {
    incident_id: incidentId,
    recorded: true,
  };
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

function feedRateLimitRef(uid, action) {
  return db.collection('safety_feed_rate_limits_private').doc(`${uid}_${action}`);
}

// Sliding-window + cooldown limiter. Must be called before any writes in the
// enclosing transaction (it issues a read), and persists the updated window.
async function enforceRateLimit(transaction, rateRef, now, limit) {
  const snap = await transaction.get(rateRef);
  const windowStartsAt = new Date(now.getTime() - limit.windowSeconds * 1000);
  const recentEvents = snap.exists
    ? (snap.data().recentEvents || [])
      .map(timestampToDate)
      .filter((date) => date && date.getTime() >= windowStartsAt.getTime())
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
    recentEvents: recentEvents.map((date) => Timestamp.fromDate(date)),
    updatedAt: FieldValue.serverTimestamp(),
    deleteAfter: Timestamp.fromDate(retentionDate(now)),
  }, { merge: true });
}

// Server-authoritative port of the iOS IncidentStore signal rules. Counters are
// incremented separately via FieldValue.increment; the +1 here mirrors the
// post-increment state the client computes locally.
function deriveSignalOutcome(signal, incident) {
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

function numberOr(value, fallback) {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
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

function sanitizeIncidentPayload(data, uid) {
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
    ? data.evidence.slice(0, 4).map((item) => sanitizeIncidentEvidence(item, uid, clientRef))
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

function sanitizeIncidentCoordinate(data) {
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

function hasCoordinateValue(value) {
  return value !== undefined
    && value !== null
    && !(typeof value === 'string' && value.trim() === '');
}

function publicIncidentCoordinate(payload) {
  if (payload.latitude === undefined || payload.longitude === undefined) {
    return undefined;
  }

  return payload.useApproximateLocation
    ? approximateCoordinate(payload.latitude, payload.longitude)
    : { latitude: payload.latitude, longitude: payload.longitude };
}

function sanitizeIncidentEvidence(item, uid, clientRef) {
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

function approximateCoordinate(latitude, longitude) {
  const minimumMeters = 140;
  const maximumMeters = 260;
  const distance = minimumMeters + Math.random() * (maximumMeters - minimumMeters);
  const bearing = Math.random() * 2 * Math.PI;
  const latitudeMeters = 111320;
  const longitudeMeters = Math.max(Math.cos(latitude * Math.PI / 180) * latitudeMeters, 1);
  return {
    latitude: latitude + (Math.cos(bearing) * distance / latitudeMeters),
    longitude: longitude + (Math.sin(bearing) * distance / longitudeMeters),
  };
}

function cleanString(value, maxLength) {
  return typeof value === 'string' ? value.trim().slice(0, maxLength) : '';
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

if (process.env.NODE_ENV === 'test') {
  exports.__test = {
    publicIncidentCoordinate,
    sanitizeIncidentPayload,
    deriveSignalOutcome,
    SIGNAL_COUNTER_FIELD,
    INCIDENT_CONCERN_REASONS,
  };
}
