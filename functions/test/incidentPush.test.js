'use strict';

process.env.NODE_ENV = 'test';

const assert = require('node:assert/strict');
const test = require('node:test');
const { __test } = require('../lib/index');

const baseIncident = {
  title: 'Smoke at market',
  summary: 'Residents report thick smoke near the north gate and are avoiding the area.',
  category: 'fire',
  severity: 'Medium',
  status: 'Active',
  neighborhood: 'Mile 12',
  public_h3_cell: '862a1072fffffff',
  public_h3_resolution: 6,
  location_reveal_status: 'revealed',
};

test('transition matrix sends reveal and escalation alerts only for qualifying changes', () => {
  assert.deepEqual(
    __test.pendingAlertKindsForPublicWrite(
      { ...baseIncident, location_reveal_status: 'pending_k_anonymity' },
      baseIncident,
    ),
    ['reveal'],
  );

  assert.deepEqual(
    __test.pendingAlertKindsForPublicWrite(baseIncident, { ...baseIncident, summary: 'Updated public summary.' }),
    [],
  );

  assert.deepEqual(
    __test.pendingAlertKindsForPublicWrite(baseIncident, { ...baseIncident, severity: 'High' }),
    ['escalation'],
  );

  assert.deepEqual(
    __test.pendingAlertKindsForPublicWrite(
      { ...baseIncident, severity: 'High' },
      { ...baseIncident, severity: 'Urgent' },
      { escalationAlertSentAt: new Date('2026-07-10T12:00:00Z') },
    ),
    [],
  );

  assert.deepEqual(
    __test.pendingAlertKindsForPublicWrite(null, baseIncident),
    ['reveal'],
  );

  assert.deepEqual(
    __test.pendingAlertKindsForPublicWrite(
      { ...baseIncident, location_reveal_status: 'pending_k_anonymity' },
      { ...baseIncident, status: 'Resolved' },
    ),
    [],
  );
});

test('created already revealed high-severity incidents qualify for both alert types before marker filtering', () => {
  assert.deepEqual(
    __test.candidateAlertKindsForPublicWrite(null, { ...baseIncident, severity: 'High' }),
    ['reveal', 'escalation'],
  );
});

test('topic names are derived at H3 resolution 6 and capped', () => {
  const payload = validPayload({ urgent_alerts: true, community_alerts: true, watch_radius_km: 15 });
  const cells = __test.topicCellsForWatchRegion(payload.latitude, payload.longitude, payload.watch_radius_km);
  const topics = __test.topicNamesForPreferences(payload);

  assert.ok(cells.length > 0);
  assert.ok(cells.length <= __test.PUSH_MAX_TOPIC_CELLS);
  assert.equal(topics.length, cells.length * 2);
  assert.ok(topics.every((topic) => /^incident_(urgent|community)_86/.test(topic)));
});

test('tier mapping sends severe and critical-category incidents to urgent topics', () => {
  assert.equal(__test.incidentAlertTier({ severity: 'High', category: 'traffic' }), 'urgent');
  assert.equal(__test.incidentAlertTier({ severity: 'Medium', category: 'medical' }), 'urgent');
  assert.equal(__test.incidentAlertTier({ severity: 'Medium', category: 'community' }), 'community');
});

test('message payload contains only public alert fields and routing data', () => {
  const incident = {
    ...baseIncident,
    latitude: 6.52438,
    longitude: 3.37921,
    geohash: 's14k3',
    summary: 'A'.repeat(180),
  };
  const message = __test.buildIncidentPushMessage({
    incidentId: 'incident-1',
    incident,
    tier: 'urgent',
  });
  const serialized = JSON.stringify(message);

  assert.equal(message.notification.title, 'Fire: Smoke at market');
  assert.match(message.notification.body, /^Mile 12/);
  assert.ok(message.notification.body.length <= 'Mile 12 — '.length + 120);
  assert.deepEqual(message.data, {
    incident_id: 'incident-1',
    deep_link: 'pulsetrackr://incident/incident-1',
  });
  assert.ok(message.apns.payload.aps.contentAvailable);
  assert.equal(message.apns.payload.aps.sound, 'default');
  assert.doesNotMatch(serialized, /6\.52438|3\.37921|s14k3|latitude|longitude|geohash/);
});

test('public task payload is redacted to fields needed by the worker', () => {
  const payload = __test.publicIncidentTaskPayload({
    ...baseIncident,
    latitude: 40.7128,
    longitude: -74.006,
    geohash: 'dr5reg',
  });

  assert.equal(payload.title, baseIncident.title);
  assert.equal(payload.public_h3_cell, baseIncident.public_h3_cell);
  assert.equal(Object.hasOwn(payload, 'latitude'), false);
  assert.equal(Object.hasOwn(payload, 'longitude'), false);
  assert.equal(Object.hasOwn(payload, 'geohash'), false);
});

test('registry record contains no queryable location fields', () => {
  const payload = validPayload();
  const topics = __test.topicNamesForPreferences(payload);
  const record = __test.registryRecordForDevice({
    uid: 'user-1',
    payload,
    subscribedTopics: topics,
  });

  assert.equal(record.owner_uid, 'user-1');
  assert.equal(record.fcm_token, payload.fcm_token);
  assert.equal(record.platform, 'ios');
  assert.equal(record.subscribed_topics.length, topics.length);
  assert.equal(Object.hasOwn(record, 'latitude'), false);
  assert.equal(Object.hasOwn(record, 'longitude'), false);
  assert.equal(Object.hasOwn(record, 'watch_radius_km'), false);
  assert.equal(Object.hasOwn(record, 'geohash'), false);
  assert.equal(Object.hasOwn(record, 'h3_cell'), false);
});

test('topic diff reconciliation subscribes and unsubscribes only changed topics', () => {
  assert.deepEqual(
    __test.diffTopicSubscriptions(
      ['incident_urgent_a', 'incident_community_a', 'incident_community_b'],
      ['incident_urgent_a', 'incident_urgent_b', 'incident_community_b'],
    ),
    {
      subscribe: ['incident_urgent_b'],
      unsubscribe: ['incident_community_a'],
    },
  );
});

test('push payload validation follows the generated contract', () => {
  assert.equal(__test.sanitizeRegisterPushDevicePayload(validPayload()).platform, 'ios');
  assert.throws(
    () => __test.sanitizeRegisterPushDevicePayload(validPayload({ latitude: 120 })),
    /Number must be less than or equal to 90|latitude/i,
  );
});

test('device doc id hashes the FCM token instead of embedding it', () => {
  const docId = __test.pushDeviceDocId('user-1', 'secret-fcm-token');
  assert.match(docId, /^user-1_[a-f0-9]{16}$/);
  assert.doesNotMatch(docId, /secret-fcm-token/);
});

function validPayload(overrides = {}) {
  return {
    fcm_token: 'fcm-token-123',
    platform: 'ios',
    app_version: '1.2.3',
    urgent_alerts: true,
    community_alerts: false,
    latitude: 6.52438,
    longitude: 3.37921,
    watch_radius_km: 3,
    ...overrides,
  };
}
