'use strict';

process.env.NODE_ENV = 'test';
process.env.SOS_ENVELOPE_KEK = Buffer.alloc(32, 7).toString('base64');

const assert = require('node:assert/strict');
const test = require('node:test');
const {
  incidentLocationPrivacy,
  publicLocationFields,
} = require('../lib/shared/locationPrivacy');
const { h3QueryCellsForRadius } = require('../lib/shared/h3Feed');
const {
  decryptPrivateJson,
  encryptPrivateJson,
} = require('../lib/shared/envelope');

test('incident H3 privacy metadata is deterministic and k-anonymous by default', () => {
  const first = incidentLocationPrivacy(40.7128, -74.0060);
  const second = incidentLocationPrivacy(40.7128, -74.0060);

  assert.equal(first.privateH3Cell, second.privateH3Cell);
  assert.equal(first.privateH3Resolution, 8);
  assert.equal(first.privateH3ParentResolution, 7);
  assert.equal(first.threshold, 3);

  const fields = publicLocationFields({
    ...first,
    status: 'pending_k_anonymity',
    distinctReporterCount: 1,
    existingReportIdsToReveal: [],
  });
  assert.equal(fields.location_reveal_status, 'pending_k_anonymity');
  assert.equal(fields.location_privacy_policy, 'h3_k_anonymous');
  assert.equal(fields.latitude, undefined);
  assert.equal(fields.geohash, undefined);
});

test('envelope encryption round-trips only with matching authenticated context', () => {
  const aad = {
    domain: 'pulsetrackr.sos.location',
    sessionId: 'session-1',
    ownerUid: 'owner-1',
    field: 'lastKnownLocation',
  };
  const location = {
    latitude: 6.52,
    longitude: 3.37,
    capturedAt: '2026-06-21T12:00:00.000Z',
  };
  const encrypted = encryptPrivateJson(location, aad);

  assert.notEqual(encrypted.payload.ciphertext, JSON.stringify(location));
  assert.deepEqual(decryptPrivateJson(encrypted, aad), location);
  assert.throws(() => decryptPrivateJson(encrypted, { ...aad, field: 'recentTrail' }), /context mismatch/);
});

test('H3 feed query expands to bounded hierarchical public cells', () => {
  const cells = h3QueryCellsForRadius(40.7128, -74.0060, 3000);
  assert.equal(cells.length > 1, true);
  assert.equal(cells.length <= 300, true);
  assert.equal(new Set(cells).size, cells.length);
});
