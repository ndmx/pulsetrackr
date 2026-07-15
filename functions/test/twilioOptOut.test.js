'use strict';

const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const test = require('node:test');
const {
  normalizePhoneNumberForSMS,
  parseInboundOptCommand,
  smsOptOutDocId,
  validateTwilioSignature,
} = require('../lib/twilioOptOut');

test('parses Twilio opt-out and opt-in commands', () => {
  assert.deepEqual(parseInboundOptCommand({ Body: 'STOP please' }), {
    action: 'opt_out',
    keyword: 'STOP',
  });
  assert.deepEqual(parseInboundOptCommand({ Body: 'cancel' }), {
    action: 'opt_out',
    keyword: 'CANCEL',
  });
  assert.deepEqual(parseInboundOptCommand({ OptOutType: 'STOP' }), {
    action: 'opt_out',
    keyword: 'STOP',
  });
  assert.deepEqual(parseInboundOptCommand({ Body: 'START' }), {
    action: 'opt_in',
    keyword: 'START',
  });
  assert.deepEqual(parseInboundOptCommand({ Body: 'hello' }), {
    action: 'none',
    keyword: 'HELLO',
  });
});

test('normalizes phone numbers before hashing opt-out records', () => {
  assert.equal(normalizePhoneNumberForSMS('+1 (555) 123-4567'), '+15551234567');
  assert.equal(normalizePhoneNumberForSMS('0015551234567'), '+15551234567');
  assert.equal(normalizePhoneNumberForSMS('555-123-4567'), '5551234567');
  assert.equal(smsOptOutDocId('+1 (555) 123-4567'), smsOptOutDocId('+15551234567'));
});

test('validates Twilio request signatures', () => {
  const url = 'https://us-central1-demo.cloudfunctions.net/twilio_sms_webhook';
  const params = {
    Body: 'STOP',
    From: '+15551234567',
    To: '+15557654321',
  };
  const authToken = 'auth-token';
  const signature = signTwilioPayload(url, params, authToken);

  assert.equal(validateTwilioSignature({ url, params, signature, authToken }), true);
  assert.equal(validateTwilioSignature({ url, params, signature: 'bad', authToken }), false);
  assert.equal(validateTwilioSignature({ url: `${url}?changed=1`, params, signature, authToken }), false);
});

function signTwilioPayload(url, params, authToken) {
  const payload = Object.keys(params)
    .sort()
    .reduce((accumulator, key) => `${accumulator}${key}${params[key]}`, url);
  return crypto
    .createHmac('sha1', authToken)
    .update(Buffer.from(payload, 'utf8'))
    .digest('base64');
}
