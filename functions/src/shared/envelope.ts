import crypto from 'node:crypto';
import { secretValue, sosEnvelopeKek } from './config';

const ENVELOPE_VERSION = 1;
const CIPHER = 'aes-256-gcm';

type EncryptedEnvelope = {
  version: number;
  algorithm: string;
  keyWrapAlgorithm: string;
  keyVersion: string;
  aadHash: string;
  wrappedKey: CipherBlob;
  payload: CipherBlob;
};

type CipherBlob = {
  iv: string;
  ciphertext: string;
  tag: string;
};

export function encryptPrivateJson(value: unknown, aad: Record<string, unknown>): EncryptedEnvelope {
  const dataKey = crypto.randomBytes(32);
  const kek = envelopeKek();
  return {
    version: ENVELOPE_VERSION,
    algorithm: CIPHER,
    keyWrapAlgorithm: CIPHER,
    keyVersion: process.env.SOS_ENVELOPE_KEY_VERSION || 'v1',
    aadHash: aadHash(aad),
    wrappedKey: encryptBuffer(dataKey, kek, aadBuffer({ ...aad, purpose: 'wrap_data_key' })),
    payload: encryptBuffer(Buffer.from(JSON.stringify(value)), dataKey, aadBuffer(aad)),
  };
}

export function decryptPrivateJson(envelope: EncryptedEnvelope | null | undefined, aad: Record<string, unknown>): any {
  if (!envelope) return null;
  if (envelope.version !== ENVELOPE_VERSION || envelope.algorithm !== CIPHER) {
    throw new Error('Unsupported encrypted private payload version');
  }
  const expectedHash = aadHash(aad);
  if (envelope.aadHash !== expectedHash) {
    throw new Error('Encrypted private payload context mismatch');
  }
  const kek = envelopeKek();
  const dataKey = decryptBuffer(envelope.wrappedKey, kek, aadBuffer({ ...aad, purpose: 'wrap_data_key' }));
  const plaintext = decryptBuffer(envelope.payload, dataKey, aadBuffer(aad));
  return JSON.parse(plaintext.toString('utf8'));
}

export function privateLocationJson(location: any) {
  if (!location) return null;
  const capturedAt = location.capturedAt instanceof Date
    ? location.capturedAt.toISOString()
    : (typeof location.capturedAt?.toDate === 'function' ? location.capturedAt.toDate().toISOString() : location.capturedAt);
  return {
    latitude: location.latitude,
    longitude: location.longitude,
    horizontalAccuracyMeters: location.horizontalAccuracyMeters,
    altitudeMeters: location.altitudeMeters,
    speedMetersPerSecond: location.speedMetersPerSecond,
    courseDegrees: location.courseDegrees,
    capturedAt,
  };
}

function encryptBuffer(plaintext: Buffer, key: Buffer, aad: Buffer): CipherBlob {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv(CIPHER, key, iv);
  cipher.setAAD(aad);
  const ciphertext = Buffer.concat([cipher.update(plaintext), cipher.final()]);
  return {
    iv: iv.toString('base64'),
    ciphertext: ciphertext.toString('base64'),
    tag: cipher.getAuthTag().toString('base64'),
  };
}

function decryptBuffer(blob: CipherBlob, key: Buffer, aad: Buffer): Buffer {
  const decipher = crypto.createDecipheriv(CIPHER, key, Buffer.from(blob.iv, 'base64'));
  decipher.setAAD(aad);
  decipher.setAuthTag(Buffer.from(blob.tag, 'base64'));
  return Buffer.concat([
    decipher.update(Buffer.from(blob.ciphertext, 'base64')),
    decipher.final(),
  ]);
}

function aadBuffer(aad: Record<string, unknown>): Buffer {
  return Buffer.from(canonicalJson(aad));
}

function aadHash(aad: Record<string, unknown>): string {
  return crypto.createHash('sha256').update(aadBuffer(aad)).digest('hex');
}

function envelopeKek(): Buffer {
  const raw = secretValue(sosEnvelopeKek) || process.env.SOS_ENVELOPE_KEK || process.env.PULSETRACKR_LOCAL_ENVELOPE_KEK;
  if (!raw) {
    throw new Error('SOS_ENVELOPE_KEK is required to encrypt or decrypt private SOS location data');
  }
  const key = Buffer.from(raw, raw.length === 64 ? 'hex' : 'base64');
  if (key.length !== 32) {
    throw new Error('SOS_ENVELOPE_KEK must decode to 32 bytes');
  }
  return key;
}

function canonicalJson(value: any): string {
  if (value === null || typeof value !== 'object') {
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) {
    return `[${value.map(canonicalJson).join(',')}]`;
  }
  return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`).join(',')}}`;
}
