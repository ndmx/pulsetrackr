'use strict';

const crypto = require('node:crypto');
const { HttpsError, onCall } = require('firebase-functions/v2/https');
const { logger } = require('firebase-functions');
const { db, FieldValue, Timestamp } = require('../shared/admin');
const { callableOptions } = require('../shared/config');
const {
  withoutUndefined,
  cleanString,
  numberOr,
  timestampToDate,
  timestampToIso,
  requireAuth,
  translateErrors,
  retentionDate,
} = require('../shared/util');
const { appendAuditToTransaction, logAudit } = require('../shared/audit');
const { decryptPrivateJson, encryptPrivateJson, privateLocationJson } = require('../shared/envelope');
const {
  HARD_LIMITS,
  makeIdempotencyKey,
  makeLocationUpdateId,
  redactedContact,
  sanitizeActivationPayload,
  sanitizeLocationUpdatePayload,
  sanitizeResolutionPayload,
} = require('../sosShared');
const { enqueueSosNotificationTask, providerNameForChannel } = require('../notifications');

const APP_TRUSTED_CONTACT_INVITE_TTL_SECONDS = 3 * 24 * 60 * 60;
const APP_TRUSTED_CONTACT_ALERT_LIMIT = 10;

let sosRepository;

exports.activate_sos = onCall(callableOptions, async (request) => {
  const uid = requireAuth(request);
  const now = new Date();
  const payload = translateErrors(() => sanitizeActivationPayload(request.data || {}, now));
  return sosRepository.activate({ uid, now, payload });
});

exports.create_app_trusted_contact_invite = onCall(callableOptions, async (request) => {
  const uid = requireAuth(request);
  const now = new Date();
  const ownerDisplayName = cleanString(request.data?.owner_display_name, 80) || 'PulseTrackr user';
  return sosRepository.createAppTrustedContactInvite({ uid, now, ownerDisplayName });
});

exports.accept_app_trusted_contact_invite = onCall(callableOptions, async (request) => {
  const trustedContactUid = requireAuth(request);
  const now = new Date();
  const inviteCode = normalizeAppTrustedContactInviteCode(request.data?.invite_code);
  const trustedContactDisplayName = cleanString(request.data?.trusted_contact_display_name, 80) || 'Trusted contact';
  if (!inviteCode) {
    throw new HttpsError('invalid-argument', 'invite_code is required');
  }

  return sosRepository.acceptAppTrustedContactInvite({
    trustedContactUid,
    now,
    inviteCode,
    trustedContactDisplayName,
  });
});

exports.list_app_trusted_contacts = onCall(callableOptions, async (request) => {
  const uid = requireAuth(request);
  return sosRepository.listAppTrustedContacts(uid);
});

exports.revoke_app_trusted_contact = onCall(callableOptions, async (request) => {
  const uid = requireAuth(request);
  const relationshipId = cleanString(request.data?.relationship_id, 160);
  if (!relationshipId) {
    throw new HttpsError('invalid-argument', 'relationship_id is required');
  }

  return sosRepository.revokeAppTrustedContact({ uid, relationshipId });
});

exports.append_sos_location = onCall(callableOptions, async (request) => {
  const uid = requireAuth(request);
  const payload = translateErrors(() => sanitizeLocationUpdatePayload(request.data || {}));
  return sosRepository.appendLocation({ uid, payload, now: new Date() });
});

exports.resolve_sos = onCall(callableOptions, async (request) => {
  const uid = requireAuth(request);
  const payload = translateErrors(() => sanitizeResolutionPayload(request.data || {}));
  return sosRepository.resolve({ uid, payload, now: new Date() });
});

class SOSRepository {
  async activate({ uid, now, payload }) {
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
      const sessionSnap = await transaction.get(db.collection('sos_sessions_private').doc(data.sessionId));
      const session = sessionSnap.exists ? sessionSnap.data() : {};
      const sagaStatus = session.notificationSagaStatus;
      return {
        alreadyExisted: true,
        sessionId: data.sessionId,
        trustedContactsNotified: session.trustedContactsNotified || [],
        trustedContactsOptedOut: session.trustedContactsOptedOut || [],
        appTrustedContactsNotified: session.appTrustedContactsNotified || [],
        notificationSummary: session.notificationSummary || { queued: 0, sent: 0, failed: 0, skipped: 0, optedOut: 0 },
        expiresAt: data.expiresAt.toDate(),
        shouldEnqueueNotification: !sagaStatus || sagaStatus === 'failed',
        contacts: session.trustedContacts || [],
        location: plaintextSessionLocation(session, data.sessionId),
        directionOfTravel: session.directionOfTravel,
        deleteAfter: timestampToDate(session.deleteAfter) || retentionDate(now),
      };
    }

    await applyActivationRateLimit(transaction, rateRef, now);

    const trustedContactsAccepted = payload.trustedContacts.map((contact) => contact.contactId);
    await appendAuditToTransaction(transaction, {
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
    });

    transaction.set(sessionRef, {
      ownerUid: uid,
      clientSessionId: payload.clientSessionId,
      status: 'active',
      source: payload.source,
      activatedAt: Timestamp.fromDate(payload.activatedAt),
      serverActivatedAt: FieldValue.serverTimestamp(),
      expiresAt: Timestamp.fromDate(expiresAt),
      deleteAfter: Timestamp.fromDate(deleteAfter),
      lastKnownLocationEncrypted: encryptPrivateJson(
        privateLocationJson(payload.lastKnownLocation),
        encryptedLocationAad(sessionRef.id, uid, 'lastKnownLocation'),
      ),
      recentTrailEncrypted: encryptPrivateJson(
        payload.recentTrail.map(privateLocationJson),
        encryptedLocationAad(sessionRef.id, uid, 'recentTrail'),
      ),
      locationEncryption: {
        version: 1,
        scheme: 'local_envelope_aes_256_gcm',
        keyVersion: process.env.SOS_ENVELOPE_KEY_VERSION || 'v1',
      },
      directionOfTravel: payload.directionOfTravel,
      trustedContacts: payload.trustedContacts,
      trustedContactsRedacted: payload.trustedContacts.map(redactedContact),
      trustedContactsAccepted,
      trustedContactsNotified: [],
      trustedContactsOptedOut: [],
      notificationSummary: {
        queued: trustedContactsAccepted.length,
        sent: 0,
        failed: 0,
        skipped: 0,
        optedOut: 0,
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

    return {
      alreadyExisted: false,
      sessionId: sessionRef.id,
      expiresAt,
      contacts: payload.trustedContacts,
      location: payload.lastKnownLocation,
      directionOfTravel: payload.directionOfTravel,
      deleteAfter,
    };
  });

  let notificationSummary = transactionResult.notificationSummary || { queued: 0, sent: 0, failed: 0, skipped: 0, optedOut: 0 };
  let trustedContactsNotified = transactionResult.trustedContactsNotified || [];
  let trustedContactsOptedOut = transactionResult.trustedContactsOptedOut || [];
  let appTrustedContactsNotified = transactionResult.appTrustedContactsNotified || [];
  if (!transactionResult.alreadyExisted || transactionResult.shouldEnqueueNotification) {
    const delivery = await enqueueSosNotificationTask({
      sessionId: transactionResult.sessionId,
      ownerUid: uid,
      contacts: transactionResult.contacts,
      location: transactionResult.location,
      directionOfTravel: transactionResult.directionOfTravel,
      deleteAfter: transactionResult.deleteAfter,
    });
    notificationSummary = delivery.notificationSummary;
    await db.collection('sos_sessions_private').doc(transactionResult.sessionId).set({
      notificationSummary,
      notificationSagaStatus: 'enqueued',
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
  }

  return {
    session_id: transactionResult.sessionId,
    trusted_contacts_notified: trustedContactsNotified,
    trusted_contacts_opted_out: trustedContactsOptedOut,
    app_trusted_contacts_notified: appTrustedContactsNotified,
    notification_summary: notificationSummary,
    expires_at: transactionResult.expiresAt.toISOString(),
  };
  }

  async createAppTrustedContactInvite({ uid, now, ownerDisplayName }) {
  const inviteCode = makeAppTrustedContactInviteCode();
  const inviteRef = db.collection('sos_app_trusted_contact_invites_private').doc(appTrustedContactInviteDocId(inviteCode));
  const expiresAt = new Date(now.getTime() + APP_TRUSTED_CONTACT_INVITE_TTL_SECONDS * 1000);

  await inviteRef.set({
    ownerUid: uid,
    ownerDisplayName,
    status: 'pending',
    createdAt: FieldValue.serverTimestamp(),
    expiresAt: Timestamp.fromDate(expiresAt),
    deleteAfter: Timestamp.fromDate(new Date(expiresAt.getTime() + HARD_LIMITS.retentionSeconds * 1000)),
  });

  await logAudit({
    eventType: 'app_trusted_contact_invite_created',
    actorUid: uid,
    role: 'owner',
    sessionId: null,
    decision: 'allowed',
    reason: 'owner_created_one_way_app_contact_invite',
    redacted: {
      inviteId: inviteRef.id,
      expiresAt: expiresAt.toISOString(),
    },
    deleteAfter: retentionDate(now),
  });

  return {
    invite_id: inviteRef.id,
    invite_code: inviteCode,
    expires_at: expiresAt.toISOString(),
  };
  }

  async acceptAppTrustedContactInvite({ trustedContactUid, now, inviteCode, trustedContactDisplayName }) {
  const inviteRef = db.collection('sos_app_trusted_contact_invites_private').doc(appTrustedContactInviteDocId(inviteCode));
  const result = await db.runTransaction(async (transaction) => {
    const inviteSnap = await transaction.get(inviteRef);
    if (!inviteSnap.exists) {
      throw new HttpsError('not-found', 'Trusted contact invite not found');
    }

    const invite = inviteSnap.data();
    const expiresAt = timestampToDate(invite.expiresAt);
    if (invite.status !== 'pending') {
      throw new HttpsError('failed-precondition', 'Trusted contact invite was already used');
    }
    if (!expiresAt || expiresAt.getTime() <= now.getTime()) {
      throw new HttpsError('failed-precondition', 'Trusted contact invite has expired');
    }
    if (invite.ownerUid === trustedContactUid) {
      throw new HttpsError('failed-precondition', 'You cannot accept your own trusted contact invite');
    }

    const relationshipId = appTrustedContactRelationshipId(invite.ownerUid, trustedContactUid);
    const relationshipRef = db.collection('sos_app_trusted_contacts_private').doc(relationshipId);
    await appendAuditToTransaction(transaction, {
      eventType: 'app_trusted_contact_invite_accepted',
      actorUid: trustedContactUid,
      role: 'trusted_contact',
      sessionId: null,
      decision: 'allowed',
      reason: 'trusted_contact_accepted_one_way_app_alerts',
      redacted: {
        inviteId: inviteRef.id,
        relationshipId,
        ownerUid: invite.ownerUid,
      },
      deleteAfter: retentionDate(now),
    });

    transaction.set(relationshipRef, {
      ownerUid: invite.ownerUid,
      trustedContactUid,
      ownerDisplayName: invite.ownerDisplayName || 'PulseTrackr user',
      trustedContactDisplayName,
      status: 'accepted',
      inviteId: inviteRef.id,
      acceptedAt: FieldValue.serverTimestamp(),
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      revokedAt: FieldValue.delete(),
      revokedByUid: FieldValue.delete(),
    }, { merge: true });
    transaction.update(inviteRef, {
      status: 'accepted',
      acceptedByUid: trustedContactUid,
      acceptedAt: FieldValue.serverTimestamp(),
      relationshipId,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return {
      relationshipId,
      ownerUid: invite.ownerUid,
      ownerDisplayName: invite.ownerDisplayName || 'PulseTrackr user',
      trustedContactDisplayName,
    };
  });

  return {
    relationship_id: result.relationshipId,
    owner_uid: result.ownerUid,
    owner_display_name: result.ownerDisplayName,
    trusted_contact_display_name: result.trustedContactDisplayName,
    direction: 'owner_to_trusted_contact',
    status: 'accepted',
  };
  }

  async listAppTrustedContacts(uid) {
  const [outgoingSnap, incomingSnap] = await Promise.all([
    db.collection('sos_app_trusted_contacts_private').where('ownerUid', '==', uid).get(),
    db.collection('sos_app_trusted_contacts_private').where('trustedContactUid', '==', uid).get(),
  ]);

  const outgoing = outgoingSnap.docs
    .map((doc) => appTrustedContactResponse(doc))
    .filter((contact) => contact.status === 'accepted');
  const incoming = incomingSnap.docs
    .map((doc) => appTrustedContactResponse(doc))
    .filter((contact) => contact.status === 'accepted');

  return { outgoing, incoming };
  }

  async revokeAppTrustedContact({ uid, relationshipId }) {
  const relationshipRef = db.collection('sos_app_trusted_contacts_private').doc(relationshipId);
  await db.runTransaction(async (transaction) => {
    const relationshipSnap = await transaction.get(relationshipRef);
    if (!relationshipSnap.exists) {
      throw new HttpsError('not-found', 'Trusted app contact not found');
    }

    const relationship = relationshipSnap.data();
    if (relationship.ownerUid !== uid && relationship.trustedContactUid !== uid) {
      throw new HttpsError('permission-denied', 'Only either person in this trusted contact relationship can revoke it');
    }

    await appendAuditToTransaction(transaction, {
      eventType: 'app_trusted_contact_revoked',
      actorUid: uid,
      role: relationship.ownerUid === uid ? 'owner' : 'trusted_contact',
      sessionId: null,
      decision: 'allowed',
      reason: 'one_way_app_contact_revoked',
      redacted: { relationshipId },
      deleteAfter: retentionDate(new Date()),
    });

    transaction.update(relationshipRef, {
      status: 'revoked',
      revokedByUid: uid,
      revokedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });

  return { revoked: true };
  }

  async appendLocation({ uid, payload, now }) {
  const sessionRef = db.collection('sos_sessions_private').doc(payload.sessionId);
  const updateRef = db.collection('sos_location_updates_private')
    .doc(makeLocationUpdateId(payload.sessionId, payload.sequenceNumber));

  const result = await db.runTransaction(async (transaction) => {
    const sessionSnap = await transaction.get(sessionRef);
    assertOwnedActiveSession(sessionSnap, uid, now);

    const existingUpdate = await transaction.get(updateRef);
    if (existingUpdate.exists) {
      return { accepted: true, duplicate: true };
    }

    const session = sessionSnap.data();
    await appendAuditToTransaction(transaction, {
      eventType: 'sos_location_appended',
      actorUid: uid,
      role: 'owner',
      sessionId: payload.sessionId,
      decision: 'allowed',
      reason: `sequence:${payload.sequenceNumber}`,
      redacted: { sequenceNumber: payload.sequenceNumber },
      deleteAfter: timestampToDate(session.deleteAfter) || retentionDate(now),
    });

    transaction.set(updateRef, {
      sessionId: payload.sessionId,
      ownerUid: uid,
      sequenceNumber: payload.sequenceNumber,
      locationEncrypted: encryptPrivateJson(
        privateLocationJson(payload.location),
        encryptedLocationAad(payload.sessionId, uid, 'locationUpdate', { sequenceNumber: payload.sequenceNumber }),
      ),
      capturedAt: Timestamp.fromDate(payload.capturedAt),
      directionOfTravel: payload.directionOfTravel,
      device: payload.device,
      createdAt: FieldValue.serverTimestamp(),
      deleteAfter: session.deleteAfter || Timestamp.fromDate(retentionDate(now)),
    });
    transaction.update(sessionRef, {
      lastKnownLocationEncrypted: encryptPrivateJson(
        privateLocationJson(payload.location),
        encryptedLocationAad(payload.sessionId, uid, 'lastKnownLocation'),
      ),
      directionOfTravel: payload.directionOfTravel,
      device: payload.device,
      lastLocationAt: Timestamp.fromDate(payload.location.capturedAt),
      updatedAt: FieldValue.serverTimestamp(),
      updateCount: FieldValue.increment(1),
    });
    return {
      accepted: true,
      duplicate: false,
      deleteAfter: timestampToDate(session.deleteAfter) || retentionDate(now),
    };
  });

  if (result.accepted && !result.duplicate) {
    await updateAppTrustedContactAlerts({
      sessionId: payload.sessionId,
      ownerUid: uid,
      location: payload.location,
      directionOfTravel: payload.directionOfTravel,
      deleteAfter: result.deleteAfter,
    });
  }

  return { accepted: result.accepted, duplicate: result.duplicate };
  }

  async resolve({ uid, payload, now }) {
  const sessionRef = db.collection('sos_sessions_private').doc(payload.sessionId);

  const result = await db.runTransaction(async (transaction) => {
    const sessionSnap = await transaction.get(sessionRef);
    if (!sessionSnap.exists) {
      throw new HttpsError('not-found', 'SOS session not found');
    }
    const session = sessionSnap.data();
    if (session.ownerUid !== uid) {
      throw new HttpsError('permission-denied', 'Only the activating user can resolve this SOS session');
    }

    await appendAuditToTransaction(transaction, {
      eventType: 'sos_resolved',
      actorUid: uid,
      role: 'owner',
      sessionId: payload.sessionId,
      decision: 'allowed',
      reason: payload.reason,
      redacted: { wasAlreadyResolved: session.status === 'resolved' },
      deleteAfter: timestampToDate(session.deleteAfter) || retentionDate(now),
    });

    if (session.status !== 'resolved') {
      transaction.update(sessionRef, withoutUndefined({
        status: 'resolved',
        resolutionReason: payload.reason,
        resolvedAt: Timestamp.fromDate(payload.resolvedAt),
        finalLocationEncrypted: payload.finalLocation
          ? encryptPrivateJson(
            privateLocationJson(payload.finalLocation),
            encryptedLocationAad(payload.sessionId, uid, 'finalLocation'),
          )
          : undefined,
        updatedAt: FieldValue.serverTimestamp(),
      }));
    }

    return {
      deleteAfter: timestampToDate(session.deleteAfter) || retentionDate(now),
      finalLocation: payload.finalLocation,
    };
  });

  await resolveAppTrustedContactAlerts({
    sessionId: payload.sessionId,
    ownerUid: uid,
    finalLocation: result.finalLocation,
    deleteAfter: result.deleteAfter,
  });

  return { resolved: true };
  }
}

sosRepository = new SOSRepository();

async function enqueueAppTrustedContactAlerts({ sessionId, ownerUid, location, directionOfTravel, deleteAfter }) {
  const relationships = await acceptedOutgoingAppTrustedContacts(ownerUid);
  if (!relationships.length) {
    return {
      appTrustedContactsNotified: [],
      notificationSummary: { queued: 0, sent: 0, failed: 0, skipped: 0, optedOut: 0 },
    };
  }

  const batch = db.batch();
  const appTrustedContactsNotified = [];
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

async function updateAppTrustedContactAlerts({ sessionId, ownerUid, location, directionOfTravel, deleteAfter }) {
  const relationships = await acceptedOutgoingAppTrustedContacts(ownerUid);
  if (!relationships.length) return;

  const batch = db.batch();
  for (const relationship of relationships.slice(0, APP_TRUSTED_CONTACT_ALERT_LIMIT)) {
    batch.set(appAlertRef(sessionId, relationship.id), withoutUndefined({
      sessionId,
      ownerUid,
      recipientUid: relationship.trustedContactUid,
      relationshipId: relationship.id,
      status: 'active',
      lastKnownLocation: firestoreLocationCompat(location),
      directionOfTravel,
      updatedAt: FieldValue.serverTimestamp(),
      deleteAfter: Timestamp.fromDate(deleteAfter),
    }), { merge: true });
  }
  await batch.commit();
}

async function resolveAppTrustedContactAlerts({ sessionId, ownerUid, finalLocation, deleteAfter }) {
  const relationships = await acceptedOutgoingAppTrustedContacts(ownerUid);
  if (!relationships.length) return;

  const batch = db.batch();
  for (const relationship of relationships.slice(0, APP_TRUSTED_CONTACT_ALERT_LIMIT)) {
    batch.set(appAlertRef(sessionId, relationship.id), withoutUndefined({
      sessionId,
      ownerUid,
      recipientUid: relationship.trustedContactUid,
      relationshipId: relationship.id,
      status: 'resolved',
      finalLocation: finalLocation ? firestoreLocationCompat(finalLocation) : undefined,
      resolvedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      deleteAfter: Timestamp.fromDate(deleteAfter),
    }), { merge: true });
  }
  await batch.commit();
}

async function acceptedOutgoingAppTrustedContacts(ownerUid) {
  const snapshot = await db.collection('sos_app_trusted_contacts_private').where('ownerUid', '==', ownerUid).get();
  return snapshot.docs
    .map((doc) => ({ id: doc.id, ...doc.data() }))
    .filter((relationship) => relationship.status === 'accepted' && relationship.trustedContactUid)
    .slice(0, APP_TRUSTED_CONTACT_ALERT_LIMIT);
}

function appAlertRef(sessionId, relationshipId) {
  return db.collection('sos_app_alerts_private').doc(`${sessionId}_${relationshipId}`);
}

function appAlertPayload({ sessionId, relationship, location, directionOfTravel, status, deleteAfter }) {
  return withoutUndefined({
    sessionId,
    ownerUid: relationship.ownerUid,
    recipientUid: relationship.trustedContactUid,
    relationshipId: relationship.id,
    ownerDisplayName: relationship.ownerDisplayName,
    trustedContactDisplayName: relationship.trustedContactDisplayName,
    status,
    lastKnownLocation: firestoreLocationCompat(location),
    directionOfTravel,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
    deleteAfter: Timestamp.fromDate(deleteAfter),
  });
}

function combineNotificationSummaries(first, second) {
  return {
    queued: numberOr(first?.queued, 0) + numberOr(second?.queued, 0),
    sent: numberOr(first?.sent, 0) + numberOr(second?.sent, 0),
    failed: numberOr(first?.failed, 0) + numberOr(second?.failed, 0),
    skipped: numberOr(first?.skipped, 0) + numberOr(second?.skipped, 0),
    optedOut: numberOr(first?.optedOut ?? first?.opted_out, 0) + numberOr(second?.optedOut ?? second?.opted_out, 0),
  };
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

function makeAppTrustedContactInviteCode() {
  let code = '';
  while (code.length < 12) {
    code += crypto.randomBytes(9).toString('base64url').replace(/[^a-zA-Z0-9]/g, '');
  }
  return code.slice(0, 12).toUpperCase();
}

function normalizeAppTrustedContactInviteCode(value) {
  return cleanString(value, 40).replace(/[^a-zA-Z0-9]/g, '').toUpperCase();
}

function appTrustedContactInviteDocId(inviteCode) {
  return crypto.createHash('sha256').update(`app_trusted_contact_invite:${inviteCode}`).digest('hex');
}

function appTrustedContactRelationshipId(ownerUid, trustedContactUid) {
  return crypto
    .createHash('sha256')
    .update(`app_trusted_contact:${ownerUid}:${trustedContactUid}`)
    .digest('hex');
}

function appTrustedContactResponse(doc) {
  const data = doc.data();
  return {
    relationship_id: doc.id,
    owner_uid: data.ownerUid,
    trusted_contact_uid: data.trustedContactUid,
    owner_display_name: data.ownerDisplayName || 'PulseTrackr user',
    trusted_contact_display_name: data.trustedContactDisplayName || 'Trusted contact',
    status: data.status || 'unknown',
    accepted_at: timestampToIso(data.acceptedAt),
  };
}

function plaintextSessionLocation(session, sessionId) {
  if (session.lastKnownLocationEncrypted) {
    return decryptPrivateJson(
      session.lastKnownLocationEncrypted,
      encryptedLocationAad(sessionId, session.ownerUid, 'lastKnownLocation'),
    );
  }
  return session.lastKnownLocation || null;
}

function encryptedLocationAad(sessionId, ownerUid, field, extra = {}) {
  return {
    domain: 'pulsetrackr.sos.location',
    sessionId,
    ownerUid,
    field,
    ...extra,
  };
}

function firestoreLocationCompat(location) {
  if (!location) return null;
  return withoutUndefined({
    latitude: location.latitude,
    longitude: location.longitude,
    horizontalAccuracyMeters: location.horizontalAccuracyMeters,
    altitudeMeters: location.altitudeMeters,
    speedMetersPerSecond: location.speedMetersPerSecond,
    courseDegrees: location.courseDegrees,
    capturedAt: Timestamp.fromDate(locationDate(location.capturedAt) || new Date()),
  });
}

function locationDate(value) {
  return timestampToDate(value) || (value instanceof Date ? value : null);
}
