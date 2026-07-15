'use strict';

// Adversarial coverage for the envelope-encryption primitive: tampering with the
// ciphertext, the wrapped key, or the auth tag must fail (AES-256-GCM integrity),
// the wrong KEK must fail, and a non-32-byte KEK must refuse to operate.
// The KEK is read at call time, so tests vary it via process.env per case.

process.env.NODE_ENV = 'test';
process.env.SOS_ENVELOPE_KEK = Buffer.alloc(32, 7).toString('base64');

const assert = require('node:assert/strict');
const test = require('node:test');
const { encryptPrivateJson, decryptPrivateJson } = require('../lib/shared/envelope');

const AAD = {
  domain: 'pulsetrackr.sos.location',
  sessionId: 'session-9',
  ownerUid: 'owner-9',
  field: 'lastKnownLocation',
};
const LOCATION = { latitude: 6.52, longitude: 3.37, capturedAt: '2026-06-21T12:00:00.000Z' };
const PRIMARY_KEK = Buffer.alloc(32, 7).toString('base64');

function withKek(kek, fn) {
  const saved = process.env.SOS_ENVELOPE_KEK;
  process.env.SOS_ENVELOPE_KEK = kek;
  try {
    return fn();
  } finally {
    process.env.SOS_ENVELOPE_KEK = saved;
  }
}

function flipFirstByte(base64) {
  const buf = Buffer.from(base64, 'base64');
  buf[0] ^= 0xff;
  return buf.toString('base64');
}

test('tampered ciphertext is rejected', () => {
  const env = encryptPrivateJson(LOCATION, AAD);
  env.payload.ciphertext = flipFirstByte(env.payload.ciphertext);
  assert.throws(() => decryptPrivateJson(env, AAD));
});

test('tampered auth tag is rejected', () => {
  const env = encryptPrivateJson(LOCATION, AAD);
  env.payload.tag = flipFirstByte(env.payload.tag);
  assert.throws(() => decryptPrivateJson(env, AAD));
});

test('tampered wrapped data key is rejected', () => {
  const env = encryptPrivateJson(LOCATION, AAD);
  env.wrappedKey.ciphertext = flipFirstByte(env.wrappedKey.ciphertext);
  assert.throws(() => decryptPrivateJson(env, AAD));
});

test('decrypting under a different KEK fails', () => {
  const env = withKek(PRIMARY_KEK, () => encryptPrivateJson(LOCATION, AAD));
  withKek(Buffer.alloc(32, 9).toString('base64'), () => {
    assert.throws(() => decryptPrivateJson(env, AAD));
  });
});

test('a 32-byte key is required', () => {
  withKek(Buffer.alloc(16, 7).toString('base64'), () => {
    assert.throws(() => encryptPrivateJson(LOCATION, AAD), /32 bytes/);
  });
});
