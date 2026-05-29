'use strict';

const crypto = require('node:crypto');

const DEFAULT_POLICY = Object.freeze({
  includeRecentTrail: true,
  recentTrailMaxPoints: 12,
  recentTrailMaxAgeSeconds: 15 * 60,
  liveLocationUpdateIntervalSeconds: 30,
  shareExactLocationWithTrustedContacts: true,
  adminAccessExpiresAfterSeconds: 60 * 60,
  lawEnforcementAccessRequiresActiveSession: true,
  auditPrivilegedAccess: true,
});

const HARD_LIMITS = Object.freeze({
  recentTrailMaxPoints: 24,
  recentTrailMaxAgeSeconds: 30 * 60,
  liveLocationUpdateIntervalSeconds: 15,
  adminAccessExpiresAfterSeconds: 2 * 60 * 60,
  retentionSeconds: 30 * 24 * 60 * 60,
  activationCooldownSeconds: 60,
  activationWindowSeconds: 60 * 60,
  activationWindowLimit: 5,
});

const ALLOWED_RESOLUTION_REASONS = new Set([
  'user_resolved',
  'false_alarm',
  'timed_out',
  'transferred_to_care_team',
]);

const ALLOWED_CHANNELS = new Set(['sms', 'phone_call', 'email']);
const PRIVILEGED_ROLES = new Set(['sosAdmin', 'careTeam', 'lawEnforcement']);

function requiredString(value, fieldName) {
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw invalidArgument(`${fieldName} is required`);
  }
  return value.trim();
}

function optionalString(value) {
  return typeof value === 'string' && value.trim().length > 0 ? value.trim() : null;
}

function parseDate(value, fieldName, fallback = new Date()) {
  if (value == null) {
    return fallback;
  }
  if (value instanceof Date && !Number.isNaN(value.getTime())) {
    return value;
  }
  if (typeof value === 'string') {
    const date = new Date(value);
    if (!Number.isNaN(date.getTime())) {
      return date;
    }
  }
  throw invalidArgument(`${fieldName} must be an ISO-8601 timestamp`);
}

function clampNumber(value, fallback, min, max) {
  const number = Number(value);
  if (!Number.isFinite(number)) {
    return fallback;
  }
  return Math.min(max, Math.max(min, number));
}

function clampInteger(value, fallback, min, max) {
  const clamped = clampNumber(value, fallback, min, max);
  return clamped == null ? null : Math.round(clamped);
}

function sanitizePrivacyPolicy(input = {}) {
  return {
    includeRecentTrail: input.include_recent_trail !== false,
    recentTrailMaxPoints: clampInteger(
      input.recent_trail_max_points,
      DEFAULT_POLICY.recentTrailMaxPoints,
      0,
      HARD_LIMITS.recentTrailMaxPoints,
    ),
    recentTrailMaxAgeSeconds: clampInteger(
      input.recent_trail_max_age_seconds,
      DEFAULT_POLICY.recentTrailMaxAgeSeconds,
      0,
      HARD_LIMITS.recentTrailMaxAgeSeconds,
    ),
    liveLocationUpdateIntervalSeconds: clampInteger(
      input.live_location_update_interval_seconds,
      DEFAULT_POLICY.liveLocationUpdateIntervalSeconds,
      HARD_LIMITS.liveLocationUpdateIntervalSeconds,
      5 * 60,
    ),
    shareExactLocationWithTrustedContacts: input.share_exact_location_with_trusted_contacts !== false,
    adminAccessExpiresAfterSeconds: clampInteger(
      input.admin_access_expires_after_seconds,
      DEFAULT_POLICY.adminAccessExpiresAfterSeconds,
      60,
      HARD_LIMITS.adminAccessExpiresAfterSeconds,
    ),
    lawEnforcementAccessRequiresActiveSession: input.law_enforcement_access_requires_active_session !== false,
    auditPrivilegedAccess: input.audit_privileged_access !== false,
  };
}

function sanitizeLocationSnapshot(input, fieldName = 'location') {
  if (typeof input !== 'object' || input == null) {
    throw invalidArgument(`${fieldName} is required`);
  }

  const latitude = Number(input.latitude);
  const longitude = Number(input.longitude);
  if (!Number.isFinite(latitude) || latitude < -90 || latitude > 90) {
    throw invalidArgument(`${fieldName}.latitude is invalid`);
  }
  if (!Number.isFinite(longitude) || longitude < -180 || longitude > 180) {
    throw invalidArgument(`${fieldName}.longitude is invalid`);
  }

  return withoutNullish({
    latitude,
    longitude,
    horizontalAccuracyMeters: nonNegative(input.horizontal_accuracy_meters),
    altitudeMeters: finiteOrNull(input.altitude_meters),
    speedMetersPerSecond: nonNegative(input.speed_meters_per_second),
    courseDegrees: normalizeDegrees(input.course_degrees),
    capturedAt: parseDate(input.captured_at, `${fieldName}.captured_at`),
  });
}

function sanitizeDirectionOfTravel(input) {
  if (typeof input !== 'object' || input == null) {
    return null;
  }

  return withoutNullish({
    bearingDegrees: normalizeDegrees(input.bearing_degrees),
    speedMetersPerSecond: nonNegative(input.speed_meters_per_second),
    computedFromPointCount: clampInteger(input.computed_from_point_count, 0, 0, 1000),
  });
}

function sanitizeDevice(input = {}) {
  if (typeof input !== 'object' || input == null) {
    return {};
  }

  return withoutNullish({
    batteryLevelPercent: clampInteger(input.battery_level_percent, null, 0, 100),
    batteryState: optionalString(input.battery_state),
    lowPowerModeEnabled: input.low_power_mode_enabled === true,
    networkStatus: optionalString(input.network_status),
    networkInterfaceTypes: Array.isArray(input.network_interface_types)
      ? input.network_interface_types.map(optionalString).filter(Boolean).slice(0, 6)
      : [],
    appVersion: optionalString(input.app_version),
    buildNumber: optionalString(input.build_number),
    deviceModel: optionalString(input.device_model),
    systemVersion: optionalString(input.system_version),
  });
}

function sanitizeTrustedContacts(input = []) {
  if (!Array.isArray(input)) {
    throw invalidArgument('trusted_contacts_to_notify must be an array');
  }

  return input.slice(0, 10).map((contact, index) => {
    if (typeof contact !== 'object' || contact == null) {
      throw invalidArgument(`trusted_contacts_to_notify[${index}] is invalid`);
    }
    const contactId = requiredString(contact.contact_id, `trusted_contacts_to_notify[${index}].contact_id`);
    const channels = Array.isArray(contact.channels)
      ? contact.channels.filter((channel) => ALLOWED_CHANNELS.has(channel))
      : [];
    const phoneNumber = optionalString(contact.phone_number);
    const emailAddress = optionalString(contact.email_address);
    const deliverableChannels = channels.filter((channel) => {
      if (channel === 'email') return Boolean(emailAddress);
      return Boolean(phoneNumber);
    });

    return withoutNullish({
      contactId,
      displayName: requiredString(contact.display_name, `trusted_contacts_to_notify[${index}].display_name`),
      relationshipLabel: optionalString(contact.relationship_label),
      phoneNumber,
      emailAddress,
      channels: [...new Set(deliverableChannels)],
      consentedAt: contact.consented_at ? parseDate(contact.consented_at, `trusted_contacts_to_notify[${index}].consented_at`) : null,
    });
  }).filter((contact) => contact.channels.length > 0);
}

function limitRecentTrail(input, activatedAt, privacy) {
  if (!privacy.includeRecentTrail) {
    return [];
  }
  if (!Array.isArray(input)) {
    return [];
  }

  const oldest = activatedAt.getTime() - privacy.recentTrailMaxAgeSeconds * 1000;
  return input
    .map((point, index) => sanitizeLocationSnapshot(point, `recent_trail[${index}]`))
    .filter((point) => {
      const time = point.capturedAt.getTime();
      return time >= oldest && time <= activatedAt.getTime();
    })
    .sort((a, b) => a.capturedAt.getTime() - b.capturedAt.getTime())
    .slice(-privacy.recentTrailMaxPoints);
}

function sanitizeActivationPayload(data, now = new Date()) {
  const activatedAt = parseDate(data.activated_at, 'activated_at', now);
  const privacy = sanitizePrivacyPolicy(data.privacy);

  return {
    clientSessionId: requiredString(data.client_session_id, 'client_session_id'),
    source: optionalString(data.source) || 'ios',
    activatedAt,
    lastKnownLocation: sanitizeLocationSnapshot(data.last_known_location, 'last_known_location'),
    recentTrail: limitRecentTrail(data.recent_trail, activatedAt, privacy),
    directionOfTravel: sanitizeDirectionOfTravel(data.direction_of_travel),
    trustedContacts: sanitizeTrustedContacts(data.trusted_contacts_to_notify),
    device: sanitizeDevice(data.device),
    privacy,
  };
}

function sanitizeLocationUpdatePayload(data) {
  return {
    sessionId: requiredString(data.session_id, 'session_id'),
    location: sanitizeLocationSnapshot(data.location, 'location'),
    sequenceNumber: clampInteger(data.sequence_number, 0, 0, Number.MAX_SAFE_INTEGER),
    capturedAt: parseDate(data.captured_at, 'captured_at'),
    directionOfTravel: sanitizeDirectionOfTravel(data.direction_of_travel),
    device: sanitizeDevice(data.device),
  };
}

function sanitizeResolutionPayload(data) {
  const reason = requiredString(data.resolution_reason, 'resolution_reason');
  if (!ALLOWED_RESOLUTION_REASONS.has(reason)) {
    throw invalidArgument('resolution_reason is not supported');
  }

  return {
    sessionId: requiredString(data.session_id, 'session_id'),
    reason,
    resolvedAt: parseDate(data.resolved_at, 'resolved_at'),
    finalLocation: data.final_location ? sanitizeLocationSnapshot(data.final_location, 'final_location') : null,
  };
}

function makeIdempotencyKey(uid, clientSessionId) {
  const hash = crypto
    .createHash('sha256')
    .update(`${uid}:${clientSessionId}`)
    .digest('hex')
    .slice(0, 40);
  return `${uid.slice(0, 24)}_${hash}`;
}

function makeLocationUpdateId(sessionId, sequenceNumber) {
  return `${sessionId}_${String(sequenceNumber).padStart(12, '0')}`;
}

function redactedContact(contact) {
  return withoutNullish({
    contactId: contact.contactId,
    displayName: contact.displayName,
    relationshipLabel: contact.relationshipLabel,
    channels: contact.channels,
    phoneLast4: contact.phoneNumber ? contact.phoneNumber.slice(-4) : null,
    hasEmailAddress: Boolean(contact.emailAddress),
    consentedAt: contact.consentedAt || null,
  });
}

function privilegedRoleFromClaims(claims = {}) {
  for (const role of PRIVILEGED_ROLES) {
    if (claims[role] === true) {
      return role;
    }
  }
  return null;
}

function withoutNullish(object) {
  return Object.fromEntries(Object.entries(object).filter(([, value]) => value != null));
}

function finiteOrNull(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function nonNegative(value) {
  const number = finiteOrNull(value);
  return number == null ? null : Math.max(0, number);
}

function normalizeDegrees(value) {
  const number = finiteOrNull(value);
  if (number == null) return null;
  const normalized = number % 360;
  return normalized >= 0 ? normalized : normalized + 360;
}

function invalidArgument(message) {
  const error = new Error(message);
  error.code = 'invalid-argument';
  return error;
}

module.exports = {
  ALLOWED_RESOLUTION_REASONS,
  HARD_LIMITS,
  DEFAULT_POLICY,
  makeIdempotencyKey,
  makeLocationUpdateId,
  privilegedRoleFromClaims,
  redactedContact,
  sanitizeActivationPayload,
  sanitizeLocationUpdatePayload,
  sanitizePrivacyPolicy,
  sanitizeResolutionPayload,
};
