import crypto from 'node:crypto';

type OptCommand = { action: 'opt_out' | 'opt_in' | 'help' | 'none'; keyword: string };
type TwilioBody = Record<string, string | undefined>;

export const OPT_OUT_KEYWORDS = new Set([
  'STOP',
  'STOPALL',
  'UNSUBSCRIBE',
  'CANCEL',
  'END',
  'QUIT',
  'OPTOUT',
  'REVOKE',
]);
export const OPT_IN_KEYWORDS = new Set(['START', 'YES', 'UNSTOP']);
export const HELP_KEYWORDS = new Set(['HELP', 'INFO']);

export function normalizePhoneNumberForSMS(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  if (!trimmed) return null;

  const digits = trimmed.replace(/\D/g, '');
  if (!digits) return null;

  if (trimmed.startsWith('+')) {
    return `+${digits}`;
  }
  if (digits.startsWith('00') && digits.length > 2) {
    return `+${digits.slice(2)}`;
  }
  if (digits.length === 11 && digits.startsWith('1')) {
    return `+${digits}`;
  }
  return digits;
}

export function smsOptOutDocId(phoneNumber: unknown): string | null {
  const normalized = normalizePhoneNumberForSMS(phoneNumber);
  if (!normalized) return null;
  return crypto.createHash('sha256').update(normalized).digest('hex');
}

export function parseInboundOptCommand(body: TwilioBody = {}): OptCommand {
  const keyword = firstWord(body.Body || body.body || '');
  const optOutType = firstWord(body.OptOutType || body.optOutType || '');

  if (OPT_OUT_KEYWORDS.has(keyword) || optOutType === 'STOP') {
    return { action: 'opt_out', keyword: keyword || optOutType || 'STOP' };
  }
  if (OPT_IN_KEYWORDS.has(keyword) || optOutType === 'START') {
    return { action: 'opt_in', keyword: keyword || optOutType || 'START' };
  }
  if (HELP_KEYWORDS.has(keyword) || optOutType === 'HELP') {
    return { action: 'help', keyword: keyword || optOutType || 'HELP' };
  }
  return { action: 'none', keyword };
}

export function validateTwilioSignature({ url, params = {}, signature, authToken }: {
  url?: string;
  params?: Record<string, string>;
  signature?: string;
  authToken?: string;
}): boolean {
  if (!url || !signature || !authToken) return false;

  const payload = Object.keys(params)
    .sort()
    .reduce((accumulator, key) => `${accumulator}${key}${params[key]}`, url);
  const expected = crypto
    .createHmac('sha1', authToken)
    .update(Buffer.from(payload, 'utf8'))
    .digest('base64');

  return timingSafeEqual(expected, signature);
}

function firstWord(value: unknown): string {
  return String(value || '')
    .trim()
    .split(/\s+/)[0]
    .toUpperCase();
}

function timingSafeEqual(left: string, right: string): boolean {
  const leftBuffer = Buffer.from(String(left));
  const rightBuffer = Buffer.from(String(right));
  if (leftBuffer.length !== rightBuffer.length) return false;
  return crypto.timingSafeEqual(leftBuffer, rightBuffer);
}
