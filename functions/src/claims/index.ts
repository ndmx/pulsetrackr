import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { getAuth } from 'firebase-admin/auth';
import { db, FieldValue, Timestamp } from '../shared/admin';
import { callableOptions } from '../shared/config';
import { cleanString, requireAuth, retentionDate, timestampToDate, withoutUndefined } from '../shared/util';
import { logAudit } from '../shared/audit';
import { privilegedRoleFromClaims } from '../sosShared';

const ALLOWED_ROLES = new Set(['sosAdmin', 'careTeam', 'lawEnforcement']);
const MAX_CLAIM_TTL_MS = 90 * 24 * 60 * 60 * 1000;

export const mint_sos_role_claim = onCall(callableOptions, async (request) => {
  const actorUid = requireAuth(request);
  requireClaimAdmin(request.auth?.token || {});
  const now = new Date();
  const payload = sanitizeClaimPayload(request.data || {}, now);
  return setSosRoleClaim({ actorUid, now, payload, enabled: true });
});

export const revoke_sos_role_claim = onCall(callableOptions, async (request) => {
  const actorUid = requireAuth(request);
  requireClaimAdmin(request.auth?.token || {});
  const now = new Date();
  const payload = sanitizeClaimPayload(request.data || {}, now, { allowMissingExpiry: true });
  return setSosRoleClaim({ actorUid, now, payload, enabled: false });
});

async function setSosRoleClaim({ actorUid, now, payload, enabled }: any) {
  const auth = getAuth();
  const user = await auth.getUser(payload.targetUid);
  const claims: any = { ...(user.customClaims || {}) };
  const expiries: any = { ...(claims.sosRoleExpiries || {}) };

  claims[payload.role] = enabled;
  if (enabled) {
    expiries[payload.role] = payload.expiresAt.toISOString();
  } else {
    delete expiries[payload.role];
  }
  claims.sosRoleExpiries = expiries;

  await auth.setCustomUserClaims(payload.targetUid, claims);
  const ledgerRef = db.collection('sos_role_claim_grants_private').doc();
  await ledgerRef.set(withoutUndefined({
    actorUid,
    targetUid: payload.targetUid,
    role: payload.role,
    enabled,
    reason: payload.reason,
    reference: payload.reference,
    expiresAt: enabled ? Timestamp.fromDate(payload.expiresAt) : undefined,
    createdAt: FieldValue.serverTimestamp(),
    deleteAfter: Timestamp.fromDate(retentionDate(now)),
  }));
  const audit = await logAudit({
    eventType: enabled ? 'sos_role_claim_minted' : 'sos_role_claim_revoked',
    actorUid,
    role: 'sosAdmin',
    sessionId: null,
    decision: 'allowed',
    reason: payload.reason,
    redacted: {
      targetUid: payload.targetUid,
      role: payload.role,
      reference: payload.reference,
      expiresAt: enabled ? payload.expiresAt.toISOString() : null,
      ledgerId: ledgerRef.id,
    },
    deleteAfter: retentionDate(now),
  });
  await ledgerRef.set({
    auditRecordId: audit.recordId,
    auditRecordHash: audit.eventHash,
    auditChainId: audit.chainId,
    auditSequence: audit.sequence,
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });

  return {
    target_uid: payload.targetUid,
    role: payload.role,
    enabled,
    expires_at: enabled ? payload.expiresAt.toISOString() : null,
    audit_record_id: audit.recordId,
  };
}

function requireClaimAdmin(claims: any) {
  if (privilegedRoleFromClaims(claims) !== 'sosAdmin') {
    throw new HttpsError('permission-denied', 'Minting SOS role claims requires a PulseTrackr admin claim');
  }
}

function sanitizeClaimPayload(data: any, now: Date, options: { allowMissingExpiry?: boolean } = {}) {
  const targetUid = cleanString(data.target_uid, 160);
  const role = cleanString(data.role, 40);
  const reason = cleanString(data.reason, 240);
  const reference = cleanString(data.reference, 160);
  const expiresAt = timestampToDate(data.expires_at) || new Date(now.getTime() + 24 * 60 * 60 * 1000);

  if (!targetUid || !role || !ALLOWED_ROLES.has(role)) {
    throw new HttpsError('invalid-argument', 'target_uid and a supported role are required');
  }
  if (!reason) {
    throw new HttpsError('invalid-argument', 'reason is required');
  }
  if (!options.allowMissingExpiry) {
    if (!expiresAt || expiresAt.getTime() <= now.getTime()) {
      throw new HttpsError('invalid-argument', 'expires_at must be in the future');
    }
    if (expiresAt.getTime() - now.getTime() > MAX_CLAIM_TTL_MS) {
      throw new HttpsError('invalid-argument', 'SOS role claims can be minted for at most 90 days');
    }
  }

  return { targetUid, role, reason, reference, expiresAt };
}
