'use strict';

process.env.NODE_ENV = 'test';

const assert = require('node:assert/strict');
const test = require('node:test');
const { Timestamp } = require('firebase-admin/firestore');
const { __test } = require('../lib/index');

const {
  buildIncidentShareHtml,
  buildIncidentShareResponse,
  escapeHtml,
  incidentIdFromRequestPath,
} = __test;

test('escapeHtml escapes script, quote, angle, and ampersand payloads', () => {
  const cases = [
    ['<script>alert(1)</script>', '&lt;script&gt;alert(1)&lt;/script&gt;'],
    ['"quoted" and \'single\'', '&quot;quoted&quot; and &#39;single&#39;'],
    ['AT&T & Sons', 'AT&amp;T &amp; Sons'],
    ['unicode stays: Lagos \u{1F6A6}', 'unicode stays: Lagos \u{1F6A6}'],
  ];

  for (const [input, expected] of cases) {
    assert.equal(escapeHtml(input), expected);
  }
});

test('buildIncidentShareHtml escapes title, summary, neighborhood, and OG tags', () => {
  const html = buildIncidentShareHtml({
    title: '<script>"Market"</script>',
    summary: 'Smoke & "sparks" near <bridge>',
    category: 'fire',
    subtype: 'market_fire',
    severity: 'High',
    status: 'Active',
    neighborhood: 'A&B <Zone>',
    reported_at: Timestamp.fromDate(new Date('2026-07-10T12:34:00.000Z')),
    confirmations: 4,
    disputes: 1,
  }, 'incident_1');

  assert.match(html, /<title>&lt;script&gt;&quot;Market&quot;&lt;\/script&gt; &mdash; PulseTrackr<\/title>/);
  assert.match(html, /<meta property="og:title" content="&lt;script&gt;&quot;Market&quot;&lt;\/script&gt;">/);
  assert.match(html, /<meta property="og:description" content="Smoke &amp; &quot;sparks&quot; near &lt;bridge&gt;">/);
  assert.match(html, /A&amp;B &lt;Zone&gt;/);
  assert.doesNotMatch(html, /<script>"Market"<\/script>/);
  assert.doesNotMatch(html, /Smoke & "sparks" near <bridge>/);
});

test('buildIncidentShareHtml only renders public share fields', () => {
  const html = buildIncidentShareHtml({
    title: 'Road blocked',
    summary: 'Community report',
    category: 'traffic',
    subtype: 'roadblock',
    severity: 'Medium',
    status: 'Watching',
    neighborhood: 'Ring road',
    reported_at: '2026-07-10T12:00:00.000Z',
    confirmations: 2,
    disputes: 3,
    official_updates: 1,
    evidence_summary: { photo_count: 2, voice_count: 1 },
    latitude: 6.524412345,
    longitude: 3.379212345,
    geohash: 'secret-geohash-value',
    public_h3_cell: 'secret-h3-cell-value',
  }, 'incident-2');

  assert.match(html, /2 confirmations &middot; 3 disputes/);
  assert.match(html, /Official update/);
  assert.match(html, /Evidence: 2 photos \/ 1 voice clip/);
  assert.doesNotMatch(html, /6\.524412345/);
  assert.doesNotMatch(html, /3\.379212345/);
  assert.doesNotMatch(html, /secret-geohash-value/);
  assert.doesNotMatch(html, /secret-h3-cell-value/);
});

test('official update line toggles off when no official updates exist', () => {
  const html = buildIncidentShareHtml({
    title: 'Crash cleared',
    summary: 'Traffic moving again',
    category: 'traffic',
    severity: 'Low',
    status: 'Watching',
    neighborhood: 'Central',
    official_updates: 0,
  }, 'incident-3');

  assert.doesNotMatch(html, /Official update/);
});

test('incident id validation rejects traversal, long, empty, and percent-encoded ids', () => {
  assert.equal(incidentIdFromRequestPath('/i/../x', undefined), null);
  assert.equal(incidentIdFromRequestPath(`/i/${'a'.repeat(200)}`, undefined), null);
  assert.equal(incidentIdFromRequestPath('/i/', undefined), null);
  assert.equal(incidentIdFromRequestPath('/i/%2e%2e', undefined), null);
  assert.equal(incidentIdFromRequestPath('/share', 'incident_OK-1'), 'incident_OK-1');
});

test('404 body is identical for missing and expired incidents', () => {
  const now = new Date('2026-07-10T12:00:00.000Z');
  const missing = buildIncidentShareResponse(null, 'incident-404', now);
  const expired = buildIncidentShareResponse({
    title: 'Expired incident',
    summary: 'Should not leak',
    deleteAfter: Timestamp.fromDate(new Date('2026-07-10T11:59:59.000Z')),
  }, 'incident-404', now);

  assert.equal(missing.status, 404);
  assert.equal(expired.status, 404);
  assert.equal(missing.cacheControl, 'no-store');
  assert.equal(expired.cacheControl, 'no-store');
  assert.equal(missing.body, expired.body);
  assert.doesNotMatch(expired.body, /Expired incident|Should not leak/);
});
