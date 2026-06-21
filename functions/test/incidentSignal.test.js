'use strict';

process.env.NODE_ENV = 'test';

const assert = require('node:assert/strict');
const test = require('node:test');
const { __test } = require('../lib/index');

const {
  counterTotalsFromShardDocs,
  deriveSignalOutcome,
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
