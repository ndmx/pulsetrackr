'use strict';

// Cloud Functions entry point. This is a thin barrel: each callable lives in its
// bounded-context module (incidents / sos / disclosure / notifications) and is
// re-exported here so Firebase discovers it. Shared infrastructure (admin init,
// config/secrets, utils, audit) lives under ./shared.
//
// Requiring ./shared/admin first guarantees initializeApp() runs before any module
// touches Firestore.
require('./shared/admin');

const incidents = require('./incidents');
const sos = require('./sos');
const disclosure = require('./disclosure');
const notifications = require('./notifications');
const moderation = require('./moderation');
const claims = require('./claims');
const push = require('./push');
const share = require('./share');

// ── Incidents (public community feed) ──
exports.submit_incident = incidents.submit_incident;
exports.record_incident_signal = incidents.record_incident_signal;
exports.record_incident_concern = moderation.record_incident_concern;
exports.query_incidents_h3 = incidents.query_incidents_h3;
exports.rollupIncidentCounters = incidents.rollupIncidentCounters;

// ── SOS (activation, live location, trusted contacts) ──
exports.activate_sos = sos.activate_sos;
exports.create_app_trusted_contact_invite = sos.create_app_trusted_contact_invite;
exports.accept_app_trusted_contact_invite = sos.accept_app_trusted_contact_invite;
exports.list_app_trusted_contacts = sos.list_app_trusted_contacts;
exports.revoke_app_trusted_contact = sos.revoke_app_trusted_contact;
exports.append_sos_location = sos.append_sos_location;
exports.resolve_sos = sos.resolve_sos;
exports.get_sos_notification_status = sos.get_sos_notification_status;

// ── Disclosure (law-enforcement requests, privileged access) ──
exports.record_law_enforcement_request = disclosure.record_law_enforcement_request;
exports.review_law_enforcement_request = disclosure.review_law_enforcement_request;
exports.request_sos_session_access = disclosure.request_sos_session_access;
exports.mint_sos_role_claim = claims.mint_sos_role_claim;
exports.revoke_sos_role_claim = claims.revoke_sos_role_claim;

// ── Notifications (Twilio SMS opt-out webhook) ──
exports.twilio_sms_webhook = notifications.twilio_sms_webhook;
exports.processSosNotifications = notifications.processSosNotifications;
exports.register_push_device = push.register_push_device;
exports.onIncidentPublicWritten = push.onIncidentPublicWritten;
exports.processIncidentAlerts = push.processIncidentAlerts;
exports.incident_share_page = share.incident_share_page;

// Test-only surface, preserved for the existing test suite (test/*.test.js set
// NODE_ENV=test then read require('../src/index').__test).
if (process.env.NODE_ENV === 'test') {
  exports.__test = {
    ...incidents.__test,
    ...moderation.__test,
    ...push.__test,
    ...share.__test,
    escapeHtml: share.escapeHtml,
    buildIncidentShareHtml: share.buildIncidentShareHtml,
  };
}
