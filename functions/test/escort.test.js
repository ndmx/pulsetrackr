'use strict';

process.env.NODE_ENV = 'test';
process.env.PULSETRACKR_LOCAL_ENVELOPE_KEK = Buffer.alloc(32, 7).toString('base64');

const assert = require('node:assert/strict');
const test = require('node:test');
const { __test } = require('../lib/index');
const {
  sanitizeActivationPayload,
  sanitizeLocationUpdatePayload,
  sanitizeResolutionPayload,
} = require('../lib/sosShared');

const { SOSRepository } = __test;

test('escort activation writes one app alert and never starts SOS fan-out', async () => {
  const { db, repo, enqueueCalls, pushCalls } = harness();
  seedRelationship(db, 'rel-1');
  db.seed('user_push_devices_private/device-1', {
    owner_uid: 'trusted-1',
    fcm_token: 'fcm-token-1',
  });

  const now = new Date('2026-07-10T12:00:00.000Z');
  const payload = sanitizeActivationPayload(activationInput({
    session_kind: 'escort',
    escort_relationship_id: 'rel-1',
  }), now);

  const result = await repo.activate({ uid: 'owner-1', now, payload });
  const session = db.collectionDocs('sos_sessions_private')[0];
  const alerts = db.collectionDocs('sos_app_alerts_private');

  assert.equal(payload.sessionKind, 'escort');
  assert.equal(payload.trustedContacts.length, 0);
  assert.equal(session.kind, 'escort');
  assert.equal(session.escortRelationshipId, 'rel-1');
  assert.equal(session.notificationSagaStatus, 'not_applicable');
  assert.deepEqual(session.appTrustedContactsNotified, ['rel-1']);
  assert.equal(alerts.length, 1);
  assert.equal(alerts[0].kind, 'escort');
  assert.equal(alerts[0].relationshipId, 'rel-1');
  assert.equal(alerts[0].recipientUid, 'trusted-1');
  assert.equal(db.collectionDocs('sos_notification_attempts_private').length, 0);
  assert.equal(db.collectionDocs('sos_notification_tasks_private').length, 0);
  assert.equal(enqueueCalls.length, 0);
  assert.equal(pushCalls.length, 1);
  assert.equal(pushCalls[0].data.session_id, result.session_id);
  assert.equal(pushCalls[0].data.kind, 'escort');
  assert.equal(result.app_trusted_contacts_notified.length, 1);
});

test('escort activation ignores smuggled trusted contacts before repository processing', async () => {
  const { db, repo, enqueueCalls } = harness();
  seedRelationship(db, 'rel-1');

  const now = new Date('2026-07-10T12:00:00.000Z');
  const payload = sanitizeActivationPayload(activationInput({
    client_session_id: 'escort-smuggled',
    sessionKind: 'escort',
    escortRelationshipId: 'rel-1',
    trusted_contacts_to_notify: [{
      contact_id: 'twilio-contact',
      display_name: 'SMS Contact',
      phone_number: '+15551234567',
      channels: ['sms', 'phone_call', 'email'],
      email_address: 'contact@example.com',
    }],
  }), now);

  await repo.activate({ uid: 'owner-1', now, payload });
  const session = db.collectionDocs('sos_sessions_private')[0];

  assert.deepEqual(payload.trustedContacts, []);
  assert.deepEqual(session.trustedContacts, []);
  assert.deepEqual(session.trustedContactsAccepted, []);
  assert.equal(db.collectionDocs('sos_notification_attempts_private').length, 0);
  assert.equal(enqueueCalls.length, 0);
});

test('escort activation rejects missing, revoked, and foreign relationships', async () => {
  assert.throws(() => sanitizeActivationPayload(activationInput({
    session_kind: 'escort',
    escort_relationship_id: '',
  })), /escort_relationship_id is required/);

  {
    const { repo } = harness();
    const payload = sanitizeActivationPayload(activationInput({
      session_kind: 'escort',
      escort_relationship_id: 'missing-rel',
    }));
    await assert.rejects(
      () => repo.activate({ uid: 'owner-1', now: new Date('2026-07-10T12:00:00.000Z'), payload }),
      (error) => error.code === 'not-found',
    );
  }

  {
    const { db, repo } = harness();
    seedRelationship(db, 'rel-revoked', { status: 'revoked' });
    const payload = sanitizeActivationPayload(activationInput({
      session_kind: 'escort',
      escort_relationship_id: 'rel-revoked',
    }));
    await assert.rejects(
      () => repo.activate({ uid: 'owner-1', now: new Date('2026-07-10T12:00:00.000Z'), payload }),
      (error) => error.code === 'failed-precondition',
    );
  }

  {
    const { db, repo } = harness();
    seedRelationship(db, 'rel-foreign', { ownerUid: 'other-owner' });
    const payload = sanitizeActivationPayload(activationInput({
      session_kind: 'escort',
      escort_relationship_id: 'rel-foreign',
    }));
    await assert.rejects(
      () => repo.activate({ uid: 'owner-1', now: new Date('2026-07-10T12:00:00.000Z'), payload }),
      (error) => error.code === 'permission-denied',
    );
  }
});

test('escort and SOS activation rate limits use isolated documents', async () => {
  const { db, repo, enqueueCalls } = harness();
  seedRelationship(db, 'rel-1');
  const now = new Date('2026-07-10T12:00:00.000Z');

  await repo.activate({
    uid: 'owner-1',
    now,
    payload: sanitizeActivationPayload(activationInput({
      client_session_id: 'escort-rate',
      session_kind: 'escort',
      escort_relationship_id: 'rel-1',
    }), now),
  });
  await repo.activate({
    uid: 'owner-1',
    now: new Date(now.getTime() + 10_000),
    payload: sanitizeActivationPayload(activationInput({
      client_session_id: 'sos-rate',
    }), now),
  });

  assert.equal(db.has('sos_rate_limits_private/owner-1_escort'), true);
  assert.equal(db.has('sos_rate_limits_private/owner-1'), true);
  assert.equal(enqueueCalls.length, 1);
});

test('legacy activation defaults to SOS and invokes the existing fan-out path', async () => {
  const { db, repo, enqueueCalls } = harness();
  const now = new Date('2026-07-10T12:00:00.000Z');
  const payload = sanitizeActivationPayload(activationInput({
    client_session_id: 'legacy-sos',
    trusted_contacts_to_notify: [{
      contact_id: 'contact-1',
      display_name: 'Ada',
      phone_number: '+15551234567',
      channels: ['sms'],
    }],
  }), now);

  await repo.activate({ uid: 'owner-1', now, payload });
  const session = db.collectionDocs('sos_sessions_private')[0];

  assert.equal(payload.sessionKind, 'sos');
  assert.equal(session.kind, 'sos');
  assert.equal(session.notificationSagaStatus, 'enqueued');
  assert.equal(enqueueCalls.length, 1);
  assert.equal(enqueueCalls[0].contacts.length, 1);
});

test('escort resolve accepts arrived_safely and touches only the escort alert', async () => {
  const { db, repo } = harness();
  seedRelationship(db, 'rel-1');
  seedRelationship(db, 'rel-other', { trustedContactUid: 'trusted-2' });
  const now = new Date('2026-07-10T12:00:00.000Z');
  const activation = await repo.activate({
    uid: 'owner-1',
    now,
    payload: sanitizeActivationPayload(activationInput({
      client_session_id: 'escort-resolve',
      session_kind: 'escort',
      escort_relationship_id: 'rel-1',
    }), now),
  });

  await repo.resolve({
    uid: 'owner-1',
    now: new Date(now.getTime() + 60_000),
    payload: sanitizeResolutionPayload({
      session_id: activation.session_id,
      resolution_reason: 'arrived_safely',
      resolved_at: '2026-07-10T12:01:00.000Z',
      final_location: locationInput('2026-07-10T12:01:00.000Z'),
    }),
  });

  const session = db.get(`sos_sessions_private/${activation.session_id}`);
  const alerts = db.collectionDocs('sos_app_alerts_private');
  assert.equal(session.status, 'resolved');
  assert.equal(session.resolutionReason, 'arrived_safely');
  assert.equal(alerts.length, 1);
  assert.equal(alerts[0].relationshipId, 'rel-1');
  assert.equal(alerts[0].status, 'resolved');
  assert.equal(alerts[0].kind, 'escort');
});

test('escort append updates only the escort relationship alert', async () => {
  const { db, repo } = harness();
  seedRelationship(db, 'rel-1');
  seedRelationship(db, 'rel-other', { trustedContactUid: 'trusted-2' });
  const now = new Date('2026-07-10T12:00:00.000Z');
  const activation = await repo.activate({
    uid: 'owner-1',
    now,
    payload: sanitizeActivationPayload(activationInput({
      client_session_id: 'escort-append',
      session_kind: 'escort',
      escort_relationship_id: 'rel-1',
    }), now),
  });

  await repo.appendLocation({
    uid: 'owner-1',
    now: new Date(now.getTime() + 30_000),
    payload: sanitizeLocationUpdatePayload({
      session_id: activation.session_id,
      sequence_number: 1,
      location: locationInput('2026-07-10T12:00:30.000Z', { latitude: 40.713 }),
      captured_at: '2026-07-10T12:00:30.000Z',
    }),
  });

  const alerts = db.collectionDocs('sos_app_alerts_private');
  assert.equal(alerts.length, 1);
  assert.equal(alerts[0].relationshipId, 'rel-1');
  assert.equal(alerts[0].lastKnownLocation.latitude, 40.713);
});

test('escort expiry is four hours from activation', async () => {
  const { db, repo } = harness();
  seedRelationship(db, 'rel-1');
  const now = new Date('2026-07-10T12:00:00.000Z');

  await repo.activate({
    uid: 'owner-1',
    now,
    payload: sanitizeActivationPayload(activationInput({
      client_session_id: 'escort-expiry',
      session_kind: 'escort',
      escort_relationship_id: 'rel-1',
      privacy: { admin_access_expires_after_seconds: 60 },
    }), now),
  });

  const session = db.collectionDocs('sos_sessions_private')[0];
  assert.equal(
    session.expiresAt.toDate().toISOString(),
    new Date(now.getTime() + 4 * 60 * 60 * 1000).toISOString(),
  );
});

function harness() {
  const db = new FakeFirestore();
  const enqueueCalls = [];
  const pushCalls = [];
  const warnings = [];
  const repo = new SOSRepository({
    db,
    enqueueSosNotificationTask: async (payload) => {
      enqueueCalls.push(payload);
      return {
        enqueued: true,
        notificationSummary: {
          queued: payload.contacts.length,
          sent: 0,
          failed: 0,
          skipped: 0,
          optedOut: 0,
        },
      };
    },
    sendFcmPush: async (payload) => {
      pushCalls.push(payload);
      return {
        status: 'sent',
        provider: 'fcm',
        providerMessageId: 'message-1',
        errorMessage: null,
      };
    },
    logger: {
      warn(message, data) {
        warnings.push({ message, data });
      },
    },
  });
  return { db, repo, enqueueCalls, pushCalls, warnings };
}

function activationInput(overrides = {}) {
  return {
    client_session_id: 'client-1',
    activated_at: '2026-07-10T12:00:00.000Z',
    source: 'ios',
    last_known_location: locationInput('2026-07-10T12:00:00.000Z'),
    recent_trail: [],
    trusted_contacts_to_notify: [],
    privacy: {},
    ...overrides,
  };
}

function locationInput(capturedAt, overrides = {}) {
  return {
    latitude: 40.7128,
    longitude: -74.006,
    captured_at: capturedAt,
    horizontal_accuracy_meters: 12,
    ...overrides,
  };
}

function seedRelationship(db, id, overrides = {}) {
  db.seed(`sos_app_trusted_contacts_private/${id}`, {
    ownerUid: 'owner-1',
    trustedContactUid: 'trusted-1',
    ownerDisplayName: 'Owner One',
    trustedContactDisplayName: 'Trusted One',
    status: 'accepted',
    ...overrides,
  });
}

class FakeFirestore {
  constructor() {
    this.docs = new Map();
    this.nextId = 1;
  }

  collection(path) {
    return new FakeCollectionRef(this, path);
  }

  batch() {
    return new FakeBatch(this);
  }

  async runTransaction(callback) {
    return callback(new FakeTransaction(this));
  }

  seed(path, data) {
    this.docs.set(path, cloneData(data));
  }

  get(path) {
    const data = this.docs.get(path);
    assert.ok(data, `Expected ${path} to exist`);
    return cloneData(data);
  }

  has(path) {
    return this.docs.has(path);
  }

  collectionDocs(collectionPath) {
    const prefix = `${collectionPath}/`;
    return Array.from(this.docs.entries())
      .filter(([path]) => path.startsWith(prefix) && !path.slice(prefix.length).includes('/'))
      .map(([, data]) => cloneData(data));
  }

  queryDocs(query) {
    let entries = Array.from(this.docs.entries())
      .filter(([path]) => path.startsWith(`${query.collectionPath}/`) && !path.slice(query.collectionPath.length + 1).includes('/'));
    for (const filter of query.filters) {
      entries = entries.filter(([, data]) => matchesFilter(data[filter.field], filter.op, filter.value));
    }
    if (query.limitCount != null) {
      entries = entries.slice(0, query.limitCount);
    }
    return entries.map(([path, data]) => new FakeQueryDocSnapshot(path.split('/').at(-1), data));
  }
}

class FakeCollectionRef {
  constructor(db, path) {
    this.db = db;
    this.path = path;
  }

  doc(id) {
    return new FakeDocRef(this.db, this.path, id || `auto-${this.db.nextId++}`);
  }

  where(field, op, value) {
    return new FakeQuery(this.db, this.path).where(field, op, value);
  }

  limit(count) {
    return new FakeQuery(this.db, this.path).limit(count);
  }
}

class FakeDocRef {
  constructor(db, collectionPath, id) {
    this.db = db;
    this.collectionPath = collectionPath;
    this.id = id;
    this.path = `${collectionPath}/${id}`;
  }

  async get() {
    return new FakeDocSnapshot(this.id, this.db.docs.get(this.path));
  }

  async set(data, options = {}) {
    writeDoc(this.db, this, data, options);
  }

  async update(data) {
    const current = this.db.docs.get(this.path);
    assert.ok(current, `Expected ${this.path} to exist before update`);
    this.db.docs.set(this.path, applyWrite(current, data));
  }
}

class FakeQuery {
  constructor(db, collectionPath, filters = [], limitCount = undefined) {
    this.db = db;
    this.collectionPath = collectionPath;
    this.filters = filters;
    this.limitCount = limitCount;
  }

  where(field, op, value) {
    return new FakeQuery(this.db, this.collectionPath, [...this.filters, { field, op, value }], this.limitCount);
  }

  limit(count) {
    return new FakeQuery(this.db, this.collectionPath, this.filters, count);
  }

  async get() {
    const docs = this.db.queryDocs(this);
    return { empty: docs.length === 0, docs };
  }
}

class FakeTransaction {
  constructor(db) {
    this.db = db;
    this.hasWritten = false;
  }

  async get(refOrQuery) {
    assert.equal(this.hasWritten, false, 'Firestore transaction read happened after a write');
    if (refOrQuery instanceof FakeDocRef) {
      return new FakeDocSnapshot(refOrQuery.id, this.db.docs.get(refOrQuery.path));
    }
    const docs = this.db.queryDocs(refOrQuery);
    return { docs, empty: docs.length === 0 };
  }

  set(ref, data, options = {}) {
    this.hasWritten = true;
    writeDoc(this.db, ref, data, options);
  }

  update(ref, data) {
    this.hasWritten = true;
    const current = this.db.docs.get(ref.path);
    assert.ok(current, `Expected ${ref.path} to exist before update`);
    this.db.docs.set(ref.path, applyWrite(current, data));
  }
}

class FakeBatch {
  constructor(db) {
    this.db = db;
    this.writes = [];
  }

  set(ref, data, options = {}) {
    this.writes.push({ ref, data, options });
  }

  async commit() {
    for (const write of this.writes) {
      writeDoc(this.db, write.ref, write.data, write.options);
    }
  }
}

class FakeDocSnapshot {
  constructor(id, data) {
    this.id = id;
    this.exists = data !== undefined;
    this.value = data;
  }

  data() {
    return cloneData(this.value);
  }
}

class FakeQueryDocSnapshot extends FakeDocSnapshot {}

function writeDoc(db, ref, data, options = {}) {
  const current = options.merge ? db.docs.get(ref.path) || {} : {};
  db.docs.set(ref.path, applyWrite(current, data));
}

function applyWrite(current, data) {
  const next = cloneData(current);
  for (const [key, value] of Object.entries(data)) {
    if (isDelete(value)) {
      delete next[key];
    } else if (isIncrement(value)) {
      next[key] = (Number(next[key]) || 0) + value.operand;
    } else {
      next[key] = cloneData(value);
    }
  }
  return next;
}

function matchesFilter(actual, op, expected) {
  if (op === '==') {
    return actual === expected;
  }
  throw new Error(`Unsupported fake query op ${op}`);
}

function cloneData(value) {
  if (value === null || typeof value !== 'object') {
    return value;
  }
  if (
    typeof value.toDate === 'function'
    || isIncrement(value)
    || isDelete(value)
    || value.constructor.name === 'ServerTimestampTransform'
  ) {
    return value;
  }
  if (Array.isArray(value)) {
    return value.map(cloneData);
  }
  return Object.fromEntries(
    Object.entries(value)
      .filter(([, entryValue]) => entryValue !== undefined)
      .map(([key, entryValue]) => [key, cloneData(entryValue)]),
  );
}

function isIncrement(value) {
  return value && value.constructor && value.constructor.name === 'NumericIncrementTransform';
}

function isDelete(value) {
  return value && value.constructor && value.constructor.name === 'DeleteTransform';
}
