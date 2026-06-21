// Cross-cutting helpers used by every domain: object/string cleaning, timestamp
// coercion, auth/error translation, retention windows, and location shaping.

import { HttpsError } from 'firebase-functions/v2/https';
import { Timestamp } from './admin';
import { HARD_LIMITS } from '../sosShared';

export function withoutUndefined(object: Record<string, unknown>): Record<string, unknown> {
  return Object.fromEntries(Object.entries(object).filter(([, value]) => value !== undefined));
}

export function cleanString(value: unknown, maxLength: number): string {
  return typeof value === 'string' ? value.trim().slice(0, maxLength) : '';
}

export function numberOr(value: unknown, fallback: number): number {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

export function timestampToDate(value: any): Date | null {
  if (!value) return null;
  if (value instanceof Date) return value;
  if (typeof value.toDate === 'function') return value.toDate();
  if (typeof value === 'string') {
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? null : date;
  }
  return null;
}

export function timestampToIso(value: any): string | null {
  const date = timestampToDate(value);
  return date ? date.toISOString() : null;
}

export function requireAuth(request: any): string {
  if (!request.auth?.uid) {
    throw new HttpsError('unauthenticated', 'Sign in is required for SOS');
  }
  return request.auth.uid;
}

export function translateErrors<T>(callback: () => T): T {
  try {
    return callback();
  } catch (error: any) {
    if (error instanceof HttpsError) {
      throw error;
    }
    if (error.code === 'invalid-argument') {
      throw new HttpsError('invalid-argument', error.message);
    }
    throw error;
  }
}

export function retentionDate(now: Date): Date {
  return new Date(now.getTime() + HARD_LIMITS.retentionSeconds * 1000);
}

export function firestoreLocation(location: any): Record<string, unknown> {
  return withoutUndefined({
    latitude: location.latitude,
    longitude: location.longitude,
    horizontalAccuracyMeters: location.horizontalAccuracyMeters,
    altitudeMeters: location.altitudeMeters,
    speedMetersPerSecond: location.speedMetersPerSecond,
    courseDegrees: location.courseDegrees,
    capturedAt: Timestamp.fromDate(location.capturedAt),
  });
}

export function plainLocation(location: any): Record<string, unknown> | null {
  if (!location) return null;
  return withoutUndefined({
    latitude: location.latitude,
    longitude: location.longitude,
    horizontal_accuracy_meters: location.horizontalAccuracyMeters,
    altitude_meters: location.altitudeMeters,
    speed_meters_per_second: location.speedMetersPerSecond,
    course_degrees: location.courseDegrees,
    captured_at: timestampToIso(location.capturedAt),
  });
}
