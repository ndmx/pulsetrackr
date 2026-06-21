import { z } from 'zod';

// Wire enums. rawValues mirror the iOS enums in app/Incident.swift EXACTLY — this
// package is the source of truth, so a change here is the change that regenerates the
// Swift types. Values verified against functions/src/index.js (SIGNAL_COUNTER_FIELD,
// INCIDENT_CONCERN_REASONS) so client, contract, and server agree on the wire format.

export const incidentCategory = z.enum([
  'security',
  'traffic',
  'fire',
  'medical',
  'weather',
  'utilities',
  'structure',
  'community',
]);
export type IncidentCategory = z.infer<typeof incidentCategory>;

// Capitalized on the wire (IncidentSeverity.rawValue is "Low"/"Medium"/...).
export const incidentSeverity = z.enum(['Low', 'Medium', 'High', 'Urgent']);
export type IncidentSeverity = z.infer<typeof incidentSeverity>;

// Capitalized on the wire (IncidentStatus.rawValue is "Active"/"Watching"/"Resolved").
export const incidentStatus = z.enum(['Active', 'Watching', 'Resolved']);
export type IncidentStatus = z.infer<typeof incidentStatus>;

// camelCase default rawValues — these are the keys of SIGNAL_COUNTER_FIELD in index.js.
export const communitySignal = z.enum([
  'seen',
  'notSeen',
  'unsafe',
  'roadBlocked',
  'cleared',
]);
export type CommunitySignal = z.infer<typeof communitySignal>;

export const incidentConcernReason = z.enum([
  'false_report',
  'offensive_content',
  'private_information',
  'dangerous_advice',
  'spam_or_abuse',
]);
export type IncidentConcernReason = z.infer<typeof incidentConcernReason>;
