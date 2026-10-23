'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const {
  makeIdempotencyKey,
  makeLocationUpdateId,
  privilegedRoleFromClaims,
  redactedContact,
  sanitizeActivationPayload,
  sanitizeLawEnforcementRequestPayload,
  sanitizeLawEnforcementReviewPayload,
  sanitizeLocationUpdatePayload,
  sanitizePrivacyPolicy,
  sanitizeResolutionPayload,
} = require('../lib/sosShared');

test('activation payload caps recent trail by policy and hard limits', () => {
  const activatedAt = new Date('2026-05-27T12:00:00.000Z');
  const trail = Array.from({ length: 40 }, (_, index) => ({
    latitude: 6.45 + index / 1000,
    longitude: 3.39,
    captured_at: new Date(activatedAt.getTime() - (39 - index) * 60 * 1000).toISOString(),
  }));

  const payload = sanitizeActivationPayload({
    client_session_id: 'client-1',
    activated_at: activatedAt.toISOString(),
    last_known_location: trail.at(-1),
    recent_trail: trail,
    privacy: {
      recent_trail_max_points: 99,
      recent_trail_max_age_seconds: 99 * 60,
    },
  }, activatedAt);

  assert.equal(payload.recentTrail.length, 24);
  assert.equal(payload.recentTrail[0].latitude, 6.466);
  assert.equal(payload.privacy.recentTrailMaxPoints, 24);
  assert.equal(payload.privacy.recentTrailMaxAgeSeconds, 1800);
});

test('activation payload rejects invalid coordinates', () => {
  assert.throws(() => sanitizeActivationPayload({
    client_session_id: 'client-1',
    last_known_location: { latitude: 200, longitude: 3.4, captured_at: '2026-05-27T12:00:00Z' },
  }), /latitude is invalid/);
});

test('trusted contacts are deliverable and redacted for diagnostics/access', () => {
  const payload = sanitizeActivationPayload({
    client_session_id: 'client-1',
    last_known_location: { latitude: 6.52, longitude: 3.37, captured_at: '2026-05-27T12:00:00Z' },
    trusted_contacts_to_notify: [{
      contact_id: 'contact-1',
      display_name: 'Ada',
      phone_number: '+2348012345678',
      email_address: 'ada@example.com',
      channels: ['sms', 'email', 'phone_call', 'fax'],
    }],
  });

  assert.deepEqual(payload.trustedContacts[0].channels, ['sms', 'email', 'phone_call']);
  assert.deepEqual(redactedContact(payload.trustedContacts[0]), {
    contactId: 'contact-1',
    displayName: 'Ada',
    channels: ['sms', 'email', 'phone_call'],
    phoneLast4: '5678',
    hasEmailAddress: true,
    hasAppRoute: false,
  });
});

test('app trusted contact channel requires an accepted app route', () => {
  const payload = sanitizeActivationPayload({
    client_session_id: 'client-1',
    last_known_location: { latitude: 6.52, longitude: 3.37, captured_at: '2026-05-27T12:00:00Z' },
    trusted_contacts_to_notify: [{
      contact_id: 'contact-1',
      display_name: 'Ada',
      app_user_uid: 'trusted-user-1',
      app_relationship_id: 'relationship-1',
      channels: ['app_push'],
    }, {
      contact_id: 'contact-2',
      display_name: 'Ben',
      app_user_uid: 'trusted-user-2',
      channels: ['app_push'],
    }],
  });

  assert.equal(payload.trustedContacts.length, 1);
  assert.deepEqual(payload.trustedContacts[0].channels, ['app_push']);
  assert.deepEqual(redactedContact(payload.trustedContacts[0]), {
    contactId: 'contact-1',
    displayName: 'Ada',
    channels: ['app_push'],
    hasEmailAddress: false,
    appRelationshipId: 'relationship-1',
    hasAppRoute: true,
  });
});

test('escort activation requires one app relationship and strips notification contacts', () => {
  const payload = sanitizeActivationPayload({
    client_session_id: 'client-escort',
    session_kind: 'escort',
    escort_relationship_id: 'relationship-1',
    last_known_location: { latitude: 6.52, longitude: 3.37, captured_at: '2026-05-27T12:00:00Z' },
    trusted_contacts_to_notify: [{
      contact_id: 'contact-1',
      display_name: 'Ada',
      phone_number: '+2348012345678',
      channels: ['sms', 'phone_call'],
    }],
  });

  assert.equal(payload.sessionKind, 'escort');
  assert.equal(payload.escortRelationshipId, 'relationship-1');
  assert.deepEqual(payload.trustedContacts, []);

  assert.throws(() => sanitizeActivationPayload({
    client_session_id: 'client-escort',
    session_kind: 'escort',
    last_known_location: { latitude: 6.52, longitude: 3.37, captured_at: '2026-05-27T12:00:00Z' },
  }), /escort_relationship_id is required/);
});

test('legacy activation payload defaults to sos kind', () => {
  const payload = sanitizeActivationPayload({
    client_session_id: 'client-1',
    last_known_location: { latitude: 6.52, longitude: 3.37, captured_at: '2026-05-27T12:00:00Z' },
    escort_relationship_id: 'ignored-for-sos',
  });

  assert.equal(payload.sessionKind, 'sos');
  assert.equal(payload.escortRelationshipId, undefined);
});

test('location update ids are stable for idempotent append', () => {
  assert.equal(makeLocationUpdateId('abc', 7), 'abc_000000000007');
  assert.equal(makeIdempotencyKey('uid-123', 'client-abc'), makeIdempotencyKey('uid-123', 'client-abc'));
  assert.notEqual(makeIdempotencyKey('uid-123', 'client-abc'), makeIdempotencyKey('uid-123', 'client-def'));
});

test('location update payload sanitizes sequence and bearing', () => {
  const payload = sanitizeLocationUpdatePayload({
    session_id: 'session-1',
    sequence_number: -2,
    location: { latitude: 6.52, longitude: 3.37, captured_at: '2026-05-27T12:00:01Z' },
    direction_of_travel: { bearing_degrees: -10, speed_meters_per_second: 4, computed_from_point_count: 2 },
  });

  assert.equal(payload.sequenceNumber, 0);
  assert.equal(payload.directionOfTravel.bearingDegrees, 350);
});

test('device metadata does not invent missing optional values', () => {
  const payload = sanitizeActivationPayload({
    client_session_id: 'client-1',
    last_known_location: { latitude: 6.52, longitude: 3.37, captured_at: '2026-05-27T12:00:00Z' },
    device: {},
  });

  assert.equal(payload.device.batteryLevelPercent, undefined);
  assert.equal(payload.device.lowPowerModeEnabled, false);
});

test('resolution payload allows only known reasons', () => {
  assert.equal(sanitizeResolutionPayload({
    session_id: 'session-1',
    resolution_reason: 'false_alarm',
    resolved_at: '2026-05-27T12:05:00Z',
  }).reason, 'false_alarm');
  assert.equal(sanitizeResolutionPayload({
    session_id: 'session-1',
    resolution_reason: 'arrived_safely',
    resolved_at: '2026-05-27T12:05:00Z',
  }).reason, 'arrived_safely');

  assert.throws(() => sanitizeResolutionPayload({
    session_id: 'session-1',
    resolution_reason: 'other',
    resolved_at: '2026-05-27T12:05:00Z',
  }), /not supported/);
});

test('privacy policy enforces conservative server ceilings', () => {
  const policy = sanitizePrivacyPolicy({
    live_location_update_interval_seconds: 1,
    admin_access_expires_after_seconds: 999999,
  });

  assert.equal(policy.liveLocationUpdateIntervalSeconds, 15);
  assert.equal(policy.adminAccessExpiresAfterSeconds, 7200);
});

test('privileged role claim is explicit', () => {
  assert.equal(privilegedRoleFromClaims({}), null);
  assert.equal(privilegedRoleFromClaims({ lawEnforcement: true }), 'lawEnforcement');
});

test('law enforcement request payload requires legal process metadata', () => {
  const payload = sanitizeLawEnforcementRequestPayload({
    session_id: 'session-1',
    agency_name: 'Lagos Police Command',
    requester_name: 'Inspector Doe',
    requester_email: 'inspector@example.gov',
    legal_process_type: 'warrant',
    legal_reference: 'CASE-123',
    requested_scope: ['last_known_location', 'direction_of_travel', 'unknown'],
  }, new Date('2026-06-11T12:00:00Z'));

  assert.equal(payload.sessionId, 'session-1');
  assert.equal(payload.legalProcessType, 'warrant');
  assert.deepEqual(payload.requestedScope, ['last_known_location', 'direction_of_travel']);
  assert.equal(payload.urgency, 'active_sos');

  assert.throws(() => sanitizeLawEnforcementRequestPayload({
    session_id: 'session-1',
    agency_name: 'Agency',
    requester_name: 'Officer',
    legal_process_type: 'text_message',
    legal_reference: 'CASE-123',
  }), /legal_process_type is not supported/);
});

test('law enforcement review payload constrains decision and scope', () => {
  const payload = sanitizeLawEnforcementReviewPayload({
    legal_request_id: 'legal-1',
    decision: 'approved',
    review_note: 'Valid warrant for active SOS session',
    approved_scope: ['last_known_location', 'recent_trail', 'raw_contact_destinations'],
    expires_at: '2026-06-11T12:30:00Z',
  }, new Date('2026-06-11T12:00:00Z'));

  assert.equal(payload.legalRequestId, 'legal-1');
  assert.equal(payload.decision, 'approved');
  assert.deepEqual(payload.approvedScope, ['last_known_location', 'recent_trail']);
  assert.equal(payload.expiresAt.toISOString(), '2026-06-11T12:30:00.000Z');

  assert.throws(() => sanitizeLawEnforcementReviewPayload({
    legal_request_id: 'legal-1',
    decision: 'maybe',
    review_note: 'Unclear',
  }), /decision must be approved or denied/);
});
