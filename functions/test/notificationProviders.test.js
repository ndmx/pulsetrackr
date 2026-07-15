'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const {
  buildSOSMessage,
  providerReadiness,
  sendNotificationAttempt,
} = require('../lib/notificationProviders');

const contact = {
  contactId: 'contact-1',
  displayName: 'Ada <Friend>',
  phoneNumber: '+2348012345678',
  emailAddress: 'ada@example.com',
};
const location = {
  latitude: 6.52438,
  longitude: 3.37921,
  capturedAt: new Date('2026-06-11T12:00:00Z'),
};

test('provider readiness is false until secrets are present', () => {
  assert.deepEqual(providerReadiness({}), {
    sms: false,
    phone_call: false,
    email: false,
  });

  assert.deepEqual(providerReadiness({
    TWILIO_ACCOUNT_SID: 'sid',
    TWILIO_API_KEY_SID: 'SK123',
    TWILIO_API_KEY_SECRET: 'secret',
    TWILIO_AUTH_TOKEN: 'token',
    TWILIO_FROM_NUMBER: '+15551234567',
    TWILIO_EMAIL_FROM_ADDRESS: 'sos@example.com',
  }), {
    sms: true,
    phone_call: true,
    email: true,
  });
});

test('missing provider credentials do not report a sent notification', async () => {
  const result = await sendNotificationAttempt({
    sessionId: 'session-123',
    contact,
    channel: 'sms',
    destination: contact.phoneNumber,
    env: {},
  });

  assert.equal(result.status, 'provider_unconfigured');
  assert.equal(result.provider, 'twilio');
});

test('twilio sms request is built with basic auth and form payload', async () => {
  let request;
  const result = await sendNotificationAttempt({
    sessionId: 'session-123456',
    contact,
    channel: 'sms',
    destination: contact.phoneNumber,
    env: {
      TWILIO_ACCOUNT_SID: 'AC123',
      TWILIO_API_KEY_SID: 'SK123',
      TWILIO_API_KEY_SECRET: 'secret',
      TWILIO_FROM_NUMBER: '+15551234567',
    },
    fetchImpl: async (url, options) => {
      request = { url, options };
      return jsonResponse(201, { sid: 'SM123' });
    },
  });

  assert.equal(result.status, 'sent');
  assert.equal(result.providerMessageId, 'SM123');
  assert.match(request.url, /Accounts\/AC123\/Messages\.json$/);
  assert.equal(request.options.headers.Authorization, `Basic ${Buffer.from('SK123:secret').toString('base64')}`);
  assert.equal(request.options.body.get('To'), contact.phoneNumber);
  assert.equal(request.options.body.get('From'), '+15551234567');
  assert.match(request.options.body.get('Body'), /PulseTrackr SOS/);
});

test('twilio auth token fallback still works for local migration', async () => {
  let request;
  const result = await sendNotificationAttempt({
    sessionId: 'session-123456',
    contact,
    channel: 'sms',
    destination: contact.phoneNumber,
    env: {
      TWILIO_ACCOUNT_SID: 'AC123',
      TWILIO_AUTH_TOKEN: 'token',
      TWILIO_FROM_NUMBER: '+15551234567',
    },
    fetchImpl: async (url, options) => {
      request = { url, options };
      return jsonResponse(201, { sid: 'SM124' });
    },
  });

  assert.equal(result.status, 'sent');
  assert.equal(result.providerMessageId, 'SM124');
  assert.equal(request.options.headers.Authorization, `Basic ${Buffer.from('AC123:token').toString('base64')}`);
});

test('twilio sms opt-out errors are reported separately from delivery failures', async () => {
  const result = await sendNotificationAttempt({
    sessionId: 'session-123456',
    contact,
    channel: 'sms',
    destination: contact.phoneNumber,
    env: {
      TWILIO_ACCOUNT_SID: 'AC123',
      TWILIO_API_KEY_SID: 'SK123',
      TWILIO_API_KEY_SECRET: 'secret',
      TWILIO_FROM_NUMBER: '+15551234567',
    },
    fetchImpl: async () => jsonResponse(400, {
      code: 21610,
      message: 'Message cannot be sent because the recipient replied with STOP',
    }),
  });

  assert.equal(result.status, 'recipient_opted_out');
  assert.equal(result.provider, 'twilio');
  assert.match(result.errorMessage, /STOP/);
});

test('twilio email request is built without leaking html injection', async () => {
  let request;
  const result = await sendNotificationAttempt({
    sessionId: 'session-abcdef',
    contact,
    channel: 'email',
    destination: contact.emailAddress,
    location,
    env: {
      TWILIO_ACCOUNT_SID: 'AC123',
      TWILIO_AUTH_TOKEN: 'token',
      TWILIO_EMAIL_FROM_ADDRESS: 'sos@example.com',
    },
    fetchImpl: async (url, options) => {
      request = { url, body: JSON.parse(options.body), options };
      return jsonResponse(202, { sid: 'EM123' });
    },
  });

  assert.equal(result.status, 'sent');
  assert.equal(result.provider, 'twilio');
  assert.equal(result.providerMessageId, 'EM123');
  assert.equal(request.url, 'https://comms.twilio.com/v1/Emails');
  assert.equal(request.options.headers.Authorization, `Basic ${Buffer.from('AC123:token').toString('base64')}`);
  assert.equal(request.body.from.address, 'sos@example.com');
  assert.equal(request.body.to[0].address, contact.emailAddress);
  assert.match(request.body.content.html, /Ada &lt;Friend&gt;/);
  assert.match(request.body.content.html, /unable to make a phone call/);
  assert.match(request.body.content.html, /maps\.google\.com/);
});

test('message copy explains the SOS purpose and identifies the session', () => {
  const message = buildSOSMessage({ sessionId: '1234567890', contact, channel: 'sms', location });

  assert.match(message.text, /PulseTrackr SOS/);
  assert.match(message.text, /trusted emergency contact/);
  assert.match(message.text, /unable to call/);
  assert.match(message.text, /maps\.google\.com/);
  assert.match(message.text, /12345678/);
  assert.match(message.text, /does not dispatch responders/);
  assert.match(message.text, /Reply STOP to opt out/);
  assert.ok(message.text.length < 360);
});

function jsonResponse(status, body, headers = {}) {
  return {
    ok: status >= 200 && status < 300,
    status,
    async json() {
      return body;
    },
    headers: {
      get(name) {
        return headers[name.toLowerCase()] || null;
      },
    },
  };
}
