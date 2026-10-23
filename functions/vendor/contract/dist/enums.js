"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.incidentConcernReason = exports.communitySignal = exports.incidentStatus = exports.incidentSeverity = exports.incidentCategory = void 0;
const zod_1 = require("zod");
// Wire enums. rawValues mirror the iOS enums in app/Incident.swift EXACTLY — this
// package is the source of truth, so a change here is the change that regenerates the
// Swift types. Values verified against functions/src/index.js (SIGNAL_COUNTER_FIELD,
// INCIDENT_CONCERN_REASONS) so client, contract, and server agree on the wire format.
exports.incidentCategory = zod_1.z.enum([
    'security',
    'traffic',
    'fire',
    'medical',
    'weather',
    'utilities',
    'structure',
    'community',
]);
// Capitalized on the wire (IncidentSeverity.rawValue is "Low"/"Medium"/...).
exports.incidentSeverity = zod_1.z.enum(['Low', 'Medium', 'High', 'Urgent']);
// Capitalized on the wire (IncidentStatus.rawValue is "Active"/"Watching"/"Resolved").
exports.incidentStatus = zod_1.z.enum(['Active', 'Watching', 'Resolved']);
// camelCase default rawValues — these are the keys of SIGNAL_COUNTER_FIELD in index.js.
exports.communitySignal = zod_1.z.enum([
    'seen',
    'notSeen',
    'unsafe',
    'roadBlocked',
    'cleared',
]);
exports.incidentConcernReason = zod_1.z.enum([
    'false_report',
    'offensive_content',
    'private_information',
    'dangerous_advice',
    'spam_or_abuse',
]);
//# sourceMappingURL=enums.js.map