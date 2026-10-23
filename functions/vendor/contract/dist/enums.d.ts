import { z } from 'zod';
export declare const incidentCategory: z.ZodEnum<["security", "traffic", "fire", "medical", "weather", "utilities", "structure", "community"]>;
export type IncidentCategory = z.infer<typeof incidentCategory>;
export declare const incidentSeverity: z.ZodEnum<["Low", "Medium", "High", "Urgent"]>;
export type IncidentSeverity = z.infer<typeof incidentSeverity>;
export declare const incidentStatus: z.ZodEnum<["Active", "Watching", "Resolved"]>;
export type IncidentStatus = z.infer<typeof incidentStatus>;
export declare const communitySignal: z.ZodEnum<["seen", "notSeen", "unsafe", "roadBlocked", "cleared"]>;
export type CommunitySignal = z.infer<typeof communitySignal>;
export declare const incidentConcernReason: z.ZodEnum<["false_report", "offensive_content", "private_information", "dangerous_advice", "spam_or_abuse"]>;
export type IncidentConcernReason = z.infer<typeof incidentConcernReason>;
//# sourceMappingURL=enums.d.ts.map