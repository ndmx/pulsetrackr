'use strict';

process.env.NODE_ENV = 'test';

const assert = require('node:assert/strict');
const test = require('node:test');
const { __test } = require('../lib/index');

const requiredPayload = {
  client_ref: 'client-1',
  title: 'Smoke nearby',
  summary: 'People nearby report seeing smoke from the next block.',
};

test('incident payload rejects missing coordinates instead of inventing a fallback', () => {
  assert.throws(() => __test.sanitizeIncidentPayload(
    requiredPayload,
    'uid-1'
  ), /valid latitude and longitude/);
});

test('incident payload accepts valid supplied coordinates', () => {
  const payload = __test.sanitizeIncidentPayload({
    ...requiredPayload,
    latitude: 40.7128,
    longitude: -74.0060,
    use_approximate_location: false,
  }, 'uid-1');

  assert.equal(payload.latitude, 40.7128);
  assert.equal(payload.longitude, -74.0060);
  assert.equal(__test.publicIncidentCoordinate(payload), undefined);
});

test('incident payload rejects partial coordinates', () => {
  assert.throws(() => __test.sanitizeIncidentPayload({
    ...requiredPayload,
    latitude: 40.7128,
  }, 'uid-1'), /provided together/);
});

test('incident payload rejects invalid supplied coordinates', () => {
  assert.throws(() => __test.sanitizeIncidentPayload({
    ...requiredPayload,
    latitude: 200,
    longitude: -74.0060,
  }, 'uid-1'), /valid latitude and longitude/);
});

test('public incident TTL keeps critical alerts for four hours', () => {
  const now = new Date('2026-06-02T12:00:00.000Z');
  const deleteAfter = __test.publicIncidentDeleteAfter(now, {
    category: 'security',
    subtype: 'armed_robbery',
    severity: 'Medium',
  });

  assert.equal(deleteAfter.toISOString(), '2026-06-02T16:00:00.000Z');
  assert.equal(__test.isCriticalPublicAlert({ severity: 'High', category: 'traffic' }), true);
});

test('public incident TTL removes non-critical alerts after three hours', () => {
  const now = new Date('2026-06-02T12:00:00.000Z');
  const deleteAfter = __test.publicIncidentDeleteAfter(now, {
    category: 'traffic',
    subtype: 'gridlock',
    severity: 'Medium',
  });

  assert.equal(deleteAfter.toISOString(), '2026-06-02T15:00:00.000Z');
  assert.equal(__test.isCriticalPublicAlert({ severity: 'Medium', category: 'traffic' }), false);
});
