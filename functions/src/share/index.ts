import { onRequest } from 'firebase-functions/v2/https';
import { db } from '../shared/admin';
import { callableOptions } from '../shared/config';

const INCIDENT_ID_PATTERN = /^[A-Za-z0-9_-]{1,128}$/;
const NOT_FOUND_HTML = '<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Incident unavailable - PulseTrackr</title><style>body{margin:0;min-height:100vh;display:grid;place-items:center;background:#090b10;color:#f5f7fb;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}main{max-width:36rem;padding:2rem}p{color:#bac3d4;line-height:1.5}</style></head><body><main><h1>Incident unavailable</h1><p>This incident link is no longer available or could not be found.</p></main></body></html>';

type IncidentShareResponse = {
  body: string;
  cacheControl: string;
  status: 200 | 404;
};

type EvidenceSummary = {
  photo_count?: unknown;
  voice_count?: unknown;
};

type PublicIncidentShareFields = {
  title?: unknown;
  summary?: unknown;
  category?: unknown;
  subtype?: unknown;
  severity?: unknown;
  status?: unknown;
  neighborhood?: unknown;
  reported_at?: unknown;
  confirmations?: unknown;
  disputes?: unknown;
  official_updates?: unknown;
  evidence_summary?: EvidenceSummary;
  deleteAfter?: unknown;
};

export function escapeHtml(value: unknown): string {
  return String(value ?? '').replace(/[&<>"']/g, (character) => {
    switch (character) {
      case '&':
        return '&amp;';
      case '<':
        return '&lt;';
      case '>':
        return '&gt;';
      case '"':
        return '&quot;';
      case '\'':
        return '&#39;';
      default:
        return character;
    }
  });
}

export function isValidIncidentId(value: unknown): value is string {
  return typeof value === 'string' && INCIDENT_ID_PATTERN.test(value);
}

export function incidentIdFromRequestPath(path: string, queryId: unknown): string | null {
  const pathId = path.startsWith('/i/') ? path.slice('/i/'.length) : '';
  const candidate = pathId || (typeof queryId === 'string' ? queryId : '');
  return isValidIncidentId(candidate) ? candidate : null;
}

export function buildIncidentShareHtml(incident: PublicIncidentShareFields, id: string): string {
  const title = cleanText(incident.title, 'PulseTrackr incident', 120);
  const summary = cleanText(incident.summary, 'A PulseTrackr community safety incident.', 800);
  const description = truncateText(summary, 160);
  const category = labelFor(cleanText(incident.category, 'Incident', 80));
  const subtype = labelFor(cleanText(incident.subtype, '', 80));
  const severity = labelFor(cleanText(incident.severity, 'Unknown', 40));
  const status = labelFor(cleanText(incident.status, 'Active', 40));
  const neighborhood = cleanText(incident.neighborhood, 'Nearby area', 140);
  const reportedAt = formatUtcDate(timestampToDate(incident.reported_at));
  const confirmations = nonNegativeInteger(incident.confirmations);
  const disputes = nonNegativeInteger(incident.disputes);
  const officialUpdates = nonNegativeInteger(incident.official_updates);
  const photoCount = nonNegativeInteger(incident.evidence_summary?.photo_count);
  const voiceCount = nonNegativeInteger(incident.evidence_summary?.voice_count);
  const evidenceParts = [
    photoCount > 0 ? `${photoCount} ${photoCount === 1 ? 'photo' : 'photos'}` : '',
    voiceCount > 0 ? `${voiceCount} ${voiceCount === 1 ? 'voice clip' : 'voice clips'}` : '',
  ].filter(Boolean);
  const safeId = escapeHtml(id);
  const escapedTitle = escapeHtml(title);
  const escapedDescription = escapeHtml(description);

  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>${escapedTitle} &mdash; PulseTrackr</title>
  <meta name="description" content="${escapedDescription}">
  <meta property="og:title" content="${escapedTitle}">
  <meta property="og:description" content="${escapedDescription}">
  <meta property="og:type" content="article">
  <meta property="og:site_name" content="PulseTrackr">
  <meta name="twitter:card" content="summary">
  <meta name="twitter:title" content="${escapedTitle}">
  <meta name="twitter:description" content="${escapedDescription}">
  <style>
    :root{color-scheme:dark;background:#080a0f;color:#f7f8fb}
    *{box-sizing:border-box}
    body{margin:0;min-height:100vh;background:linear-gradient(180deg,#111827 0%,#080a0f 58%);font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Arial,sans-serif;color:#f7f8fb}
    main{width:min(42rem,100%);margin:0 auto;padding:3rem 1.25rem}
    .chip{display:inline-flex;align-items:center;border:1px solid #324055;background:#172033;color:#d8e2f3;border-radius:999px;padding:.38rem .72rem;font-size:.82rem;font-weight:700}
    h1{margin:1rem 0 .75rem;font-size:clamp(2rem,8vw,3.25rem);line-height:1.02;letter-spacing:0}
    p{line-height:1.58}
    .meta,.counts,.evidence{color:#bac3d4}
    .summary{font-size:1.08rem;color:#eef2f8}
    .official{border-left:3px solid #49d17d;padding-left:.8rem;color:#d9ffe6;font-weight:700}
    .actions{display:flex;flex-wrap:wrap;gap:.75rem;margin-top:2rem}
    a{display:inline-flex;align-items:center;justify-content:center;min-height:2.75rem;padding:0 1rem;border-radius:.45rem;text-decoration:none;font-weight:800}
    .primary{background:#f7f8fb;color:#080a0f}
    .secondary{border:1px solid #3a465a;color:#f7f8fb}
  </style>
</head>
<body>
  <main>
    <span class="chip">${escapeHtml(category)}${subtype ? ` / ${escapeHtml(subtype)}` : ''}</span>
    <h1>${escapedTitle}</h1>
    <p class="meta">${escapeHtml(severity)} severity &middot; ${escapeHtml(status)}</p>
    <p class="meta">${escapeHtml(neighborhood)} &middot; ${escapeHtml(reportedAt)}</p>
    <p class="summary">${escapeHtml(summary)}</p>
    <p class="counts">${confirmations} confirmations &middot; ${disputes} disputes</p>
    ${evidenceParts.length > 0 ? `<p class="evidence">Evidence: ${escapeHtml(evidenceParts.join(' / '))}</p>` : ''}
    ${officialUpdates > 0 ? '<p class="official">Official update</p>' : ''}
    <nav class="actions" aria-label="Incident actions">
      <a class="primary" href="pulsetrackr://incident/${safeId}">Open in PulseTrackr</a>
      <a class="secondary" href="https://apps.apple.com/">Get the app</a>
    </nav>
  </main>
</body>
</html>`;
}

export function buildIncidentShareResponse(
  incident: PublicIncidentShareFields | null,
  id: string,
  now: Date = new Date(),
): IncidentShareResponse {
  if (!incident || isExpired(incident.deleteAfter, now)) {
    return {
      body: NOT_FOUND_HTML,
      cacheControl: 'no-store',
      status: 404,
    };
  }

  return {
    body: buildIncidentShareHtml(incident, id),
    cacheControl: 'public, max-age=300, s-maxage=300',
    status: 200,
  };
}

async function incidentShareHandler(req: any, res: any): Promise<void> {
  const id = incidentIdFromRequestPath(String(req.path || ''), req.query?.id);
  if (!id) {
    sendShareResponse(res, buildIncidentShareResponse(null, ''));
    return;
  }

  const snapshot = await db.collection('safety_incidents_public').doc(id).get();
  const response = buildIncidentShareResponse(snapshot.exists ? snapshot.data() as PublicIncidentShareFields : null, id);
  sendShareResponse(res, response);
}

function sendShareResponse(res: any, response: IncidentShareResponse): void {
  res.status(response.status)
    .set('Cache-Control', response.cacheControl)
    .set('Content-Type', 'text/html; charset=utf-8')
    .send(response.body);
}

function isExpired(deleteAfter: unknown, now: Date): boolean {
  const date = timestampToDate(deleteAfter);
  return Boolean(date && date.getTime() <= now.getTime());
}

function timestampToDate(value: unknown): Date | null {
  if (!value) return null;
  if (value instanceof Date) return Number.isNaN(value.getTime()) ? null : value;
  if (typeof (value as { toDate?: unknown }).toDate === 'function') {
    const date = (value as { toDate: () => Date }).toDate();
    return Number.isNaN(date.getTime()) ? null : date;
  }
  if (typeof value === 'string') {
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? null : date;
  }
  return null;
}

function cleanText(value: unknown, fallback: string, maxLength: number): string {
  const text = typeof value === 'string' ? value.trim() : '';
  return truncateText(text || fallback, maxLength);
}

function truncateText(value: string, maxLength: number): string {
  const characters = Array.from(value);
  if (characters.length <= maxLength) {
    return value;
  }
  const suffix = maxLength > 3 ? '...' : '';
  return `${characters.slice(0, Math.max(0, maxLength - suffix.length)).join('').trimEnd()}${suffix}`;
}

function nonNegativeInteger(value: unknown): number {
  const number = Number(value);
  return Number.isFinite(number) && number > 0 ? Math.floor(number) : 0;
}

function labelFor(value: string): string {
  return value
    .replace(/[_-]+/g, ' ')
    .replace(/([a-z])([A-Z])/g, '$1 $2')
    .trim()
    .replace(/\w\S*/g, (word) => word.charAt(0).toUpperCase() + word.slice(1).toLowerCase());
}

function formatUtcDate(date: Date | null): string {
  if (!date) {
    return 'Time not available';
  }
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const hours = String(date.getUTCHours()).padStart(2, '0');
  const minutes = String(date.getUTCMinutes()).padStart(2, '0');
  return `${months[date.getUTCMonth()]} ${date.getUTCDate()}, ${date.getUTCFullYear()}, ${hours}:${minutes} UTC`;
}

export const incident_share_page = onRequest({
  region: callableOptions.region,
  maxInstances: callableOptions.maxInstances,
}, incidentShareHandler);

export const __test = {
  buildIncidentShareResponse,
  incidentIdFromRequestPath,
  isValidIncidentId,
};
