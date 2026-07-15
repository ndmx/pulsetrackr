'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const { encodeGeohash } = require('../lib/geohash');

// Local decoder mirrors the client test: confirms the encoded cell contains the
// original point, which is the core correctness property of the encoder.
function decodeBounds(hash) {
  const BASE32 = '0123456789bcdefghjkmnpqrstuvwxyz';
  let lat = [-90, 90];
  let lon = [-180, 180];
  let isEven = true;
  for (const ch of hash) {
    const cd = BASE32.indexOf(ch);
    for (const mask of [16, 8, 4, 2, 1]) {
      if (isEven) {
        const mid = (lon[0] + lon[1]) / 2;
        if (cd & mask) { lon[0] = mid; } else { lon[1] = mid; }
      } else {
        const mid = (lat[0] + lat[1]) / 2;
        if (cd & mask) { lat[0] = mid; } else { lat[1] = mid; }
      }
      isEven = !isEven;
    }
  }
  return { latMin: lat[0], latMax: lat[1], lonMin: lon[0], lonMax: lon[1] };
}

test('encodes the canonical origin cell', () => {
  assert.equal(encodeGeohash(0, 0, 5), 's0000');
});

test('produces the requested length', () => {
  assert.equal(encodeGeohash(6.5244, 3.3792, 9).length, 9);
});

test('encoded cell contains its point (matches client encoder)', () => {
  const points = [
    [6.5244, 3.3792],
    [40.7484, -73.9857],
    [-33.8688, 151.2093],
    [51.5074, -0.1278],
    [0, 0],
  ];
  for (const [lat, lon] of points) {
    for (const precision of [4, 6, 9]) {
      const b = decodeBounds(encodeGeohash(lat, lon, precision));
      assert.ok(lat >= b.latMin && lat <= b.latMax, `lat ${lat} @${precision}`);
      assert.ok(lon >= b.lonMin && lon <= b.lonMax, `lon ${lon} @${precision}`);
    }
  }
});
