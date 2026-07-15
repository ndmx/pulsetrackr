import { gridDisk, latLngToCell } from 'h3-js';

const MAX_QUERY_CELLS = 300;

export function h3QueryCellsForRadius(latitude: number, longitude: number, radiusMeters: number): string[] {
  const res8 = gridDisk(
    latLngToCell(latitude, longitude, 8),
    ringSize(radiusMeters, 650, 12),
  );
  const res7 = gridDisk(
    latLngToCell(latitude, longitude, 7),
    ringSize(radiusMeters, 1800, 8),
  );
  return [...new Set([...res8, ...res7])].slice(0, MAX_QUERY_CELLS);
}

function ringSize(radiusMeters: number, metersPerRing: number, maxRing: number): number {
  return Math.min(Math.max(Math.ceil(radiusMeters / metersPerRing), 1), maxRing);
}

