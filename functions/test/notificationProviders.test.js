'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const { sendNotificationAttempt } = require('../lib/notificationProviders');
const { enqueueTrustedContactNotifications } = require('../lib/notifications');

test('legacy SMS, call, and email attempts cannot use external providers', async () => {
  for (const channel of ['sms', 'phone_call', 'email']) {
    let externalRequests = 0;
    const result = await sendNotificationAttempt({
      channel,
      destination: channel === 'email' ? 'ada@example.com' : '+15551234567',
      env: {
        TWILIO_ACCOUNT_SID: 'AC123',
        TWILIO_AUTH_TOKEN: 'secret',
        TWILIO_FROM_NUMBER: '+15557654321',
        TWILIO_EMAIL_FROM_ADDRESS: 'sos@example.com',
      },
      fetchImpl: async () => { externalRequests += 1; throw new Error('unexpected request'); },
    });
    assert.equal(result.status, 'provider_unconfigured');
    assert.equal(result.errorMessage, 'in_app_only');
    assert.equal(externalRequests, 0);
  }
});

test('app push requires a device token', async () => {
  const result = await sendNotificationAttempt({ channel: 'app_push', destination: '' });
  assert.equal(result.status, 'provider_unconfigured');
  assert.equal(result.errorMessage, 'missing_destination');
});

test('a queued legacy phone task produces no outbound attempt', async () => {
  const result = await enqueueTrustedContactNotifications({
    sessionId: 'old-session',
    ownerUid: 'owner-1',
    contacts: [{ channels: ['sms', 'phone_call', 'email'], phoneNumber: '+15551234567' }],
  });
  assert.equal(result.notificationSummary.sent, 0);
  assert.equal(result.notificationSummary.queued, 0);
  assert.deepEqual(result.trustedContactsNotified, []);
});
