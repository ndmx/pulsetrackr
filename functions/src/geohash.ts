// Standard (GeoFire-compatible) geohash encoding. Must stay byte-for-byte
// compatible with the client encoder (app/Geohash.swift) so prefix-range queries
// line up. Written onto each public incident so the app can geo-bound its feed.

const BASE32 = '0123456789bcdefghjkmnpqrstuvwxyz';
export const GEOHASH_PRECISION = 9;

export function encodeGeohash(latitude: number, longitude: number, precision: number = GEOHASH_PRECISION): string {
  let latMin = -90;
  let latMax = 90;
  let lonMin = -180;
  let lonMax = 180;
  let hash = '';
  let isEven = true;
  let bit = 0;
  let ch = 0;

  while (hash.length < precision) {
    if (isEven) {
      const mid = (lonMin + lonMax) / 2;
      if (longitude >= mid) {
        ch |= (1 << (4 - bit));
        lonMin = mid;
      } else {
        lonMax = mid;
      }
    } else {
      const mid = (latMin + latMax) / 2;
      if (latitude >= mid) {
        ch |= (1 << (4 - bit));
        latMin = mid;
      } else {
        latMax = mid;
      }
    }

    isEven = !isEven;
    if (bit < 4) {
      bit += 1;
    } else {
      hash += BASE32[ch];
      bit = 0;
      ch = 0;
    }
  }
  return hash;
}
