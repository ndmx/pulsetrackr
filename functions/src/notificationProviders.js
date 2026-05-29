'use strict';

const TWILIO_API_BASE = 'https://api.twilio.com/2010-04-01';
const SENDGRID_API_BASE = 'https://api.sendgrid.com/v3';

function buildSOSMessage({ sessionId, contact, channel }) {
  const name = contact.displayName || 'your trusted contact';
  const shortSessionId = String(sessionId).slice(0, 8);
  const text = [
    `PulseTrackr SOS: ${name}, someone who trusts you activated SOS.`,
    `Session ${shortSessionId}.`,
    'Contact them now. Do not share their location. PulseTrackr does not call police or ambulance.',
  ].join(' ');

  if (channel === 'email') {
    return {
      subject: 'PulseTrackr SOS alert',
      text,
      html: [
        '<p><strong>PulseTrackr SOS alert</strong></p>',
        `<p>${escapeHtml(name)}, someone who trusts you activated SOS.</p>`,
        `<p>Session: <code>${escapeHtml(shortSessionId)}</code></p>`,
        '<p>Contact them now. Do not share their location.</p>',
        '<p>PulseTrackr does not automatically contact police, ambulance, or emergency services.</p>',
      ].join(''),
    };
  }

  return { text };
}

function providerReadiness(env = process.env) {
  return {
    sms: hasTwilioSms(env),
    phone_call: hasTwilioVoice(env),
    email: hasSendGrid(env),
  };
}

async function sendNotificationAttempt({
  channel,
  destination,
  contact,
  sessionId,
  fetchImpl = fetch,
  env = process.env,
}) {
  try {
    if (!destination) {
      return skipped('missing_destination');
    }

    if (channel === 'sms') {
      if (!hasTwilioSms(env)) return skipped('twilio_sms_unconfigured', 'twilio');
      return sendTwilioSms({ to: destination, message: buildSOSMessage({ sessionId, contact, channel }), fetchImpl, env });
    }

    if (channel === 'phone_call') {
      if (!hasTwilioVoice(env)) return skipped('twilio_voice_unconfigured', 'twilio');
      return sendTwilioCall({ to: destination, message: buildSOSMessage({ sessionId, contact, channel }), fetchImpl, env });
    }

    if (channel === 'email') {
      if (!hasSendGrid(env)) return skipped('sendgrid_unconfigured', 'sendgrid');
      return sendSendGridEmail({ to: destination, message: buildSOSMessage({ sessionId, contact, channel }), fetchImpl, env });
    }

    return skipped('unsupported_channel');
  } catch (error) {
    return failed(providerForChannel(channel), error.message || 'delivery_exception');
  }
}

async function sendTwilioSms({ to, message, fetchImpl, env }) {
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

async function sendTwilioCall({ to, message, fetchImpl, env }) {
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

async function twilioRequest({ path, body, fetchImpl, env }) {
  const credentials = twilioCredentials(env);
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
    return failed('twilio', json?.message || json?.error_message || `Twilio HTTP ${response.status}`);
  }

  return sent('twilio', json?.sid || null);
}

async function sendSendGridEmail({ to, message, fetchImpl, env }) {
  const response = await fetchImpl(`${SENDGRID_API_BASE}/mail/send`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${env.SENDGRID_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      personalizations: [{ to: [{ email: to }] }],
      from: {
        email: env.SENDGRID_FROM_EMAIL,
        name: env.SENDGRID_FROM_NAME || 'PulseTrackr SOS',
      },
      subject: message.subject,
      content: [
        { type: 'text/plain', value: message.text },
        { type: 'text/html', value: message.html },
      ],
    }),
  });

  if (!response.ok) {
    const json = await safeJson(response);
    const detail = Array.isArray(json?.errors) ? json.errors.map((error) => error.message).join('; ') : null;
    return failed('sendgrid', detail || `SendGrid HTTP ${response.status}`);
  }

  return sent('sendgrid', response.headers?.get?.('x-message-id') || null);
}

function hasTwilioSms(env) {
  return Boolean(env.TWILIO_ACCOUNT_SID && env.TWILIO_FROM_NUMBER && twilioCredentials(env));
}

function hasTwilioVoice(env) {
  return hasTwilioSms(env);
}

function twilioCredentials(env) {
  if (env.TWILIO_API_KEY_SID && env.TWILIO_API_KEY_SECRET) {
    return {
      username: env.TWILIO_API_KEY_SID,
      password: env.TWILIO_API_KEY_SECRET,
    };
  }

  if (env.TWILIO_AUTH_TOKEN) {
    return {
      username: env.TWILIO_ACCOUNT_SID,
      password: env.TWILIO_AUTH_TOKEN,
    };
  }

  return null;
}

function hasSendGrid(env) {
  return Boolean(env.SENDGRID_API_KEY && env.SENDGRID_FROM_EMAIL);
}

function providerForChannel(channel) {
  if (channel === 'sms' || channel === 'phone_call') return 'twilio';
  if (channel === 'email') return 'sendgrid';
  return 'unknown';
}

async function safeJson(response) {
  try {
    return await response.json();
  } catch {
    return null;
  }
}

function sent(provider, providerMessageId) {
  return {
    status: 'sent',
    provider,
    providerMessageId,
    errorMessage: null,
  };
}

function failed(provider, errorMessage) {
  return {
    status: 'failed',
    provider,
    providerMessageId: null,
    errorMessage: String(errorMessage || 'delivery_failed').slice(0, 500),
  };
}

function skipped(errorMessage, provider = 'none') {
  return {
    status: 'provider_unconfigured',
    provider,
    providerMessageId: null,
    errorMessage,
  };
}

function escapeHtml(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function escapeXml(value) {
  return escapeHtml(value);
}

module.exports = {
  buildSOSMessage,
  providerReadiness,
  sendNotificationAttempt,
};
