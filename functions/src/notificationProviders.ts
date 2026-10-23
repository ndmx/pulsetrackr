import { getMessaging, type Message } from 'firebase-admin/messaging';

type NotificationResult = {
  status: 'sent' | 'failed' | 'provider_unconfigured';
  provider: string;
  providerMessageId: string | null;
  errorMessage: string | null;
};

// This remains callable by old queue paths, but never sends SMS, calls or email.
export async function sendNotificationAttempt({ channel, destination, title, body, data }: any): Promise<NotificationResult> {
  if (channel !== 'app_push') {
    return { status: 'provider_unconfigured', provider: 'none', providerMessageId: null, errorMessage: 'in_app_only' };
  }
  if (!destination) {
    return { status: 'provider_unconfigured', provider: 'none', providerMessageId: null, errorMessage: 'missing_destination' };
  }
  try {
    return await sendFcmPush({ token: destination, title, body, data });
  } catch (error: any) {
    return { status: 'failed', provider: 'fcm', providerMessageId: null, errorMessage: String(error?.message || error).slice(0, 500) };
  }
}

export async function sendFcmPush({ token, title, body, data }: any): Promise<NotificationResult> {
  const message = withoutUndefined({
    token,
    notification: {
      title: cleanPushText(title, 120) || 'PulseTrackr alert',
      body: cleanPushText(body, 500) || '',
    },
    data: cleanPushData(data),
  }) as unknown as Message;
  const messageId = await getMessaging().send(message);
  return { status: 'sent', provider: 'fcm', providerMessageId: messageId || null, errorMessage: null };
}

function cleanPushText(value: unknown, maxLength: number): string {
  return typeof value === 'string' ? value.trim().slice(0, maxLength) : '';
}

function cleanPushData(value: unknown): Record<string, string> | undefined {
  if (!value || typeof value !== 'object') return undefined;
  const entries = Object.entries(value as Record<string, unknown>)
    .map(([key, entryValue]) => [cleanPushText(key, 128), cleanPushText(entryValue, 1024)])
    .filter(([key]) => key);
  return entries.length ? Object.fromEntries(entries) : undefined;
}

function withoutUndefined(object: Record<string, unknown>): Record<string, unknown> {
  return Object.fromEntries(Object.entries(object).filter(([, value]) => value !== undefined));
}
