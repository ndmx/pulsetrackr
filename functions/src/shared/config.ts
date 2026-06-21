// Function deployment options + Twilio secrets. The secret objects are defined once
// here and shared by both the function options (which bind them) and the notification
// code (which reads their values), so the same instances flow through everywhere.

import { defineSecret } from 'firebase-functions/params';

export const twilioAccountSid = defineSecret('TWILIO_ACCOUNT_SID');
export const twilioApiKeySid = defineSecret('TWILIO_API_KEY_SID');
export const twilioApiKeySecret = defineSecret('TWILIO_API_KEY_SECRET');
export const twilioFromNumber = defineSecret('TWILIO_FROM_NUMBER');
export const twilioEmailFromAddress = defineSecret('TWILIO_EMAIL_FROM_ADDRESS');
export const twilioAuthToken = defineSecret('TWILIO_AUTH_TOKEN');
export const sosEnvelopeKek = defineSecret('SOS_ENVELOPE_KEK');

export const callableOptions = {
  region: process.env.PULSETRACKR_FUNCTION_REGION || 'us-central1',
  enforceAppCheck: process.env.FUNCTIONS_EMULATOR !== 'true',
  maxInstances: 20,
  secrets: [
    twilioAccountSid,
    twilioApiKeySid,
    twilioApiKeySecret,
    twilioFromNumber,
    twilioEmailFromAddress,
    sosEnvelopeKek,
  ],
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
  secrets: [
    twilioAccountSid,
    twilioApiKeySid,
    twilioApiKeySecret,
    twilioFromNumber,
    twilioEmailFromAddress,
    sosEnvelopeKek,
  ],
};

export function secretValue(secret: { value: () => string }): string | null {
  try {
    return secret.value();
  } catch {
    return null;
  }
}
