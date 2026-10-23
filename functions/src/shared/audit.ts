// Append-only privileged-access audit log (sos_access_audit). Used by the SOS and
// disclosure domains to record every owner/responder/admin action.

import crypto from 'node:crypto';
import { db, FieldValue, Timestamp } from './admin';
import { withoutUndefined } from './util';

const AUDIT_CHAIN_ID = 'sos_access_v1';
const AUDIT_SCHEMA_VERSION = 1;
const GENESIS_HASH = '0'.repeat(64);

export function auditRef(database: any = db) {
  return database.collection('sos_access_audit').doc();
}

export function auditEvent({ eventType, actorUid, role, sessionId, decision, reason, redacted, deleteAfter, createdAtMillis, previousHash, sequence, eventHash }: any) {
  return withoutUndefined({
    eventType,
    actorUid,
    role,
    sessionId,
    decision,
    reason,
    redacted,
    chainId: previousHash ? AUDIT_CHAIN_ID : undefined,
    chainSchemaVersion: previousHash ? AUDIT_SCHEMA_VERSION : undefined,
    sequence,
    previousHash,
    eventHash,
    createdAtMillis,
    createdAt: FieldValue.serverTimestamp(),
    deleteAfter: Timestamp.fromDate(deleteAfter),
  });
}

export async function logAudit(event: any): Promise<any> {
  return db.runTransaction(async (transaction) => {
    const prepared = await prepareAuditAppend(transaction, event);
    writePreparedAudit(transaction, prepared);
    return {
      recordId: prepared.recordRef.id,
      eventHash: prepared.head.eventHash,
      sequence: prepared.head.sequence,
      chainId: AUDIT_CHAIN_ID,
    };
  });
}

export async function prepareAuditAppend(transaction: any, event: any, database: any = db): Promise<any> {
  const headRef = database.collection('sos_access_audit_chain_heads').doc(AUDIT_CHAIN_ID);
  const headSnap = await transaction.get(headRef);
  const head = headSnap.exists ? headSnap.data() : {};
  const previousHash = typeof head.eventHash === 'string' ? head.eventHash : GENESIS_HASH;
  const sequence = Number.isInteger(head.sequence) ? head.sequence + 1 : 1;
  const createdAtMillis = Number.isFinite(event.createdAtMillis) ? event.createdAtMillis : Date.now();
  const recordRef = auditRef(database);
  const hashPayload = {
    chainId: AUDIT_CHAIN_ID,
    schemaVersion: AUDIT_SCHEMA_VERSION,
    sequence,
    previousHash,
    recordId: recordRef.id,
    createdAtMillis,
    eventType: event.eventType,
    actorUid: event.actorUid,
    role: event.role,
    sessionId: event.sessionId || null,
    decision: event.decision,
    reason: event.reason || '',
    redacted: event.redacted || {},
  };
  const eventHash = sha256(canonicalJson(hashPayload));

  return {
    recordRef,
    headRef,
    head: {
      chainId: AUDIT_CHAIN_ID,
      eventHash,
      previousHash,
      sequence,
      recordId: recordRef.id,
      updatedAt: FieldValue.serverTimestamp(),
    },
    event: auditEvent({ ...event, createdAtMillis, previousHash, sequence, eventHash }),
  };
}

export function writePreparedAudit(transaction: any, prepared: any): void {
  transaction.set(prepared.recordRef, prepared.event);
  transaction.set(prepared.headRef, prepared.head, { merge: true });
}

export async function appendAuditToTransaction(transaction: any, event: any, database: any = db): Promise<void> {
  const prepared = await prepareAuditAppend(transaction, event, database);
  writePreparedAudit(transaction, prepared);
}

function sha256(value: string): string {
  return crypto.createHash('sha256').update(value).digest('hex');
}

function canonicalJson(value: any): string {
  if (value === null || typeof value !== 'object') {
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) {
    return `[${value.map(canonicalJson).join(',')}]`;
  }
  return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`).join(',')}}`;
}
