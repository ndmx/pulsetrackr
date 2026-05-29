'use strict';

// End-to-end validation of the geo-bounded incident feed against the Firestore
// emulator. This fills the gap the offline unit tests can't cover: that writing a
// geohash and querying prefix ranges actually returns nearby incidents and excludes
// far ones. Run via:  npm run test:geo  (from functions/), which wraps this in
// `firebase emulators:exec --only firestore`.
//
// The covering-prefix logic below mirrors app/Geohash.swift (the source of truth,
// unit-tested separately); running it here in a second language also cross-checks
// that both implementations agree against real Firestore behaviour.

const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const admin = require('firebase-admin');
const { encodeGeohash } = require('../src/geohash');

const BASE32 = '0123456789bcdefghjkmnpqrstuvwxyz';
const NEIGHBOUR_EVEN = {
  right: 'bc01fg45238967deuvhjyznpkmstqrwx',
  left: '238967debc01fg45kmstqrwxuvhjyznp',
  top: 'p0r21436x8zb9dcf5h7kjnmqesgutwvy',
  bottom: '14365h7k9dcfesgujnmqp0r2twvyx8zb',
};
const BORDER_EVEN = { right: 'bcfguvyz', left: '0145hjnp', top: 'prxz', bottom: '028b' };
const ODD_MAP = { bottom: 'left', top: 'right', left: 'bottom', right: 'top' };

function table(base, dir, oddLength) {
  return oddLength ? base[ODD_MAP[dir]] : base[dir];
}

function adjacent(hash, dir) {
  const last = hash[hash.length - 1];
  const oddLength = hash.length % 2 === 1;
  let base = hash.slice(0, -1);
  if (table(BORDER_EVEN, dir, oddLength).indexOf(last) !== -1 && base.length) {
    base = adjacent(base, dir);
  }
  return base + BASE32[table(NEIGHBOUR_EVEN, dir, oddLength).indexOf(last)];
}

function neighbours(hash) {
  const north = adjacent(hash, 'top');
  const south = adjacent(hash, 'bottom');
  return [
    north, south, adjacent(hash, 'left'), adjacent(hash, 'right'),
    adjacent(north, 'left'), adjacent(north, 'right'),
    adjacent(south, 'left'), adjacent(south, 'right'),
  ];
}

function precisionForRadius(radius) {
  if (radius < 610) return 6;
  if (radius < 4900) return 5;
  if (radius < 19500) return 4;
  if (radius < 156000) return 3;
  return 2;
}

function coveringPrefixes(lat, lon, radius) {
  const center = encodeGeohash(lat, lon, precisionForRadius(radius));
  return Array.from(new Set([center, ...neighbours(center)]));
}

function haversineMeters(aLat, aLon, bLat, bLon) {
  const R = 6371000;
  const toRad = (d) => (d * Math.PI) / 180;
  const dLat = toRad(bLat - aLat);
  const dLon = toRad(bLon - aLon);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(aLat)) * Math.cos(toRad(bLat)) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}

const COLLECTION = 'safety_incidents_public';
let db;

// Lagos centre; incidents at varying distances plus a different continent.
const CENTER = { lat: 6.5244, lon: 3.3792 };
const FIXTURES = [
  { id: 'near-1', lat: 6.5244, lon: 3.3792, status: 'active' },   // 0 m
  { id: 'near-2', lat: 6.5300, lon: 3.3850, status: 'active' },   // ~0.9 km
  { id: 'near-3', lat: 6.5100, lon: 3.3700, status: 'watching' }, // ~1.8 km
  { id: 'edge',   lat: 6.6100, lon: 3.4400, status: 'active' },   // ~11 km (outside 3 km)
  { id: 'far-ny', lat: 40.7484, lon: -73.9857, status: 'active' }, // another continent
  { id: 'resolved-near', lat: 6.5250, lon: 3.3800, status: 'resolved' }, // near but inactive
];

before(async () => {
  admin.initializeApp({ projectId: 'demo-pulsetrackr-geo' });
  db = admin.firestore();
  const batch = db.batch();
  for (const f of FIXTURES) {
    batch.set(db.collection(COLLECTION).doc(f.id), {
      title: f.id,
      status: f.status,
      latitude: f.lat,
      longitude: f.lon,
      geohash: encodeGeohash(f.lat, f.lon),
      reported_at: admin.firestore.Timestamp.now(),
    });
  }
  await batch.commit();
});

after(async () => {
  await admin.app().delete();
});

// Runs the client's query strategy: prefix-range queries over covering cells,
// merged, then distance- and status-filtered.
async function queryNearby(center, radiusMeters) {
  const prefixes = coveringPrefixes(center.lat, center.lon, radiusMeters);
  const seen = new Map();
  for (const prefix of prefixes) {
    const snap = await db.collection(COLLECTION)
      .orderBy('geohash')
      .startAt(prefix)
      .endBefore(`${prefix}~`)
      .get();
    snap.forEach((doc) => seen.set(doc.id, doc.data()));
  }
  return [...seen.values()].filter((d) =>
    (d.status === 'active' || d.status === 'watching')
    && haversineMeters(center.lat, center.lon, d.latitude, d.longitude) <= radiusMeters);
}

test('prefix-range query returns only docs with that geohash prefix', async () => {
  // Pure Firestore-mechanics check, independent of the covering logic.
  const prefix = encodeGeohash(CENTER.lat, CENTER.lon, 5);
  const snap = await db.collection(COLLECTION)
    .orderBy('geohash').startAt(prefix).endBefore(`${prefix}~`).get();
  const ids = snap.docs.map((d) => d.id);
  for (const doc of snap.docs) {
    assert.ok(doc.data().geohash.startsWith(prefix), `${doc.id} should start with ${prefix}`);
  }
  assert.ok(!ids.includes('far-ny'), 'New York must not appear in a Lagos prefix range');
});

test('nearby active incidents returned, far and resolved excluded (3 km)', async () => {
  const results = await queryNearby(CENTER, 3000);
  const ids = results.map((r) => r.title).sort();
  assert.deepEqual(ids, ['near-1', 'near-2', 'near-3'], `got ${JSON.stringify(ids)}`);
});

test('widening the radius to 15 km pulls in the edge incident', async () => {
  const results = await queryNearby(CENTER, 15000);
  const ids = results.map((r) => r.title).sort();
  assert.ok(ids.includes('edge'), 'edge incident should appear at 15 km');
  assert.ok(!ids.includes('far-ny'), 'another continent must still be excluded');
  assert.ok(!ids.includes('resolved-near'), 'resolved incidents are never shown');
});
