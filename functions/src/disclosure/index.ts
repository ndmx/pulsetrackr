import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { db, FieldValue, Timestamp } from '../shared/admin';
import { callableOptions } from '../shared/config';
import { requireAuth, translateErrors, withoutUndefined, retentionDate, timestampToDate, timestampToIso, plainLocation } from '../shared/util';
import { logAudit } from '../shared/audit';
import { decryptPrivateJson } from '../shared/envelope';
import { privilegedRoleFromClaims, sanitizeLawEnforcementRequestPayload, sanitizeLawEnforcementReviewPayload } from '../sosShared';

let disclosureRepository: DisclosureRepository;

export const record_law_enforcement_request = onCall(callableOptions, async (request) => {
  const uid = requireAuth(request);
  const role = privilegedRoleFromClaims(request.auth?.token || {});
  requireLegalOpsRole(role);

  const now = new Date();
  const payload = translateErrors(() => sanitizeLawEnforcementRequestPayload(request.data || {}, now));
  return disclosureRepository.recordLawEnforcementRequest({ uid, role, now, payload });
});

export const review_law_enforcement_request = onCall(callableOptions, async (request) => {
  const uid = requireAuth(request);
  const role = privilegedRoleFromClaims(request.auth?.token || {});
  requireLegalApprovalRole(role);

  const now = new Date();
  const payload = translateErrors(() => sanitizeLawEnforcementReviewPayload(request.data || {}, now));
  return disclosureRepository.reviewLawEnforcementRequest({ uid, role, now, payload });
});

export const request_sos_session_access = onCall(callableOptions, async (request) => {
  const uid = requireAuth(request);
  const role = privilegedRoleFromClaims(request.auth?.token || {});
  const sessionId = typeof request.data?.session_id === 'string' ? request.data.session_id : '';
  const reason = typeof request.data?.reason === 'string' ? request.data.reason.slice(0, 240) : '';
  const legalRequestId = typeof request.data?.legal_request_id === 'string' ? request.data.legal_request_id.trim() : '';
  const now = new Date();

  return disclosureRepository.requestSosSessionAccess({
    uid,
    role,
    sessionId,
    reason,
    legalRequestId,
    now,
  });
});

class DisclosureRepository {
  async recordLawEnforcementRequest({ uid, role, now, payload }: any) {
  const sessionSnap = await db.collection('sos_sessions_private').doc(payload.sessionId).get();
  const session = sessionSnap.exists ? sessionSnap.data() : null;
  const sessionExpiresAt = timestampToDate(session?.expiresAt);
  const sessionActive = Boolean(
    session
      && session.status === 'active'
      && sessionExpiresAt
      && sessionExpiresAt.getTime() > now.getTime(),
  );
  const deleteAfter = timestampToDate(session?.deleteAfter) || retentionDate(now);
  const legalRequestRef = db.collection('sos_law_enforcement_requests_private').doc();

  await legalRequestRef.set(withoutUndefined({
    status: 'pending',
    sessionId: payload.sessionId,
    agencyName: payload.agencyName,
    requesterName: payload.requesterName,
    requesterTitle: payload.requesterTitle,
    requesterEmail: payload.requesterEmail,
    requesterPhone: payload.requesterPhone,
    legalProcessType: payload.legalProcessType,
    legalReference: payload.legalReference,
    documentReference: payload.documentReference,
    requestedScope: payload.requestedScope,
    urgency: payload.urgency,
    notes: payload.notes,
    receivedAt: Timestamp.fromDate(payload.receivedAt),
    sessionStatusAtIntake: session?.status || 'not_found',
    sessionActiveAtIntake: sessionActive,
    recordedByUid: uid,
    recordedByRole: role,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
    deleteAfter: Timestamp.fromDate(deleteAfter),
  }));

  await logAudit({
    eventType: 'law_enforcement_request_recorded',
    actorUid: uid,
    role,
    sessionId: payload.sessionId,
    decision: 'recorded',
    reason: payload.legalReference,
    redacted: {
      legalRequestId: legalRequestRef.id,
      agencyName: payload.agencyName,
      legalProcessType: payload.legalProcessType,
      requestedScope: payload.requestedScope,
      sessionStatus: session?.status || 'not_found',
      sessionActive,
    },
    deleteAfter,
  });

  return {
    legal_request_id: legalRequestRef.id,
    status: 'pending',
    session_id: payload.sessionId,
    session_active: sessionActive,
  };
  }

  async reviewLawEnforcementRequest({ uid, role, now, payload }: any) {
  const legalRequestRef = db.collection('sos_law_enforcement_requests_private').doc(payload.legalRequestId);
  const legalRequestSnap = await legalRequestRef.get();
  if (!legalRequestSnap.exists) {
    throw new HttpsError('not-found', 'Law enforcement request not found');
  }

  const legalRequest = legalRequestSnap.data() as any;
  const sessionSnap = await db.collection('sos_sessions_private').doc(legalRequest.sessionId).get();
  const session = sessionSnap.exists ? sessionSnap.data() : null;
  const sessionExpiresAt = timestampToDate(session?.expiresAt);
  const sessionActive = Boolean(
    session
      && session.status === 'active'
      && sessionExpiresAt
      && sessionExpiresAt.getTime() > now.getTime(),
  );
  const deleteAfter = timestampToDate(legalRequest.deleteAfter) || timestampToDate(session?.deleteAfter) || retentionDate(now);

  if (payload.decision === 'approved' && !sessionActive) {
    await logAudit({
      eventType: 'law_enforcement_request_reviewed',
      actorUid: uid,
      role,
      sessionId: legalRequest.sessionId,
      decision: 'denied',
      reason: `${payload.reviewNote}:inactive_or_expired_session`,
      redacted: { legalRequestId: payload.legalRequestId, requestedDecision: 'approved' },
      deleteAfter,
    });
    throw new HttpsError('failed-precondition', 'Law enforcement access can only be approved for active, unexpired SOS sessions');
  }

  if (payload.decision === 'denied') {
    await legalRequestRef.set(withoutUndefined({
      status: 'denied',
      reviewNote: payload.reviewNote,
      reviewedByUid: uid,
      reviewedByRole: role,
      reviewedAt: Timestamp.fromDate(payload.reviewedAt),
      updatedAt: FieldValue.serverTimestamp(),
    }), { merge: true });

    await logAudit({
      eventType: 'law_enforcement_request_reviewed',
      actorUid: uid,
      role,
      sessionId: legalRequest.sessionId,
      decision: 'denied',
      reason: payload.reviewNote,
      redacted: { legalRequestId: payload.legalRequestId },
      deleteAfter,
    });

    return {
      legal_request_id: payload.legalRequestId,
      status: 'denied',
    };
  }

  const maxApprovalExpiresAt = new Date(now.getTime() + 60 * 60 * 1000);
  const requestedExpiresAt = payload.expiresAt || new Date(now.getTime() + 30 * 60 * 1000);
  const approvalExpiresAt = new Date(Math.min(
    sessionExpiresAt!.getTime(),
    requestedExpiresAt.getTime(),
    maxApprovalExpiresAt.getTime(),
  ));
  const approvedScope = payload.approvedScope.length
    ? payload.approvedScope
    : (legalRequest.requestedScope || ['last_known_location', 'direction_of_travel']);

  await legalRequestRef.set(withoutUndefined({
    status: 'approved',
    reviewNote: payload.reviewNote,
    approvedScope,
    approvalExpiresAt: Timestamp.fromDate(approvalExpiresAt),
    reviewedByUid: uid,
    reviewedByRole: role,
    reviewedAt: Timestamp.fromDate(payload.reviewedAt),
    updatedAt: FieldValue.serverTimestamp(),
  }), { merge: true });

  await logAudit({
    eventType: 'law_enforcement_request_reviewed',
    actorUid: uid,
    role,
    sessionId: legalRequest.sessionId,
    decision: 'approved',
    reason: payload.reviewNote,
    redacted: {
      legalRequestId: payload.legalRequestId,
      approvedScope,
      approvalExpiresAt: approvalExpiresAt.toISOString(),
    },
    deleteAfter,
  });

  return {
    legal_request_id: payload.legalRequestId,
    status: 'approved',
    approved_scope: approvedScope,
    approval_expires_at: approvalExpiresAt.toISOString(),
  };
  }

  async requestSosSessionAccess({ uid, role, sessionId, reason, legalRequestId, now }: any) {
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

  const session = sessionSnap.data() as any;
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

  let legalRequest: any = null;
  if (role === 'lawEnforcement') {
    if (!legalRequestId) {
      await logAudit({
        eventType: 'privileged_access_requested',
        actorUid: uid,
        role,
        sessionId,
        decision: 'denied',
        reason: `${reason}:missing_legal_request_id`,
        redacted: {},
        deleteAfter: timestampToDate(session.deleteAfter) || retentionDate(now),
      });
      throw new HttpsError('failed-precondition', 'Law enforcement access requires an approved legal request id');
    }

    legalRequest = await approvedLawEnforcementRequest({ legalRequestId, sessionId, now });
    if (!legalRequest.allowed) {
      await logAudit({
        eventType: 'privileged_access_requested',
        actorUid: uid,
        role,
        sessionId,
        decision: 'denied',
        reason: `${reason}:${legalRequest.reason}`,
        redacted: { legalRequestId },
        deleteAfter: timestampToDate(session.deleteAfter) || retentionDate(now),
      });
      throw new HttpsError('failed-precondition', legalRequest.message);
    }
  }

  const grantExpiresAt = new Date(Math.min(
    expiresAt!.getTime(),
    now.getTime() + 15 * 60 * 1000,
  ));
  const responseScope = legalRequest?.approvedScope || [
    'last_known_location',
    'direction_of_travel',
    'redacted_trusted_contacts',
  ];
  const grantRef = db.collection('sos_access_grants_private').doc();
  await grantRef.set({
    actorUid: uid,
    role,
    sessionId,
    legalRequestId: legalRequest?.id || null,
    approvedScope: responseScope,
    reason,
    status: 'pending_key_release',
    expiresAt: Timestamp.fromDate(grantExpiresAt),
    createdAt: FieldValue.serverTimestamp(),
    deleteAfter: session.deleteAfter || Timestamp.fromDate(retentionDate(now)),
  });
  const auditRecord = await logAudit({
    eventType: 'privileged_access_requested',
    actorUid: uid,
    role,
    sessionId,
    decision: 'allowed',
    reason,
    redacted: {
      legalRequestId: legalRequest?.id || null,
      approvedScope: responseScope,
      grantExpiresAt: grantExpiresAt.toISOString(),
    },
    deleteAfter: timestampToDate(session.deleteAfter) || retentionDate(now),
  });
  await db.collection('sos_disclosure_key_releases_private').add({
    actorUid: uid,
    role,
    sessionId,
    grantId: grantRef.id,
    legalRequestId: legalRequest?.id || null,
    approvedScope: responseScope,
    auditRecordId: auditRecord.recordId,
    auditRecordHash: auditRecord.eventHash,
    auditChainId: auditRecord.chainId,
    auditSequence: auditRecord.sequence,
    releaseNonce: `${Date.now()}_${Math.random().toString(36).slice(2)}`,
    status: 'released',
    expiresAt: Timestamp.fromDate(grantExpiresAt),
    createdAt: FieldValue.serverTimestamp(),
    deleteAfter: session.deleteAfter || Timestamp.fromDate(retentionDate(now)),
  });
  await grantRef.set({
    status: 'released',
    auditRecordId: auditRecord.recordId,
    auditRecordHash: auditRecord.eventHash,
    auditChainId: auditRecord.chainId,
    auditSequence: auditRecord.sequence,
    releasedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });

  const lastKnownLocation = responseScope.includes('last_known_location')
    ? decryptSessionLocation(session, sessionId, 'lastKnownLocation')
    : null;
  const recentTrail = responseScope.includes('recent_trail')
    ? decryptSessionTrail(session, sessionId)
    : [];

  return withoutUndefined({
    session_id: sessionId,
    status: session.status,
    activated_at: timestampToIso(session.activatedAt),
    expires_at: timestampToIso(session.expiresAt),
    legal_request_id: legalRequest?.id || undefined,
    approved_scope: legalRequest ? responseScope : undefined,
    last_known_location: responseScope.includes('last_known_location') ? plainLocation(lastKnownLocation) : undefined,
    direction_of_travel: responseScope.includes('direction_of_travel') ? (session.directionOfTravel || null) : undefined,
    trusted_contacts: responseScope.includes('redacted_trusted_contacts') ? (session.trustedContactsRedacted || []) : undefined,
    recent_trail: responseScope.includes('recent_trail') ? recentTrail.map(plainLocation) : undefined,
    grant_expires_at: grantExpiresAt.toISOString(),
  });
  }
}

disclosureRepository = new DisclosureRepository();

function requireLegalOpsRole(role: string | null) {
  if (role !== 'sosAdmin' && role !== 'careTeam') {
    throw new HttpsError('permission-denied', 'Recording law enforcement requests requires a PulseTrackr legal/admin role');
  }
}

function requireLegalApprovalRole(role: string | null) {
  if (role !== 'sosAdmin') {
    throw new HttpsError('permission-denied', 'Approving law enforcement requests requires a PulseTrackr admin role');
  }
}

function decryptSessionLocation(session: any, sessionId: string, field: string) {
  const encryptedField = `${field}Encrypted`;
  if (session[encryptedField]) {
    return decryptPrivateJson(
      session[encryptedField],
      encryptedLocationAad(sessionId, session.ownerUid, field),
    );
  }
  return session[field] || null;
}

function decryptSessionTrail(session: any, sessionId: string) {
  if (session.recentTrailEncrypted) {
    return decryptPrivateJson(
      session.recentTrailEncrypted,
      encryptedLocationAad(sessionId, session.ownerUid, 'recentTrail'),
    ) || [];
  }
  return session.recentTrail || [];
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

async function approvedLawEnforcementRequest({ legalRequestId, sessionId, now }: any) {
  const snapshot = await db.collection('sos_law_enforcement_requests_private').doc(legalRequestId).get();
  if (!snapshot.exists) {
    return {
      allowed: false,
      reason: 'legal_request_not_found',
      message: 'Approved legal request not found',
    };
  }

  const request = snapshot.data() as any;
  const approvalExpiresAt = timestampToDate(request.approvalExpiresAt);
  if (request.sessionId !== sessionId) {
    return {
      allowed: false,
      reason: 'legal_request_session_mismatch',
      message: 'Approved legal request does not match this SOS session',
    };
  }
  if (request.status !== 'approved' || !approvalExpiresAt || approvalExpiresAt.getTime() <= now.getTime()) {
    return {
      allowed: false,
      reason: 'legal_request_not_approved_or_expired',
      message: 'Law enforcement request is not approved or has expired',
    };
  }

  const approvedScope = Array.isArray(request.approvedScope)
    ? request.approvedScope
    : ['last_known_location', 'direction_of_travel'];
  if (!approvedScope.includes('last_known_location')) {
    return {
      allowed: false,
      reason: 'legal_request_location_not_approved',
      message: 'Law enforcement request does not approve location disclosure',
    };
  }

  return {
    allowed: true,
    id: snapshot.id,
    approvedScope,
    approvalExpiresAt,
  };
}
