import { z } from 'zod';
/** Mirrors `HARD_LIMITS` in functions/src/sosShared.js. */
export declare const HARD_LIMITS: {
    readonly recentTrailMaxPoints: 24;
    readonly recentTrailMaxAgeSeconds: number;
    readonly liveLocationUpdateIntervalSeconds: 15;
    readonly adminAccessExpiresAfterSeconds: number;
    readonly retentionSeconds: number;
    readonly activationCooldownSeconds: 60;
    readonly activationWindowSeconds: number;
    readonly activationWindowLimit: 5;
};
/** Mirrors `DEFAULT_POLICY` in functions/src/sosShared.js. */
export declare const DEFAULT_POLICY: {
    readonly includeRecentTrail: true;
    readonly recentTrailMaxPoints: 12;
    readonly recentTrailMaxAgeSeconds: number;
    readonly liveLocationUpdateIntervalSeconds: 30;
    readonly shareExactLocationWithTrustedContacts: true;
    readonly adminAccessExpiresAfterSeconds: number;
    readonly lawEnforcementAccessRequiresActiveSession: true;
    readonly auditPrivilegedAccess: true;
};
/** Mirrors `PRIVILEGED_ROLES` in sosShared.js. */
export declare const privilegedRole: z.ZodEnum<["sosAdmin", "careTeam", "lawEnforcement"]>;
export type PrivilegedRole = z.infer<typeof privilegedRole>;
/** Mirrors `DISCLOSURE_SCOPES` in sosShared.js. */
export declare const disclosureScope: z.ZodEnum<["last_known_location", "direction_of_travel", "redacted_trusted_contacts", "recent_trail"]>;
export type DisclosureScope = z.infer<typeof disclosureScope>;
/** Mirrors `LEGAL_PROCESS_TYPES` in sosShared.js. */
export declare const legalProcessType: z.ZodEnum<["warrant", "court_order", "subpoena", "emergency_disclosure_request", "other"]>;
export type LegalProcessType = z.infer<typeof legalProcessType>;
/** Mirrors `ALLOWED_CHANNELS` in sosShared.js. */
export declare const notificationChannel: z.ZodEnum<["sms", "phone_call", "email", "app_push"]>;
export type NotificationChannel = z.infer<typeof notificationChannel>;
/** Mirrors `ALLOWED_RESOLUTION_REASONS` in sosShared.js. */
export declare const resolutionReason: z.ZodEnum<["user_resolved", "false_alarm", "timed_out", "transferred_to_care_team", "arrived_safely"]>;
export type ResolutionReason = z.infer<typeof resolutionReason>;
/**
 * Session kind: a real SOS emergency vs a "walk with me" escort session. Escort
 * sessions reuse the SOS trail machinery but alert exactly one app trusted
 * contact and never trigger the Twilio fan-out.
 */
export declare const sessionKind: z.ZodEnum<["sos", "escort"]>;
export type SessionKind = z.infer<typeof sessionKind>;
/** Mirrors `sanitizeLocationSnapshot()` output. */
export declare const sosLocation: z.ZodObject<{
    latitude: z.ZodNumber;
    longitude: z.ZodNumber;
    /** >= 0 (nonNegative). */
    horizontalAccuracyMeters: z.ZodOptional<z.ZodNumber>;
    /** Any finite number. */
    altitudeMeters: z.ZodOptional<z.ZodNumber>;
    /** >= 0 (nonNegative). */
    speedMetersPerSecond: z.ZodOptional<z.ZodNumber>;
    /** Normalized to [0, 360). */
    courseDegrees: z.ZodOptional<z.ZodNumber>;
    capturedAt: z.ZodString;
}, "strip", z.ZodTypeAny, {
    latitude: number;
    longitude: number;
    capturedAt: string;
    horizontalAccuracyMeters?: number | undefined;
    altitudeMeters?: number | undefined;
    speedMetersPerSecond?: number | undefined;
    courseDegrees?: number | undefined;
}, {
    latitude: number;
    longitude: number;
    capturedAt: string;
    horizontalAccuracyMeters?: number | undefined;
    altitudeMeters?: number | undefined;
    speedMetersPerSecond?: number | undefined;
    courseDegrees?: number | undefined;
}>;
export type SosLocation = z.infer<typeof sosLocation>;
/** Mirrors `sanitizeDirectionOfTravel()` output (null when absent). */
export declare const directionOfTravel: z.ZodObject<{
    /** Normalized to [0, 360). */
    bearingDegrees: z.ZodOptional<z.ZodNumber>;
    /** >= 0 (nonNegative). */
    speedMetersPerSecond: z.ZodOptional<z.ZodNumber>;
    /** clampInteger(.., 0, 0, 1000). */
    computedFromPointCount: z.ZodOptional<z.ZodNumber>;
}, "strip", z.ZodTypeAny, {
    speedMetersPerSecond?: number | undefined;
    bearingDegrees?: number | undefined;
    computedFromPointCount?: number | undefined;
}, {
    speedMetersPerSecond?: number | undefined;
    bearingDegrees?: number | undefined;
    computedFromPointCount?: number | undefined;
}>;
export type DirectionOfTravel = z.infer<typeof directionOfTravel>;
/** Mirrors `sanitizeDevice()` output (all keys optional, nullish-stripped). */
export declare const sosDevice: z.ZodObject<{
    /** clampInteger(.., null, 0, 100). */
    batteryLevelPercent: z.ZodOptional<z.ZodNumber>;
    batteryState: z.ZodOptional<z.ZodEffects<z.ZodString, string | undefined, string>>;
    /** Only present when `=== true`. */
    lowPowerModeEnabled: z.ZodOptional<z.ZodBoolean>;
    networkStatus: z.ZodOptional<z.ZodEffects<z.ZodString, string | undefined, string>>;
    /** sliced to max 6 non-empty strings. */
    networkInterfaceTypes: z.ZodOptional<z.ZodArray<z.ZodString, "many">>;
    appVersion: z.ZodOptional<z.ZodEffects<z.ZodString, string | undefined, string>>;
    buildNumber: z.ZodOptional<z.ZodEffects<z.ZodString, string | undefined, string>>;
    deviceModel: z.ZodOptional<z.ZodEffects<z.ZodString, string | undefined, string>>;
    systemVersion: z.ZodOptional<z.ZodEffects<z.ZodString, string | undefined, string>>;
}, "strip", z.ZodTypeAny, {
    batteryLevelPercent?: number | undefined;
    batteryState?: string | undefined;
    lowPowerModeEnabled?: boolean | undefined;
    networkStatus?: string | undefined;
    networkInterfaceTypes?: string[] | undefined;
    appVersion?: string | undefined;
    buildNumber?: string | undefined;
    deviceModel?: string | undefined;
    systemVersion?: string | undefined;
}, {
    batteryLevelPercent?: number | undefined;
    batteryState?: string | undefined;
    lowPowerModeEnabled?: boolean | undefined;
    networkStatus?: string | undefined;
    networkInterfaceTypes?: string[] | undefined;
    appVersion?: string | undefined;
    buildNumber?: string | undefined;
    deviceModel?: string | undefined;
    systemVersion?: string | undefined;
}>;
export type SosDevice = z.infer<typeof sosDevice>;
/** Mirrors `sanitizePrivacyPolicy()` output. */
export declare const privacyPolicy: z.ZodObject<{
    includeRecentTrail: z.ZodBoolean;
    /** clampInteger 0..HARD_LIMITS.recentTrailMaxPoints. */
    recentTrailMaxPoints: z.ZodNumber;
    /** clampInteger 0..HARD_LIMITS.recentTrailMaxAgeSeconds. */
    recentTrailMaxAgeSeconds: z.ZodNumber;
    /** clampInteger HARD_LIMITS.liveLocationUpdateIntervalSeconds..300. */
    liveLocationUpdateIntervalSeconds: z.ZodNumber;
    shareExactLocationWithTrustedContacts: z.ZodBoolean;
    /** clampInteger 60..HARD_LIMITS.adminAccessExpiresAfterSeconds. */
    adminAccessExpiresAfterSeconds: z.ZodNumber;
    lawEnforcementAccessRequiresActiveSession: z.ZodBoolean;
    auditPrivilegedAccess: z.ZodBoolean;
}, "strip", z.ZodTypeAny, {
    includeRecentTrail: boolean;
    recentTrailMaxPoints: number;
    recentTrailMaxAgeSeconds: number;
    liveLocationUpdateIntervalSeconds: number;
    shareExactLocationWithTrustedContacts: boolean;
    adminAccessExpiresAfterSeconds: number;
    lawEnforcementAccessRequiresActiveSession: boolean;
    auditPrivilegedAccess: boolean;
}, {
    includeRecentTrail: boolean;
    recentTrailMaxPoints: number;
    recentTrailMaxAgeSeconds: number;
    liveLocationUpdateIntervalSeconds: number;
    shareExactLocationWithTrustedContacts: boolean;
    adminAccessExpiresAfterSeconds: number;
    lawEnforcementAccessRequiresActiveSession: boolean;
    auditPrivilegedAccess: boolean;
}>;
export type PrivacyPolicy = z.infer<typeof privacyPolicy>;
/** Mirrors a single entry of `sanitizeTrustedContacts()` output. */
export declare const trustedContact: z.ZodObject<{
    contactId: z.ZodString;
    displayName: z.ZodString;
    relationshipLabel: z.ZodOptional<z.ZodEffects<z.ZodString, string | undefined, string>>;
    phoneNumber: z.ZodOptional<z.ZodEffects<z.ZodString, string | undefined, string>>;
    emailAddress: z.ZodOptional<z.ZodEffects<z.ZodString, string | undefined, string>>;
    appUserUid: z.ZodOptional<z.ZodEffects<z.ZodString, string | undefined, string>>;
    appRelationshipId: z.ZodOptional<z.ZodEffects<z.ZodString, string | undefined, string>>;
    /** Deliverable channels only, de-duplicated; at least one is required to survive. */
    channels: z.ZodArray<z.ZodEnum<["sms", "phone_call", "email", "app_push"]>, "many">;
    consentedAt: z.ZodOptional<z.ZodString>;
}, "strip", z.ZodTypeAny, {
    contactId: string;
    displayName: string;
    channels: ("sms" | "phone_call" | "email" | "app_push")[];
    relationshipLabel?: string | undefined;
    phoneNumber?: string | undefined;
    emailAddress?: string | undefined;
    appUserUid?: string | undefined;
    appRelationshipId?: string | undefined;
    consentedAt?: string | undefined;
}, {
    contactId: string;
    displayName: string;
    channels: ("sms" | "phone_call" | "email" | "app_push")[];
    relationshipLabel?: string | undefined;
    phoneNumber?: string | undefined;
    emailAddress?: string | undefined;
    appUserUid?: string | undefined;
    appRelationshipId?: string | undefined;
    consentedAt?: string | undefined;
}>;
export type TrustedContact = z.infer<typeof trustedContact>;
/** Mirrors `redactedContact()` output (no raw phone/email/uid leaked). */
export declare const redactedTrustedContact: z.ZodObject<{
    contactId: z.ZodString;
    displayName: z.ZodString;
    relationshipLabel: z.ZodOptional<z.ZodEffects<z.ZodString, string | undefined, string>>;
    channels: z.ZodArray<z.ZodEnum<["sms", "phone_call", "email", "app_push"]>, "many">;
    /** Last 4 digits of the phone number only. */
    phoneLast4: z.ZodOptional<z.ZodEffects<z.ZodString, string | undefined, string>>;
    hasEmailAddress: z.ZodBoolean;
    appRelationshipId: z.ZodOptional<z.ZodEffects<z.ZodString, string | undefined, string>>;
    hasAppRoute: z.ZodBoolean;
    consentedAt: z.ZodOptional<z.ZodString>;
}, "strip", z.ZodTypeAny, {
    contactId: string;
    displayName: string;
    channels: ("sms" | "phone_call" | "email" | "app_push")[];
    hasEmailAddress: boolean;
    hasAppRoute: boolean;
    relationshipLabel?: string | undefined;
    appRelationshipId?: string | undefined;
    consentedAt?: string | undefined;
    phoneLast4?: string | undefined;
}, {
    contactId: string;
    displayName: string;
    channels: ("sms" | "phone_call" | "email" | "app_push")[];
    hasEmailAddress: boolean;
    hasAppRoute: boolean;
    relationshipLabel?: string | undefined;
    appRelationshipId?: string | undefined;
    consentedAt?: string | undefined;
    phoneLast4?: string | undefined;
}>;
export type RedactedTrustedContact = z.infer<typeof redactedTrustedContact>;
/** Mirrors `sanitizeActivationPayload()` output. */
export declare const activationPayload: z.ZodObject<{
    clientSessionId: z.ZodString;
    /** `optionalString(source) || 'ios'`. */
    source: z.ZodString;
    activatedAt: z.ZodString;
    lastKnownLocation: z.ZodObject<{
        latitude: z.ZodNumber;
        longitude: z.ZodNumber;
        /** >= 0 (nonNegative). */
        horizontalAccuracyMeters: z.ZodOptional<z.ZodNumber>;
        /** Any finite number. */
        altitudeMeters: z.ZodOptional<z.ZodNumber>;
        /** >= 0 (nonNegative). */
        speedMetersPerSecond: z.ZodOptional<z.ZodNumber>;
        /** Normalized to [0, 360). */
        courseDegrees: z.ZodOptional<z.ZodNumber>;
        capturedAt: z.ZodString;
    }, "strip", z.ZodTypeAny, {
        latitude: number;
        longitude: number;
        capturedAt: string;
        horizontalAccuracyMeters?: number | undefined;
        altitudeMeters?: number | undefined;
        speedMetersPerSecond?: number | undefined;
        courseDegrees?: number | undefined;
    }, {
        latitude: number;
        longitude: number;
        capturedAt: string;
        horizontalAccuracyMeters?: number | undefined;
        altitudeMeters?: number | undefined;
        speedMetersPerSecond?: number | undefined;
        courseDegrees?: number | undefined;
    }>;
    /** limitRecentTrail(): capped at privacy.recentTrailMaxPoints (<= HARD_LIMITS). */
    recentTrail: z.ZodArray<z.ZodObject<{
        latitude: z.ZodNumber;
        longitude: z.ZodNumber;
        /** >= 0 (nonNegative). */
        horizontalAccuracyMeters: z.ZodOptional<z.ZodNumber>;
        /** Any finite number. */
        altitudeMeters: z.ZodOptional<z.ZodNumber>;
        /** >= 0 (nonNegative). */
        speedMetersPerSecond: z.ZodOptional<z.ZodNumber>;
        /** Normalized to [0, 360). */
        courseDegrees: z.ZodOptional<z.ZodNumber>;
        capturedAt: z.ZodString;
    }, "strip", z.ZodTypeAny, {
        latitude: number;
        longitude: number;
        capturedAt: string;
        horizontalAccuracyMeters?: number | undefined;
        altitudeMeters?: number | undefined;
        speedMetersPerSecond?: number | undefined;
        courseDegrees?: number | undefined;
    }, {
        latitude: number;
        longitude: number;
        capturedAt: string;
        horizontalAccuracyMeters?: number | undefined;
        altitudeMeters?: number | undefined;
        speedMetersPerSecond?: number | undefined;
        courseDegrees?: number | undefined;
    }>, "many">;
    /** null when absent. */
    directionOfTravel: z.ZodNullable<z.ZodObject<{
        /** Normalized to [0, 360). */
        bearingDegrees: z.ZodOptional<z.ZodNumber>;
        /** >= 0 (nonNegative). */
        speedMetersPerSecond: z.ZodOptional<z.ZodNumber>;
        /** clampInteger(.., 0, 0, 1000). */
        computedFromPointCount: z.ZodOptional<z.ZodNumber>;
    }, "strip", z.ZodTypeAny, {
        speedMetersPerSecond?: number | undefined;
        bearingDegrees?: number | undefined;
        computedFromPointCount?: number | undefined;
    }, {
        speedMetersPerSecond?: number | undefined;
        bearingDegrees?: number | undefined;
        computedFromPointCount?: number | undefined;
    }>>;
    /** Capped at 10 deliverable contacts. Must be empty for escort sessions. */
    trustedContacts: z.ZodArray<z.ZodObject<{
        contactId: z.ZodString;
        displayName: z.ZodString;
        relationshipLabel: z.ZodOptional<z.ZodEffects<z.ZodString, string | undefined, string>>;
        phoneNumber: z.ZodOptional<z.ZodEffects<z.ZodString, string | undefined, string>>;
        emailAddress: z.ZodOptional<z.ZodEffects<z.ZodString, string | undefined, string>>;
        appUserUid: z.ZodOptional<z.ZodEffects<z.ZodString, string | undefined, string>>;
        appRelationshipId: z.ZodOptional<z.ZodEffects<z.ZodString, string | undefined, string>>;
        /** Deliverable channels only, de-duplicated; at least one is required to survive. */
        channels: z.ZodArray<z.ZodEnum<["sms", "phone_call", "email", "app_push"]>, "many">;
        consentedAt: z.ZodOptional<z.ZodString>;
    }, "strip", z.ZodTypeAny, {
        contactId: string;
        displayName: string;
        channels: ("sms" | "phone_call" | "email" | "app_push")[];
        relationshipLabel?: string | undefined;
        phoneNumber?: string | undefined;
        emailAddress?: string | undefined;
        appUserUid?: string | undefined;
        appRelationshipId?: string | undefined;
        consentedAt?: string | undefined;
    }, {
        contactId: string;
        displayName: string;
        channels: ("sms" | "phone_call" | "email" | "app_push")[];
        relationshipLabel?: string | undefined;
        phoneNumber?: string | undefined;
        emailAddress?: string | undefined;
        appUserUid?: string | undefined;
        appRelationshipId?: string | undefined;
        consentedAt?: string | undefined;
    }>, "many">;
    device: z.ZodObject<{
        /** clampInteger(.., null, 0, 100). */
        batteryLevelPercent: z.ZodOptional<z.ZodNumber>;
        batteryState: z.ZodOptional<z.ZodEffects<z.ZodString, string | undefined, string>>;
        /** Only present when `=== true`. */
        lowPowerModeEnabled: z.ZodOptional<z.ZodBoolean>;
        networkStatus: z.ZodOptional<z.ZodEffects<z.ZodString, string | undefined, string>>;
        /** sliced to max 6 non-empty strings. */
        networkInterfaceTypes: z.ZodOptional<z.ZodArray<z.ZodString, "many">>;
        appVersion: z.ZodOptional<z.ZodEffects<z.ZodString, string | undefined, string>>;
        buildNumber: z.ZodOptional<z.ZodEffects<z.ZodString, string | undefined, string>>;
        deviceModel: z.ZodOptional<z.ZodEffects<z.ZodString, string | undefined, string>>;
        systemVersion: z.ZodOptional<z.ZodEffects<z.ZodString, string | undefined, string>>;
    }, "strip", z.ZodTypeAny, {
        batteryLevelPercent?: number | undefined;
        batteryState?: string | undefined;
        lowPowerModeEnabled?: boolean | undefined;
        networkStatus?: string | undefined;
        networkInterfaceTypes?: string[] | undefined;
        appVersion?: string | undefined;
        buildNumber?: string | undefined;
        deviceModel?: string | undefined;
        systemVersion?: string | undefined;
    }, {
        batteryLevelPercent?: number | undefined;
        batteryState?: string | undefined;
        lowPowerModeEnabled?: boolean | undefined;
        networkStatus?: string | undefined;
        networkInterfaceTypes?: string[] | undefined;
        appVersion?: string | undefined;
        buildNumber?: string | undefined;
        deviceModel?: string | undefined;
        systemVersion?: string | undefined;
    }>;
    privacy: z.ZodObject<{
        includeRecentTrail: z.ZodBoolean;
        /** clampInteger 0..HARD_LIMITS.recentTrailMaxPoints. */
        recentTrailMaxPoints: z.ZodNumber;
        /** clampInteger 0..HARD_LIMITS.recentTrailMaxAgeSeconds. */
        recentTrailMaxAgeSeconds: z.ZodNumber;
        /** clampInteger HARD_LIMITS.liveLocationUpdateIntervalSeconds..300. */
        liveLocationUpdateIntervalSeconds: z.ZodNumber;
        shareExactLocationWithTrustedContacts: z.ZodBoolean;
        /** clampInteger 60..HARD_LIMITS.adminAccessExpiresAfterSeconds. */
        adminAccessExpiresAfterSeconds: z.ZodNumber;
        lawEnforcementAccessRequiresActiveSession: z.ZodBoolean;
        auditPrivilegedAccess: z.ZodBoolean;
    }, "strip", z.ZodTypeAny, {
        includeRecentTrail: boolean;
        recentTrailMaxPoints: number;
        recentTrailMaxAgeSeconds: number;
        liveLocationUpdateIntervalSeconds: number;
        shareExactLocationWithTrustedContacts: boolean;
        adminAccessExpiresAfterSeconds: number;
        lawEnforcementAccessRequiresActiveSession: boolean;
        auditPrivilegedAccess: boolean;
    }, {
        includeRecentTrail: boolean;
        recentTrailMaxPoints: number;
        recentTrailMaxAgeSeconds: number;
        liveLocationUpdateIntervalSeconds: number;
        shareExactLocationWithTrustedContacts: boolean;
        adminAccessExpiresAfterSeconds: number;
        lawEnforcementAccessRequiresActiveSession: boolean;
        auditPrivilegedAccess: boolean;
    }>;
    /** Absent means 'sos' (legacy clients predate escort sessions). */
    sessionKind: z.ZodOptional<z.ZodEnum<["sos", "escort"]>>;
    /** Required iff sessionKind is 'escort': the accepted app relationship to alert. */
    escortRelationshipId: z.ZodOptional<z.ZodEffects<z.ZodString, string | undefined, string>>;
}, "strip", z.ZodTypeAny, {
    source: string;
    clientSessionId: string;
    activatedAt: string;
    lastKnownLocation: {
        latitude: number;
        longitude: number;
        capturedAt: string;
        horizontalAccuracyMeters?: number | undefined;
        altitudeMeters?: number | undefined;
        speedMetersPerSecond?: number | undefined;
        courseDegrees?: number | undefined;
    };
    recentTrail: {
        latitude: number;
        longitude: number;
        capturedAt: string;
        horizontalAccuracyMeters?: number | undefined;
        altitudeMeters?: number | undefined;
        speedMetersPerSecond?: number | undefined;
        courseDegrees?: number | undefined;
    }[];
    directionOfTravel: {
        speedMetersPerSecond?: number | undefined;
        bearingDegrees?: number | undefined;
        computedFromPointCount?: number | undefined;
    } | null;
    trustedContacts: {
        contactId: string;
        displayName: string;
        channels: ("sms" | "phone_call" | "email" | "app_push")[];
        relationshipLabel?: string | undefined;
        phoneNumber?: string | undefined;
        emailAddress?: string | undefined;
        appUserUid?: string | undefined;
        appRelationshipId?: string | undefined;
        consentedAt?: string | undefined;
    }[];
    device: {
        batteryLevelPercent?: number | undefined;
        batteryState?: string | undefined;
        lowPowerModeEnabled?: boolean | undefined;
        networkStatus?: string | undefined;
        networkInterfaceTypes?: string[] | undefined;
        appVersion?: string | undefined;
        buildNumber?: string | undefined;
        deviceModel?: string | undefined;
        systemVersion?: string | undefined;
    };
    privacy: {
        includeRecentTrail: boolean;
        recentTrailMaxPoints: number;
        recentTrailMaxAgeSeconds: number;
        liveLocationUpdateIntervalSeconds: number;
        shareExactLocationWithTrustedContacts: boolean;
        adminAccessExpiresAfterSeconds: number;
        lawEnforcementAccessRequiresActiveSession: boolean;
        auditPrivilegedAccess: boolean;
    };
    sessionKind?: "sos" | "escort" | undefined;
    escortRelationshipId?: string | undefined;
}, {
    source: string;
    clientSessionId: string;
    activatedAt: string;
    lastKnownLocation: {
        latitude: number;
        longitude: number;
        capturedAt: string;
        horizontalAccuracyMeters?: number | undefined;
        altitudeMeters?: number | undefined;
        speedMetersPerSecond?: number | undefined;
        courseDegrees?: number | undefined;
    };
    recentTrail: {
        latitude: number;
        longitude: number;
        capturedAt: string;
        horizontalAccuracyMeters?: number | undefined;
        altitudeMeters?: number | undefined;
        speedMetersPerSecond?: number | undefined;
        courseDegrees?: number | undefined;
    }[];
    directionOfTravel: {
        speedMetersPerSecond?: number | undefined;
        bearingDegrees?: number | undefined;
        computedFromPointCount?: number | undefined;
    } | null;
    trustedContacts: {
        contactId: string;
        displayName: string;
        channels: ("sms" | "phone_call" | "email" | "app_push")[];
        relationshipLabel?: string | undefined;
        phoneNumber?: string | undefined;
        emailAddress?: string | undefined;
        appUserUid?: string | undefined;
        appRelationshipId?: string | undefined;
        consentedAt?: string | undefined;
    }[];
    device: {
        batteryLevelPercent?: number | undefined;
        batteryState?: string | undefined;
        lowPowerModeEnabled?: boolean | undefined;
        networkStatus?: string | undefined;
        networkInterfaceTypes?: string[] | undefined;
        appVersion?: string | undefined;
        buildNumber?: string | undefined;
        deviceModel?: string | undefined;
        systemVersion?: string | undefined;
    };
    privacy: {
        includeRecentTrail: boolean;
        recentTrailMaxPoints: number;
        recentTrailMaxAgeSeconds: number;
        liveLocationUpdateIntervalSeconds: number;
        shareExactLocationWithTrustedContacts: boolean;
        adminAccessExpiresAfterSeconds: number;
        lawEnforcementAccessRequiresActiveSession: boolean;
        auditPrivilegedAccess: boolean;
    };
    sessionKind?: "sos" | "escort" | undefined;
    escortRelationshipId?: string | undefined;
}>;
export type ActivationPayload = z.infer<typeof activationPayload>;
/** Mirrors `sanitizeLocationUpdatePayload()` output. */
export declare const locationUpdatePayload: z.ZodObject<{
    sessionId: z.ZodString;
    location: z.ZodObject<{
        latitude: z.ZodNumber;
        longitude: z.ZodNumber;
        /** >= 0 (nonNegative). */
        horizontalAccuracyMeters: z.ZodOptional<z.ZodNumber>;
        /** Any finite number. */
        altitudeMeters: z.ZodOptional<z.ZodNumber>;
        /** >= 0 (nonNegative). */
        speedMetersPerSecond: z.ZodOptional<z.ZodNumber>;
        /** Normalized to [0, 360). */
        courseDegrees: z.ZodOptional<z.ZodNumber>;
        capturedAt: z.ZodString;
    }, "strip", z.ZodTypeAny, {
        latitude: number;
        longitude: number;
        capturedAt: string;
        horizontalAccuracyMeters?: number | undefined;
        altitudeMeters?: number | undefined;
        speedMetersPerSecond?: number | undefined;
        courseDegrees?: number | undefined;
    }, {
        latitude: number;
        longitude: number;
        capturedAt: string;
        horizontalAccuracyMeters?: number | undefined;
        altitudeMeters?: number | undefined;
        speedMetersPerSecond?: number | undefined;
        courseDegrees?: number | undefined;
    }>;
    /** clampInteger(.., 0, 0, MAX_SAFE_INTEGER). */
    sequenceNumber: z.ZodNumber;
    capturedAt: z.ZodString;
    directionOfTravel: z.ZodNullable<z.ZodObject<{
        /** Normalized to [0, 360). */
        bearingDegrees: z.ZodOptional<z.ZodNumber>;
        /** >= 0 (nonNegative). */
        speedMetersPerSecond: z.ZodOptional<z.ZodNumber>;
        /** clampInteger(.., 0, 0, 1000). */
        computedFromPointCount: z.ZodOptional<z.ZodNumber>;
    }, "strip", z.ZodTypeAny, {
        speedMetersPerSecond?: number | undefined;
        bearingDegrees?: number | undefined;
        computedFromPointCount?: number | undefined;
    }, {
        speedMetersPerSecond?: number | undefined;
        bearingDegrees?: number | undefined;
        computedFromPointCount?: number | undefined;
    }>>;
    device: z.ZodObject<{
        /** clampInteger(.., null, 0, 100). */
        batteryLevelPercent: z.ZodOptional<z.ZodNumber>;
        batteryState: z.ZodOptional<z.ZodEffects<z.ZodString, string | undefined, string>>;
        /** Only present when `=== true`. */
        lowPowerModeEnabled: z.ZodOptional<z.ZodBoolean>;
        networkStatus: z.ZodOptional<z.ZodEffects<z.ZodString, string | undefined, string>>;
        /** sliced to max 6 non-empty strings. */
        networkInterfaceTypes: z.ZodOptional<z.ZodArray<z.ZodString, "many">>;
        appVersion: z.ZodOptional<z.ZodEffects<z.ZodString, string | undefined, string>>;
        buildNumber: z.ZodOptional<z.ZodEffects<z.ZodString, string | undefined, string>>;
        deviceModel: z.ZodOptional<z.ZodEffects<z.ZodString, string | undefined, string>>;
        systemVersion: z.ZodOptional<z.ZodEffects<z.ZodString, string | undefined, string>>;
    }, "strip", z.ZodTypeAny, {
        batteryLevelPercent?: number | undefined;
        batteryState?: string | undefined;
        lowPowerModeEnabled?: boolean | undefined;
        networkStatus?: string | undefined;
        networkInterfaceTypes?: string[] | undefined;
        appVersion?: string | undefined;
        buildNumber?: string | undefined;
        deviceModel?: string | undefined;
        systemVersion?: string | undefined;
    }, {
        batteryLevelPercent?: number | undefined;
        batteryState?: string | undefined;
        lowPowerModeEnabled?: boolean | undefined;
        networkStatus?: string | undefined;
        networkInterfaceTypes?: string[] | undefined;
        appVersion?: string | undefined;
        buildNumber?: string | undefined;
        deviceModel?: string | undefined;
        systemVersion?: string | undefined;
    }>;
}, "strip", z.ZodTypeAny, {
    capturedAt: string;
    directionOfTravel: {
        speedMetersPerSecond?: number | undefined;
        bearingDegrees?: number | undefined;
        computedFromPointCount?: number | undefined;
    } | null;
    device: {
        batteryLevelPercent?: number | undefined;
        batteryState?: string | undefined;
        lowPowerModeEnabled?: boolean | undefined;
        networkStatus?: string | undefined;
        networkInterfaceTypes?: string[] | undefined;
        appVersion?: string | undefined;
        buildNumber?: string | undefined;
        deviceModel?: string | undefined;
        systemVersion?: string | undefined;
    };
    sessionId: string;
    location: {
        latitude: number;
        longitude: number;
        capturedAt: string;
        horizontalAccuracyMeters?: number | undefined;
        altitudeMeters?: number | undefined;
        speedMetersPerSecond?: number | undefined;
        courseDegrees?: number | undefined;
    };
    sequenceNumber: number;
}, {
    capturedAt: string;
    directionOfTravel: {
        speedMetersPerSecond?: number | undefined;
        bearingDegrees?: number | undefined;
        computedFromPointCount?: number | undefined;
    } | null;
    device: {
        batteryLevelPercent?: number | undefined;
        batteryState?: string | undefined;
        lowPowerModeEnabled?: boolean | undefined;
        networkStatus?: string | undefined;
        networkInterfaceTypes?: string[] | undefined;
        appVersion?: string | undefined;
        buildNumber?: string | undefined;
        deviceModel?: string | undefined;
        systemVersion?: string | undefined;
    };
    sessionId: string;
    location: {
        latitude: number;
        longitude: number;
        capturedAt: string;
        horizontalAccuracyMeters?: number | undefined;
        altitudeMeters?: number | undefined;
        speedMetersPerSecond?: number | undefined;
        courseDegrees?: number | undefined;
    };
    sequenceNumber: number;
}>;
export type LocationUpdatePayload = z.infer<typeof locationUpdatePayload>;
/** Mirrors `sanitizeResolutionPayload()` output. */
export declare const resolutionPayload: z.ZodObject<{
    sessionId: z.ZodString;
    reason: z.ZodEnum<["user_resolved", "false_alarm", "timed_out", "transferred_to_care_team", "arrived_safely"]>;
    resolvedAt: z.ZodString;
    /** null when no final location supplied. */
    finalLocation: z.ZodNullable<z.ZodObject<{
        latitude: z.ZodNumber;
        longitude: z.ZodNumber;
        /** >= 0 (nonNegative). */
        horizontalAccuracyMeters: z.ZodOptional<z.ZodNumber>;
        /** Any finite number. */
        altitudeMeters: z.ZodOptional<z.ZodNumber>;
        /** >= 0 (nonNegative). */
        speedMetersPerSecond: z.ZodOptional<z.ZodNumber>;
        /** Normalized to [0, 360). */
        courseDegrees: z.ZodOptional<z.ZodNumber>;
        capturedAt: z.ZodString;
    }, "strip", z.ZodTypeAny, {
        latitude: number;
        longitude: number;
        capturedAt: string;
        horizontalAccuracyMeters?: number | undefined;
        altitudeMeters?: number | undefined;
        speedMetersPerSecond?: number | undefined;
        courseDegrees?: number | undefined;
    }, {
        latitude: number;
        longitude: number;
        capturedAt: string;
        horizontalAccuracyMeters?: number | undefined;
        altitudeMeters?: number | undefined;
        speedMetersPerSecond?: number | undefined;
        courseDegrees?: number | undefined;
    }>>;
}, "strip", z.ZodTypeAny, {
    sessionId: string;
    reason: "user_resolved" | "false_alarm" | "timed_out" | "transferred_to_care_team" | "arrived_safely";
    resolvedAt: string;
    finalLocation: {
        latitude: number;
        longitude: number;
        capturedAt: string;
        horizontalAccuracyMeters?: number | undefined;
        altitudeMeters?: number | undefined;
        speedMetersPerSecond?: number | undefined;
        courseDegrees?: number | undefined;
    } | null;
}, {
    sessionId: string;
    reason: "user_resolved" | "false_alarm" | "timed_out" | "transferred_to_care_team" | "arrived_safely";
    resolvedAt: string;
    finalLocation: {
        latitude: number;
        longitude: number;
        capturedAt: string;
        horizontalAccuracyMeters?: number | undefined;
        altitudeMeters?: number | undefined;
        speedMetersPerSecond?: number | undefined;
        courseDegrees?: number | undefined;
    } | null;
}>;
export type ResolutionPayload = z.infer<typeof resolutionPayload>;
/** Mirrors `sanitizeLawEnforcementRequestPayload()` output. */
export declare const lawEnforcementRequestPayload: z.ZodObject<{
    sessionId: z.ZodString;
    agencyName: z.ZodString;
    requesterName: z.ZodString;
    requesterTitle: z.ZodOptional<z.ZodEffects<z.ZodString, string | undefined, string>>;
    requesterEmail: z.ZodOptional<z.ZodEffects<z.ZodString, string | undefined, string>>;
    requesterPhone: z.ZodOptional<z.ZodEffects<z.ZodString, string | undefined, string>>;
    legalProcessType: z.ZodEnum<["warrant", "court_order", "subpoena", "emergency_disclosure_request", "other"]>;
    legalReference: z.ZodString;
    documentReference: z.ZodOptional<z.ZodEffects<z.ZodString, string | undefined, string>>;
    /** sanitizeDisclosureScope(): de-duplicated subset of disclosureScope. */
    requestedScope: z.ZodArray<z.ZodEnum<["last_known_location", "direction_of_travel", "redacted_trusted_contacts", "recent_trail"]>, "many">;
    /** `optionalString(urgency) || 'active_sos'`. */
    urgency: z.ZodString;
    notes: z.ZodOptional<z.ZodEffects<z.ZodString, string | undefined, string>>;
    receivedAt: z.ZodString;
}, "strip", z.ZodTypeAny, {
    sessionId: string;
    agencyName: string;
    requesterName: string;
    legalProcessType: "warrant" | "court_order" | "subpoena" | "emergency_disclosure_request" | "other";
    legalReference: string;
    requestedScope: ("last_known_location" | "direction_of_travel" | "redacted_trusted_contacts" | "recent_trail")[];
    urgency: string;
    receivedAt: string;
    requesterTitle?: string | undefined;
    requesterEmail?: string | undefined;
    requesterPhone?: string | undefined;
    documentReference?: string | undefined;
    notes?: string | undefined;
}, {
    sessionId: string;
    agencyName: string;
    requesterName: string;
    legalProcessType: "warrant" | "court_order" | "subpoena" | "emergency_disclosure_request" | "other";
    legalReference: string;
    requestedScope: ("last_known_location" | "direction_of_travel" | "redacted_trusted_contacts" | "recent_trail")[];
    urgency: string;
    receivedAt: string;
    requesterTitle?: string | undefined;
    requesterEmail?: string | undefined;
    requesterPhone?: string | undefined;
    documentReference?: string | undefined;
    notes?: string | undefined;
}>;
export type LawEnforcementRequestPayload = z.infer<typeof lawEnforcementRequestPayload>;
/** Mirrors `sanitizeLawEnforcementReviewPayload()` output. */
export declare const lawEnforcementReviewPayload: z.ZodObject<{
    legalRequestId: z.ZodString;
    /** decision must be 'approved' or 'denied'. */
    decision: z.ZodEnum<["approved", "denied"]>;
    /** sanitizeDisclosureScope(): de-duplicated subset of disclosureScope. */
    approvedScope: z.ZodArray<z.ZodEnum<["last_known_location", "direction_of_travel", "redacted_trusted_contacts", "recent_trail"]>, "many">;
    reviewNote: z.ZodString;
    /** null when no expiry supplied. */
    expiresAt: z.ZodNullable<z.ZodString>;
    reviewedAt: z.ZodString;
}, "strip", z.ZodTypeAny, {
    legalRequestId: string;
    decision: "approved" | "denied";
    approvedScope: ("last_known_location" | "direction_of_travel" | "redacted_trusted_contacts" | "recent_trail")[];
    reviewNote: string;
    expiresAt: string | null;
    reviewedAt: string;
}, {
    legalRequestId: string;
    decision: "approved" | "denied";
    approvedScope: ("last_known_location" | "direction_of_travel" | "redacted_trusted_contacts" | "recent_trail")[];
    reviewNote: string;
    expiresAt: string | null;
    reviewedAt: string;
}>;
export type LawEnforcementReviewPayload = z.infer<typeof lawEnforcementReviewPayload>;
//# sourceMappingURL=sos.d.ts.map