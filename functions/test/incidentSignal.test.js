'use strict';

process.env.NODE_ENV = 'test';

const assert = require('node:assert/strict');
const test = require('node:test');
const { Timestamp } = require('firebase-admin/firestore');
const { __test } = require('../lib/index');

const {
  counterTotalsFromShardDocs,
  deriveSignalOutcome,
  IncidentRepository,
  INCIDENT_CONCERN_REASONS,
  SIGNAL_COUNTER_FIELD,
} = __test;

test('seen leaves status and severity unchanged', () => {
  const outcome = deriveSignalOutcome('seen', {
    status: 'Active', severity: 'Medium', confirmations: 3, disputes: 0,
  });
  assert.deepEqual(outcome, { status: 'Active', severity: 'Medium' });
});

test('notSeen flips an active incident to watching once disputes reach confirmations', () => {
  const outcome = deriveSignalOutcome('notSeen', {
    status: 'Active', severity: 'Medium', confirmations: 2, disputes: 1,
  });
  assert.equal(outcome.status, 'Watching');
});

test('notSeen does not change status while confirmations still lead', () => {
  const outcome = deriveSignalOutcome('notSeen', {
    status: 'Active', severity: 'Medium', confirmations: 5, disputes: 1,
  });
  assert.equal(outcome.status, 'Active');
});

test('unsafe reactivates and raises severity but never downgrades urgent', () => {
  assert.deepEqual(
    deriveSignalOutcome('unsafe', { status: 'Watching', severity: 'Low' }),
    { status: 'Active', severity: 'High' },
  );
  assert.deepEqual(
    deriveSignalOutcome('unsafe', { status: 'Active', severity: 'Urgent' }),
    { status: 'Active', severity: 'Urgent' },
  );
});

test('roadBlocked only raises the severity floor to medium, never lowers it', () => {
  // Low severity -> Medium.
  assert.equal(deriveSignalOutcome('roadBlocked', { severity: 'Low' }).severity, 'Medium');
  // Higher severities are left untouched, including traffic (no downgrade).
  assert.equal(
    deriveSignalOutcome('roadBlocked', { severity: 'High', category: 'traffic' }).severity,
    'High',
  );
  assert.equal(
    deriveSignalOutcome('roadBlocked', { severity: 'Urgent', category: 'traffic' }).severity,
    'Urgent',
  );
  assert.equal(
    deriveSignalOutcome('roadBlocked', { severity: 'Medium', category: 'security' }).severity,
    'Medium',
  );
});

test('cleared resolves after the third clear, watching before that', () => {
  assert.equal(deriveSignalOutcome('cleared', { cleared_reports: 0 }).status, 'Watching');
  assert.equal(deriveSignalOutcome('cleared', { cleared_reports: 2 }).status, 'Resolved');
});

test('signal counter map covers every supported signal', () => {
  assert.deepEqual(Object.keys(SIGNAL_COUNTER_FIELD).sort(), [
    'cleared', 'notSeen', 'roadBlocked', 'seen', 'unsafe',
  ]);
});

test('incident concern reasons cover App Store moderation paths', () => {
  assert.deepEqual([...INCIDENT_CONCERN_REASONS].sort(), [
    'dangerous_advice',
    'false_report',
    'offensive_content',
    'private_information',
    'spam_or_abuse',
  ]);
});

test('counter rollup totals sum only supported shard fields', () => {
  const docs = [
    { data: () => ({ counterField: 'confirmations', count: 2 }) },
    { data: () => ({ counterField: 'confirmations', count: 3 }) },
    { data: () => ({ counterField: 'disputes', count: 1 }) },
    { data: () => ({ counterField: 'unknown_counter', count: 99 }) },
  ];

  assert.deepEqual(counterTotalsFromShardDocs(docs), {
    confirmations: 5,
    disputes: 1,
    unsafe_reports: 0,
    blocked_reports: 0,
    cleared_reports: 0,
    official_updates: 0,
  });
});

test('recordSignal applies first signal, increments a shard, and creates voter ledger', async () => {
  const db = new FakeFirestore();
  const repo = new IncidentRepository(db);
  const now = new Date('2026-07-10T12:00:00.000Z');
  const publicDeleteAfter = new Date('2026-07-10T15:00:00.000Z');
  seedIncident(db, 'incident-1', { deleteAfter: Timestamp.fromDate(publicDeleteAfter) });

  const result = await repo.recordSignal({
    uid: 'user-1',
    now,
    incidentId: 'incident-1',
    signal: 'seen',
  });

  assert.deepEqual(result, { status: 'Active', severity: 'Medium', applied: true });
  assert.equal(shardCount(db, 'incident-1', 'confirmations'), 1);
  const voter = db.get('safety_incident_signal_voters_private/incident-1_user-1');
  assert.equal(voter.incidentId, 'incident-1');
  assert.equal(voter.uid, 'user-1');
  assert.equal(voter.signal, 'seen');
  assert.equal(
    voter.deleteAfter.toDate().toISOString(),
    new Date(publicDeleteAfter.getTime() + 35 * 24 * 60 * 60 * 1000).toISOString(),
  );
});

test('recordSignal rejects a second signal from the same user without changing shards or voter ledger', async () => {
  const db = new FakeFirestore();
  const repo = new IncidentRepository(db);
  const now = new Date('2026-07-10T12:00:00.000Z');
  seedIncident(db, 'incident-1');

  await repo.recordSignal({ uid: 'user-1', now, incidentId: 'incident-1', signal: 'seen' });
  const voterBefore = db.get('safety_incident_signal_voters_private/incident-1_user-1');
  const shardCountBefore = shardCount(db, 'incident-1');

  const result = await repo.recordSignal({
    uid: 'user-1',
    now: new Date(now.getTime() + 1000),
    incidentId: 'incident-1',
    signal: 'unsafe',
  });

  assert.deepEqual(result, {
    status: 'Active',
    severity: 'Medium',
    applied: false,
    reason: 'already_signaled',
  });
  assert.equal(shardCount(db, 'incident-1'), shardCountBefore);
  assert.equal(db.get('safety_incident_signal_voters_private/incident-1_user-1').signal, voterBefore.signal);
  assert.equal(
    db.get('safety_incident_signal_voters_private/incident-1_user-1').deleteAfter.toDate().toISOString(),
    voterBefore.deleteAfter.toDate().toISOString(),
  );
});

test('recordSignal allows the same user to signal a different incident', async () => {
  const db = new FakeFirestore();
  const repo = new IncidentRepository(db);
  const now = new Date('2026-07-10T12:00:00.000Z');
  seedIncident(db, 'incident-1');
  seedIncident(db, 'incident-2');

  const first = await repo.recordSignal({ uid: 'user-1', now, incidentId: 'incident-1', signal: 'seen' });
  const second = await repo.recordSignal({
    uid: 'user-1',
    now: new Date(now.getTime() + 3000),
    incidentId: 'incident-2',
    signal: 'unsafe',
  });

  assert.equal(first.applied, true);
  assert.equal(second.applied, true);
  assert.equal(db.has('safety_incident_signal_voters_private/incident-1_user-1'), true);
  assert.equal(db.has('safety_incident_signal_voters_private/incident-2_user-1'), true);
});

test('recordSignal allows different users to signal the same incident', async () => {
  const db = new FakeFirestore();
  const repo = new IncidentRepository(db);
  const now = new Date('2026-07-10T12:00:00.000Z');
  seedIncident(db, 'incident-1');

  const first = await repo.recordSignal({ uid: 'user-1', now, incidentId: 'incident-1', signal: 'seen' });
  const second = await repo.recordSignal({ uid: 'user-2', now, incidentId: 'incident-1', signal: 'notSeen' });

  assert.equal(first.applied, true);
  assert.equal(second.applied, true);
  assert.equal(shardCount(db, 'incident-1'), 2);
  assert.equal(db.has('safety_incident_signal_voters_private/incident-1_user-1'), true);
  assert.equal(db.has('safety_incident_signal_voters_private/incident-1_user-2'), true);
});

test('recordSignal keeps rate-limit and resolved no-op paths unchanged', async () => {
  const db = new FakeFirestore();
  const repo = new IncidentRepository(db);
  const now = new Date('2026-07-10T12:00:00.000Z');
  seedIncident(db, 'incident-1');
  seedIncident(db, 'incident-2');
  seedIncident(db, 'resolved-1', { status: 'Resolved', severity: 'Low' });

  await repo.recordSignal({ uid: 'user-1', now, incidentId: 'incident-1', signal: 'seen' });
  await assert.rejects(
    () => repo.recordSignal({
      uid: 'user-1',
      now: new Date(now.getTime() + 1000),
      incidentId: 'incident-2',
      signal: 'seen',
    }),
    (error) => error.code === 'resource-exhausted',
  );

  const resolved = await repo.recordSignal({
    uid: 'user-2',
    now,
    incidentId: 'resolved-1',
    signal: 'seen',
  });
  assert.deepEqual(resolved, { status: 'Resolved', severity: 'Low', applied: false });
  assert.equal(shardCount(db, 'resolved-1'), 0);
  assert.equal(db.has('safety_incident_signal_voters_private/resolved-1_user-2'), false);
});

test('recordSignal voter ledger falls back to now plus 60 days when public deleteAfter is absent', async () => {
  const db = new FakeFirestore();
  const repo = new IncidentRepository(db);
  const now = new Date('2026-07-10T12:00:00.000Z');
  seedIncident(db, 'incident-1', { deleteAfter: undefined });

  await repo.recordSignal({ uid: 'user-1', now, incidentId: 'incident-1', signal: 'seen' });

  assert.equal(
    db.get('safety_incident_signal_voters_private/incident-1_user-1').deleteAfter.toDate().toISOString(),
    new Date(now.getTime() + 60 * 24 * 60 * 60 * 1000).toISOString(),
  );
});

test('submitIncident stamps standard trust tier when reporter reputation is absent', async () => {
  const db = new FakeFirestore();
  const repo = new IncidentRepository(db);
  const result = await repo.submitIncident({
    uid: 'user-1',
    now: new Date('2026-07-10T12:00:00.000Z'),
    payload: submitPayload(),
  });

  const publicDoc = db.get(`safety_incidents_public/${result.incident_id}`);
  assert.equal(publicDoc.reporter_trust_tier, 'standard');
  assert.equal(Object.prototype.hasOwnProperty.call(publicDoc, 'ownerUid'), false);
});

test('submitIncident treats an invalid reporter reputation tier as standard', async () => {
  const db = new FakeFirestore();
  db.seed('reporter_reputation_private/user-1', { tier: 'elite' });
  const repo = new IncidentRepository(db);
  const result = await repo.submitIncident({
    uid: 'user-1',
    now: new Date('2026-07-10T12:00:00.000Z'),
    payload: submitPayload(),
  });

  const publicDoc = db.get(`safety_incidents_public/${result.incident_id}`);
  assert.equal(publicDoc.reporter_trust_tier, 'standard');
  assert.equal(Object.prototype.hasOwnProperty.call(publicDoc, 'ownerUid'), false);
});

test('submitIncident stamps trusted tier from reporter reputation without exposing ownerUid', async () => {
  const db = new FakeFirestore();
  db.seed('reporter_reputation_private/user-1', { tier: 'trusted' });
  const repo = new IncidentRepository(db);
  const result = await repo.submitIncident({
    uid: 'user-1',
    now: new Date('2026-07-10T12:00:00.000Z'),
    payload: submitPayload(),
  });

  const publicDoc = db.get(`safety_incidents_public/${result.incident_id}`);
  assert.equal(publicDoc.reporter_trust_tier, 'trusted');
  assert.equal(Object.prototype.hasOwnProperty.call(publicDoc, 'ownerUid'), false);
});

function seedIncident(db, incidentId, overrides = {}) {
  db.seed(`safety_incidents_public/${incidentId}`, {
    title: 'Street flooding',
    summary: 'Water covering the road',
    category: 'traffic',
    subtype: 'road_closure',
    status: 'Active',
    severity: 'Medium',
    confirmations: 1,
    disputes: 0,
    cleared_reports: 0,
    deleteAfter: Timestamp.fromDate(new Date('2026-07-10T15:00:00.000Z')),
    ...overrides,
  });
}

function submitPayload() {
  return {
    clientRef: 'client-ref-1',
    title: 'Street flooding',
    summary: 'Water covering the road',
    category: 'traffic',
    subtype: 'road_closure',
    severity: 'Medium',
    status: 'Active',
    neighborhood: 'Nearby area',
    latitude: 37.7749,
    longitude: -122.4194,
    useApproximateLocation: true,
    source: 'ios',
    evidence: [],
  };
}

function shardCount(db, incidentId, counterField) {
  return db.collectionDocs('safety_incident_counter_shards_private')
    .filter((doc) => doc.incidentId === incidentId)
    .filter((doc) => !counterField || doc.counterField === counterField)
    .reduce((total, doc) => total + doc.count, 0);
}

class FakeFirestore {
  constructor() {
    this.docs = new Map();
    this.nextId = 1;
  }

  collection(path) {
    return new FakeCollectionRef(this, path);
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
      .filter(([path]) => path.startsWith(`${query.collectionPath}/`));
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

  orderBy() {
    return new FakeQuery(this.db, this.path);
  }
}

class FakeDocRef {
  constructor(db, collectionPath, id) {
    this.db = db;
    this.collectionPath = collectionPath;
    this.id = id;
    this.path = `${collectionPath}/${id}`;
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

  orderBy() {
    return this;
  }

  async get() {
    return { empty: this.db.queryDocs(this).length === 0, docs: this.db.queryDocs(this) };
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
      const data = this.db.docs.get(refOrQuery.path);
      return new FakeDocSnapshot(refOrQuery.id, data);
    }
    return { docs: this.db.queryDocs(refOrQuery), empty: this.db.queryDocs(refOrQuery).length === 0 };
  }

  set(ref, data, options = {}) {
    this.hasWritten = true;
    const current = options.merge ? this.db.docs.get(ref.path) || {} : {};
    this.db.docs.set(ref.path, applyWrite(current, data));
  }

  create(ref, data) {
    this.hasWritten = true;
    assert.equal(this.db.docs.has(ref.path), false, `${ref.path} already exists`);
    this.db.docs.set(ref.path, applyWrite({}, data));
  }

  update(ref, data) {
    this.hasWritten = true;
    const current = this.db.docs.get(ref.path);
    assert.ok(current, `Expected ${ref.path} to exist before update`);
    this.db.docs.set(ref.path, applyWrite(current, data));
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

function applyWrite(current, data) {
  const next = cloneData(current);
  for (const [key, value] of Object.entries(data)) {
    if (isIncrement(value)) {
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
  if (op === '>') {
    return comparableValue(actual) > comparableValue(expected);
  }
  if (op === 'in') {
    return Array.isArray(expected) && expected.includes(actual);
  }
  throw new Error(`Unsupported fake query op ${op}`);
}

function comparableValue(value) {
  if (value && typeof value.toMillis === 'function') {
    return value.toMillis();
  }
  if (value instanceof Date) {
    return value.getTime();
  }
  return value;
}

function cloneData(value) {
  if (value === null || typeof value !== 'object') {
    return value;
  }
  if (typeof value.toDate === 'function' || isIncrement(value) || value.constructor.name === 'ServerTimestampTransform') {
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
