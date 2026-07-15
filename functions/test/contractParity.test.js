'use strict';

// Pins the single-source-of-truth guarantee: the server's incident signal rules
// (deriveSignalOutcome) must agree with the shared contract state machine
// (@pulsetrackr/contract applySignal), which the iOS client also uses. If these
// drift, this test fails before the divergence can reach production.

process.env.NODE_ENV = 'test';

const assert = require('node:assert/strict');
const test = require('node:test');

const { __test } = require('../lib/index');
const contract = require('@pulsetrackr/contract');

const SIGNALS = ['seen', 'notSeen', 'unsafe', 'roadBlocked', 'cleared'];
const STATUSES = ['Active', 'Watching', 'Resolved'];
const SEVERITIES = ['Low', 'Medium', 'High', 'Urgent'];

function serverState(overrides) {
  return {
    status: 'Active',
    severity: 'Medium',
    confirmations: 1,
    disputes: 0,
    unsafeReports: 0,
    blockedReports: 0,
    clearedReports: 0,
    ...overrides,
  };
}

test('server deriveSignalOutcome matches contract applySignal across the full matrix', () => {
  for (const signal of SIGNALS) {
    for (const status of STATUSES) {
      for (const severity of SEVERITIES) {
        for (const confirmations of [0, 1, 5]) {
          for (const disputes of [0, 1, 5]) {
            for (const clearedReports of [0, 2, 3]) {
              const base = serverState({ status, severity, confirmations, disputes, clearedReports });

              // Server returns only {status, severity}; it reads cleared_reports (snake).
              const server = __test.deriveSignalOutcome(signal, {
                status,
                severity,
                confirmations,
                disputes,
                cleared_reports: clearedReports,
              });

              const contractNext = contract.applySignal(base, signal);

              assert.equal(
                contractNext.status,
                server.status,
                `status drift for ${signal} @ ${status}/${severity} c=${confirmations} d=${disputes} cl=${clearedReports}`,
              );
              assert.equal(
                contractNext.severity,
                server.severity,
                `severity drift for ${signal} @ ${status}/${severity} c=${confirmations} d=${disputes} cl=${clearedReports}`,
              );
            }
          }
        }
      }
    }
  }
});

test('contract signal vocabulary matches the server counter-field map', () => {
  const serverSignals = Object.keys(__test.SIGNAL_COUNTER_FIELD).sort();
  const contractSignals = [...contract.communitySignal.options].sort();
  assert.deepEqual(contractSignals, serverSignals);
});
