import { z } from 'zod';
/** Platforms that can register for push. */
export declare const pushPlatform: z.ZodEnum<["ios"]>;
export type PushPlatform = z.infer<typeof pushPlatform>;
export declare const registerPushDevicePayload: z.ZodObject<{
    /** Current FCM registration token for this install. */
    fcm_token: z.ZodString;
    platform: z.ZodEnum<["ios"]>;
    app_version: z.ZodString;
    /** Mirrors the `urgentAlerts` setting — subscribe to urgent-tier topics. */
    urgent_alerts: z.ZodBoolean;
    /** Mirrors the `communityAlerts` setting — subscribe to community-tier topics. */
    community_alerts: z.ZodBoolean;
    /** Watch-region center; used only to derive topic cells, never persisted raw. */
    latitude: z.ZodNumber;
    longitude: z.ZodNumber;
    /** Watch radius in kilometers (Settings slider range, generous upper bound). */
    watch_radius_km: z.ZodNumber;
}, "strip", z.ZodTypeAny, {
    latitude: number;
    longitude: number;
    fcm_token: string;
    platform: "ios";
    app_version: string;
    urgent_alerts: boolean;
    community_alerts: boolean;
    watch_radius_km: number;
}, {
    latitude: number;
    longitude: number;
    fcm_token: string;
    platform: "ios";
    app_version: string;
    urgent_alerts: boolean;
    community_alerts: boolean;
    watch_radius_km: number;
}>;
export type RegisterPushDevicePayload = z.infer<typeof registerPushDevicePayload>;
export declare const pushDeviceRecord: z.ZodObject<{
    owner_uid: z.ZodString;
    fcm_token: z.ZodString;
    platform: z.ZodEnum<["ios"]>;
    app_version: z.ZodString;
    /** FCM topic names this token is subscribed to (server-derived). */
    subscribed_topics: z.ZodArray<z.ZodString, "many">;
}, "strip", z.ZodTypeAny, {
    fcm_token: string;
    platform: "ios";
    app_version: string;
    owner_uid: string;
    subscribed_topics: string[];
}, {
    fcm_token: string;
    platform: "ios";
    app_version: string;
    owner_uid: string;
    subscribed_topics: string[];
}>;
export type PushDeviceRecord = z.infer<typeof pushDeviceRecord>;
//# sourceMappingURL=push.d.ts.map