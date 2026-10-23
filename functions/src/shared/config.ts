// The legacy Twilio webhook remains available to record replies to old messages.
// SOS delivery functions bind only the location encryption secret.

import { defineSecret } from 'firebase-functions/params';

export const twilioAuthToken = defineSecret('TWILIO_AUTH_TOKEN');
export const sosEnvelopeKek = defineSecret('SOS_ENVELOPE_KEK');

export const callableOptions = {
  region: process.env.PULSETRACKR_FUNCTION_REGION || 'us-central1',
  enforceAppCheck: process.env.FUNCTIONS_EMULATOR !== 'true',
  maxInstances: 20,
  secrets: [sosEnvelopeKek],
};

export const webhookOptions = {
  region: process.env.PULSETRACKR_FUNCTION_REGION || 'us-central1',
  maxInstances: 10,
  secrets: [twilioAuthToken],
};

export const taskQueueOptions = {
  region: process.env.PULSETRACKR_FUNCTION_REGION || 'us-central1',
  maxInstances: 10,
  retryConfig: {
    maxAttempts: 5,
    minBackoffSeconds: 30,
    maxBackoffSeconds: 300,
    maxDoublings: 4,
  },
  rateLimits: {
    maxConcurrentDispatches: 10,
    maxDispatchesPerSecond: 5,
  },
  secrets: [sosEnvelopeKek],
};

export function secretValue(secret: { value: () => string }): string | null {
  try {
    return secret.value();
  } catch {
    return null;
  }
}
