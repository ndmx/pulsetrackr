'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require('@firebase/rules-unit-testing');

let testEnv;

test.before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-pulsetrackr-rules',
    firestore: {
      rules: fs.readFileSync(path.resolve(__dirname, '../../firestore.rules'), 'utf8'),
    },
  });
});

test.after(async () => {
  await testEnv.cleanup();
});

test.beforeEach(async () => {
  await testEnv.clearFirestore();
});

test('public incident feed is readable but never client-writable', async () => {
  const db = testEnv.authenticatedContext('user-1').firestore();
  await assertSucceeds(db.doc('safety_incidents_public/incident-1').get());
  await assertFails(db.doc('safety_incidents_public/incident-1').set({ title: 'client write' }));
});

test('raw SOS/private collections deny normal client access', async () => {
  const db = testEnv.authenticatedContext('user-1').firestore();
  const privatePaths = [
    'safety_reports_private/report-1',
    'safety_incident_counter_shards_private/incident-1_confirmations_00',
    'safety_incident_counter_rollup_queue_private/incident-1',
    'safety_incident_counter_rollups_private/incident-1',
    'sos_sessions_private/session-1',
    'sos_location_updates_private/update-1',
    'sos_access_grants_private/grant-1',
    'sos_disclosure_key_releases_private/release-1',
    'sos_role_claim_grants_private/grant-1',
    'sos_access_audit_chain_heads/sos_access_v1',
  ];

  for (const path of privatePaths) {
    await assertFails(db.doc(path).get());
    await assertFails(db.doc(path).set({ probe: true }));
  }
});

test('app SOS alerts are readable only by the recipient', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await context.firestore().doc('sos_app_alerts_private/alert-1').set({
      recipientUid: 'trusted-user',
      status: 'active',
    });
  });

  await assertSucceeds(testEnv.authenticatedContext('trusted-user').firestore()
    .doc('sos_app_alerts_private/alert-1')
    .get());
  await assertFails(testEnv.authenticatedContext('other-user').firestore()
    .doc('sos_app_alerts_private/alert-1')
    .get());
  await assertFails(testEnv.authenticatedContext('trusted-user').firestore()
    .doc('sos_app_alerts_private/alert-1')
    .set({ status: 'resolved' }));
});

test('audit reads are restricted to internal admin/care-team claims', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await context.firestore().doc('sos_access_audit/audit-1').set({
      eventType: 'privileged_access_requested',
      decision: 'allowed',
    });
  });

  await assertSucceeds(testEnv.authenticatedContext('admin', { sosAdmin: true }).firestore()
    .doc('sos_access_audit/audit-1')
    .get());
  await assertSucceeds(testEnv.authenticatedContext('care', { careTeam: true }).firestore()
    .doc('sos_access_audit/audit-1')
    .get());
  await assertFails(testEnv.authenticatedContext('law', { lawEnforcement: true }).firestore()
    .doc('sos_access_audit/audit-1')
    .get());
  await assertFails(testEnv.authenticatedContext('user-1').firestore()
    .doc('sos_access_audit/audit-1')
    .get());
});

test('default deny catches unknown collections', async () => {
  const db = testEnv.authenticatedContext('user-1').firestore();
  await assertFails(db.doc('unknown_collection/doc-1').get());
  assert.ok(testEnv);
});
