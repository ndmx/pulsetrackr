const TWILIO_API_BASE = 'https://api.twilio.com/2010-04-01';
const TWILIO_EMAIL_API_URL = 'https://comms.twilio.com/v1/Emails';

type Env = Record<string, string | undefined>;
type NotificationResult = {
  status: 'sent' | 'failed' | 'recipient_opted_out' | 'provider_unconfigured';
  provider: string;
  providerMessageId: string | null;
  errorMessage: string | null;
};

export function buildSOSMessage({ sessionId, contact, channel, location }: any) {
  const name = contact.displayName || 'your trusted contact';
  const shortSessionId = String(sessionId).slice(0, 8);
  const locationContext = buildLocationContext(location);
  const locationText = locationContext
    ? ` Last phone location: ${locationContext.label} ${locationContext.mapUrl}.`
    : '';
  const text = [
    'PulseTrackr SOS: You were selected as a trusted emergency contact.',
    `The user may be in distress or unable to call.${locationText}`,
    `Session ${shortSessionId}.`,
    channel === 'sms'
      ? 'Contact them or local help. PulseTrackr does not dispatch responders. Reply STOP to opt out.'
      : 'Contact them or local help. PulseTrackr does not dispatch responders.',
  ].join(' ');

  if (channel === 'email') {
    return {
      subject: 'PulseTrackr SOS trusted-contact alert',
      text,
      html: [
        '<p><strong>PulseTrackr SOS alert</strong></p>',
        `<p>${escapeHtml(name)}, you were selected as a trusted emergency contact.</p>`,
        '<p>The user activated SOS and may be in distress or unable to make a phone call.</p>',
        locationContext
          ? `<p><strong>Last phone location:</strong> ${escapeHtml(locationContext.label)}<br><a href="${escapeHtml(locationContext.mapUrl)}">${escapeHtml(locationContext.mapUrl)}</a></p>`
          : '<p>No phone location was attached to this alert.</p>',
        `<p>Session: <code>${escapeHtml(shortSessionId)}</code></p>`,
        '<p>Use this alert to contact them, check on them, or share the location with local emergency help if needed.</p>',
        '<p>PulseTrackr notifies trusted contacts only. It does not dispatch police, ambulance, or emergency responders.</p>',
      ].join(''),
    };
  }

  return { text };
}

export function providerReadiness(env: Env = process.env) {
  return {
    sms: hasTwilioSms(env),
    phone_call: hasTwilioVoice(env),
    email: hasTwilioEmail(env),
  };
}

export async function sendNotificationAttempt({
  channel,
  destination,
  contact,
  sessionId,
  location,
  fetchImpl = fetch,
  env = process.env,
}: any): Promise<NotificationResult> {
  try {
    if (!destination) {
      return skipped('missing_destination');
    }

    if (channel === 'sms') {
      if (!hasTwilioSms(env)) return skipped('twilio_sms_unconfigured', 'twilio');
      return sendTwilioSms({ to: destination, message: buildSOSMessage({ sessionId, contact, channel, location }), fetchImpl, env });
    }

    if (channel === 'phone_call') {
      if (!hasTwilioVoice(env)) return skipped('twilio_voice_unconfigured', 'twilio');
      return sendTwilioCall({ to: destination, message: buildSOSMessage({ sessionId, contact, channel, location }), fetchImpl, env });
    }

    if (channel === 'email') {
      if (!hasTwilioEmail(env)) return skipped('twilio_email_unconfigured', 'twilio');
      return sendTwilioEmail({ to: destination, message: buildSOSMessage({ sessionId, contact, channel, location }), fetchImpl, env });
    }

    return skipped('unsupported_channel');
  } catch (error: any) {
    return failed(providerForChannel(channel), error.message || 'delivery_exception');
  }
}

async function sendTwilioSms({ to, message, fetchImpl, env }: any): Promise<NotificationResult> {
  const response = await twilioRequest({
    path: `/Accounts/${encodeURIComponent(env.TWILIO_ACCOUNT_SID)}/Messages.json`,
    body: {
      To: to,
      From: env.TWILIO_FROM_NUMBER,
      Body: message.text,
    },
    fetchImpl,
    env,
  });
  return response;
}

async function sendTwilioCall({ to, message, fetchImpl, env }: any): Promise<NotificationResult> {
  const twiml = env.TWILIO_VOICE_TWIML
    || `<Response><Say>${escapeXml(message.text)}</Say></Response>`;
  return twilioRequest({
    path: `/Accounts/${encodeURIComponent(env.TWILIO_ACCOUNT_SID)}/Calls.json`,
    body: {
      To: to,
      From: env.TWILIO_FROM_NUMBER,
      Twiml: twiml,
    },
    fetchImpl,
    env,
  });
}

async function twilioRequest({ path, body, fetchImpl, env }: any): Promise<NotificationResult> {
  const credentials = twilioCredentials(env)!;
  const auth = Buffer.from(`${credentials.username}:${credentials.password}`).toString('base64');
  const response = await fetchImpl(`${TWILIO_API_BASE}${path}`, {
    method: 'POST',
    headers: {
      Authorization: `Basic ${auth}`,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: new URLSearchParams(body),
  });

  const json = await safeJson(response);
  if (!response.ok) {
    if (isTwilioOptOutError(json)) {
      return optedOut('twilio', json?.message || json?.error_message || `Twilio HTTP ${response.status}`);
    }
    return failed('twilio', json?.message || json?.error_message || `Twilio HTTP ${response.status}`);
  }

  return sent('twilio', json?.sid || null);
}

async function sendTwilioEmail({ to, message, fetchImpl, env }: any): Promise<NotificationResult> {
  const credentials = twilioCredentials(env)!;
  const auth = Buffer.from(`${credentials.username}:${credentials.password}`).toString('base64');
  const response = await fetchImpl(TWILIO_EMAIL_API_URL, {
    method: 'POST',
    headers: {
      Authorization: `Basic ${auth}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from: {
        address: twilioEmailFromAddress(env),
        name: env.TWILIO_EMAIL_FROM_NAME || 'PulseTrackr SOS',
      },
      to: [{ address: to }],
      content: {
        subject: message.subject,
        html: message.html,
        text: message.text,
      },
    }),
  });

  const json = await safeJson(response);
  if (!response.ok) {
    const detail = Array.isArray(json?.errors)
      ? json.errors.map((error: any) => error.message).join('; ')
      : json?.message || json?.error_message || null;
    return failed('twilio', detail || `Twilio Email HTTP ${response.status}`);
  }

  return sent('twilio', json?.sid || json?.id || response.headers?.get?.('x-twilio-request-id') || null);
}

function hasTwilioSms(env: Env): boolean {
  return Boolean(env.TWILIO_ACCOUNT_SID && env.TWILIO_FROM_NUMBER && twilioCredentials(env));
}

function hasTwilioVoice(env: Env): boolean {
  return hasTwilioSms(env);
}

function twilioCredentials(env: Env): { username: string; password: string } | null {
  if (env.TWILIO_API_KEY_SID && env.TWILIO_API_KEY_SECRET) {
    return {
      username: env.TWILIO_API_KEY_SID,
      password: env.TWILIO_API_KEY_SECRET,
    };
  }

  if (env.TWILIO_AUTH_TOKEN) {
    return {
      username: env.TWILIO_ACCOUNT_SID as string,
      password: env.TWILIO_AUTH_TOKEN,
    };
  }

  return null;
}

function twilioEmailFromAddress(env: Env): string {
  return env.TWILIO_EMAIL_FROM_ADDRESS || '';
}

function hasTwilioEmail(env: Env): boolean {
  return Boolean(twilioCredentials(env) && twilioEmailFromAddress(env));
}

function buildLocationContext(location: any): { label: string; mapUrl: string } | null {
  if (!location) return null;
  const latitude = Number(location.latitude);
  const longitude = Number(location.longitude);
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) return null;

  const label = `${latitude.toFixed(5)}, ${longitude.toFixed(5)}`;
  const mapUrl = `https://maps.google.com/?q=${encodeURIComponent(`${latitude.toFixed(5)},${longitude.toFixed(5)}`)}`;
  return { label, mapUrl };
}

function providerForChannel(channel: string): string {
  if (channel === 'sms' || channel === 'phone_call' || channel === 'email') return 'twilio';
  return 'unknown';
}

async function safeJson(response: any): Promise<any> {
  try {
    return await response.json();
  } catch {
    return null;
  }
}

function sent(provider: string, providerMessageId: string | null): NotificationResult {
  return {
    status: 'sent',
    provider,
    providerMessageId,
    errorMessage: null,
  };
}

function failed(provider: string, errorMessage: unknown): NotificationResult {
  return {
    status: 'failed',
    provider,
    providerMessageId: null,
    errorMessage: String(errorMessage || 'delivery_failed').slice(0, 500),
  };
}

function optedOut(provider: string, errorMessage: unknown): NotificationResult {
  return {
    status: 'recipient_opted_out',
    provider,
    providerMessageId: null,
    errorMessage: String(errorMessage || 'recipient_opted_out').slice(0, 500),
  };
}

function skipped(errorMessage: string, provider = 'none'): NotificationResult {
  return {
    status: 'provider_unconfigured',
    provider,
    providerMessageId: null,
    errorMessage,
  };
}

function escapeHtml(value: unknown): string {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function escapeXml(value: unknown): string {
  return escapeHtml(value);
}

function isTwilioOptOutError(json: any): boolean {
  const code = Number(json?.code);
  if (code === 21610 || code === 30630) return true;
  const message = String(json?.message || json?.error_message || '').toLowerCase();
  return message.includes('opted out') || message.includes('unsubscribed');
}
