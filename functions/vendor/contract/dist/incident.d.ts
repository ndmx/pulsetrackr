import { z } from 'zod';
import type { IncidentCategory } from './enums';
export declare const incidentSubtype: z.ZodEnum<["armed_robbery", "kidnapping", "gunshots", "carjacking", "one_chance", "suspicious_activity", "checkpoint_issue", "communal_clash", "crash", "roadblock", "gridlock", "flooded_road", "bad_road", "broken_down_vehicle", "building_fire", "market_fire", "gas_leak", "explosion", "electrical_fire", "pipeline_fire", "medical_emergency", "suspected_outbreak", "hospital_issue", "medicine_shortage", "contaminated_water", "food_poisoning", "flooding", "heavy_rain", "storm_damage", "erosion_landslide", "drought_water_scarcity", "power_outage", "water_outage", "fuel_scarcity", "bridge_damage", "rail_issue", "building_collapse", "bridge_collapse", "road_collapse", "unsafe_building", "fallen_power_line", "missing_person", "local_warning", "safe_route", "community_watch", "public_gathering", "aid_needed"]>;
export type IncidentSubtype = z.infer<typeof incidentSubtype>;
export declare const subtypesByCategory: Record<IncidentCategory, IncidentSubtype[]>;
/**
 * The default subtype for a category — the first subtype in declaration order.
 * Mirrors IncidentSubtype.defaultSubtype(for:) (app/Incident.swift:266), which falls
 * back to `.localWarning` when a category has no subtypes (cannot happen here, but the
 * fallback is kept for parity).
 */
export declare function defaultSubtypeForCategory(category: IncidentCategory): IncidentSubtype;
export declare const incidentEvidenceKind: z.ZodEnum<["photo", "voice"]>;
export type IncidentEvidenceKind = z.infer<typeof incidentEvidenceKind>;
export declare const incidentEvidence: z.ZodObject<{
    kind: z.ZodEnum<["photo", "voice"]>;
    storage_path: z.ZodString;
    content_type: z.ZodString;
    size_bytes: z.ZodNumber;
    duration_seconds: z.ZodOptional<z.ZodNumber>;
}, "strip", z.ZodTypeAny, {
    kind: "photo" | "voice";
    storage_path: string;
    content_type: string;
    size_bytes: number;
    duration_seconds?: number | undefined;
}, {
    kind: "photo" | "voice";
    storage_path: string;
    content_type: string;
    size_bytes: number;
    duration_seconds?: number | undefined;
}>;
export type IncidentEvidence = z.infer<typeof incidentEvidence>;
export declare const submitIncidentPayload: z.ZodEffects<z.ZodObject<{
    title: z.ZodString;
    summary: z.ZodString;
    category: z.ZodEnum<["security", "traffic", "fire", "medical", "weather", "utilities", "structure", "community"]>;
    subtype: z.ZodEnum<["armed_robbery", "kidnapping", "gunshots", "carjacking", "one_chance", "suspicious_activity", "checkpoint_issue", "communal_clash", "crash", "roadblock", "gridlock", "flooded_road", "bad_road", "broken_down_vehicle", "building_fire", "market_fire", "gas_leak", "explosion", "electrical_fire", "pipeline_fire", "medical_emergency", "suspected_outbreak", "hospital_issue", "medicine_shortage", "contaminated_water", "food_poisoning", "flooding", "heavy_rain", "storm_damage", "erosion_landslide", "drought_water_scarcity", "power_outage", "water_outage", "fuel_scarcity", "bridge_damage", "rail_issue", "building_collapse", "bridge_collapse", "road_collapse", "unsafe_building", "fallen_power_line", "missing_person", "local_warning", "safe_route", "community_watch", "public_gathering", "aid_needed"]>;
    severity: z.ZodEnum<["Low", "Medium", "High", "Urgent"]>;
    status: z.ZodEnum<["Active", "Watching", "Resolved"]>;
    neighborhood: z.ZodString;
    latitude: z.ZodOptional<z.ZodNumber>;
    longitude: z.ZodOptional<z.ZodNumber>;
    use_approximate_location: z.ZodBoolean;
    client_ref: z.ZodString;
    source: z.ZodString;
    evidence: z.ZodArray<z.ZodObject<{
        kind: z.ZodEnum<["photo", "voice"]>;
        storage_path: z.ZodString;
        content_type: z.ZodString;
        size_bytes: z.ZodNumber;
        duration_seconds: z.ZodOptional<z.ZodNumber>;
    }, "strip", z.ZodTypeAny, {
        kind: "photo" | "voice";
        storage_path: string;
        content_type: string;
        size_bytes: number;
        duration_seconds?: number | undefined;
    }, {
        kind: "photo" | "voice";
        storage_path: string;
        content_type: string;
        size_bytes: number;
        duration_seconds?: number | undefined;
    }>, "many">;
}, "strip", z.ZodTypeAny, {
    status: "Active" | "Watching" | "Resolved";
    title: string;
    summary: string;
    category: "security" | "traffic" | "fire" | "medical" | "weather" | "utilities" | "structure" | "community";
    subtype: "armed_robbery" | "kidnapping" | "gunshots" | "carjacking" | "one_chance" | "suspicious_activity" | "checkpoint_issue" | "communal_clash" | "crash" | "roadblock" | "gridlock" | "flooded_road" | "bad_road" | "broken_down_vehicle" | "building_fire" | "market_fire" | "gas_leak" | "explosion" | "electrical_fire" | "pipeline_fire" | "medical_emergency" | "suspected_outbreak" | "hospital_issue" | "medicine_shortage" | "contaminated_water" | "food_poisoning" | "flooding" | "heavy_rain" | "storm_damage" | "erosion_landslide" | "drought_water_scarcity" | "power_outage" | "water_outage" | "fuel_scarcity" | "bridge_damage" | "rail_issue" | "building_collapse" | "bridge_collapse" | "road_collapse" | "unsafe_building" | "fallen_power_line" | "missing_person" | "local_warning" | "safe_route" | "community_watch" | "public_gathering" | "aid_needed";
    severity: "Low" | "Medium" | "High" | "Urgent";
    neighborhood: string;
    use_approximate_location: boolean;
    client_ref: string;
    source: string;
    evidence: {
        kind: "photo" | "voice";
        storage_path: string;
        content_type: string;
        size_bytes: number;
        duration_seconds?: number | undefined;
    }[];
    latitude?: number | undefined;
    longitude?: number | undefined;
}, {
    status: "Active" | "Watching" | "Resolved";
    title: string;
    summary: string;
    category: "security" | "traffic" | "fire" | "medical" | "weather" | "utilities" | "structure" | "community";
    subtype: "armed_robbery" | "kidnapping" | "gunshots" | "carjacking" | "one_chance" | "suspicious_activity" | "checkpoint_issue" | "communal_clash" | "crash" | "roadblock" | "gridlock" | "flooded_road" | "bad_road" | "broken_down_vehicle" | "building_fire" | "market_fire" | "gas_leak" | "explosion" | "electrical_fire" | "pipeline_fire" | "medical_emergency" | "suspected_outbreak" | "hospital_issue" | "medicine_shortage" | "contaminated_water" | "food_poisoning" | "flooding" | "heavy_rain" | "storm_damage" | "erosion_landslide" | "drought_water_scarcity" | "power_outage" | "water_outage" | "fuel_scarcity" | "bridge_damage" | "rail_issue" | "building_collapse" | "bridge_collapse" | "road_collapse" | "unsafe_building" | "fallen_power_line" | "missing_person" | "local_warning" | "safe_route" | "community_watch" | "public_gathering" | "aid_needed";
    severity: "Low" | "Medium" | "High" | "Urgent";
    neighborhood: string;
    use_approximate_location: boolean;
    client_ref: string;
    source: string;
    evidence: {
        kind: "photo" | "voice";
        storage_path: string;
        content_type: string;
        size_bytes: number;
        duration_seconds?: number | undefined;
    }[];
    latitude?: number | undefined;
    longitude?: number | undefined;
}>, {
    status: "Active" | "Watching" | "Resolved";
    title: string;
    summary: string;
    category: "security" | "traffic" | "fire" | "medical" | "weather" | "utilities" | "structure" | "community";
    subtype: "armed_robbery" | "kidnapping" | "gunshots" | "carjacking" | "one_chance" | "suspicious_activity" | "checkpoint_issue" | "communal_clash" | "crash" | "roadblock" | "gridlock" | "flooded_road" | "bad_road" | "broken_down_vehicle" | "building_fire" | "market_fire" | "gas_leak" | "explosion" | "electrical_fire" | "pipeline_fire" | "medical_emergency" | "suspected_outbreak" | "hospital_issue" | "medicine_shortage" | "contaminated_water" | "food_poisoning" | "flooding" | "heavy_rain" | "storm_damage" | "erosion_landslide" | "drought_water_scarcity" | "power_outage" | "water_outage" | "fuel_scarcity" | "bridge_damage" | "rail_issue" | "building_collapse" | "bridge_collapse" | "road_collapse" | "unsafe_building" | "fallen_power_line" | "missing_person" | "local_warning" | "safe_route" | "community_watch" | "public_gathering" | "aid_needed";
    severity: "Low" | "Medium" | "High" | "Urgent";
    neighborhood: string;
    use_approximate_location: boolean;
    client_ref: string;
    source: string;
    evidence: {
        kind: "photo" | "voice";
        storage_path: string;
        content_type: string;
        size_bytes: number;
        duration_seconds?: number | undefined;
    }[];
    latitude?: number | undefined;
    longitude?: number | undefined;
}, {
    status: "Active" | "Watching" | "Resolved";
    title: string;
    summary: string;
    category: "security" | "traffic" | "fire" | "medical" | "weather" | "utilities" | "structure" | "community";
    subtype: "armed_robbery" | "kidnapping" | "gunshots" | "carjacking" | "one_chance" | "suspicious_activity" | "checkpoint_issue" | "communal_clash" | "crash" | "roadblock" | "gridlock" | "flooded_road" | "bad_road" | "broken_down_vehicle" | "building_fire" | "market_fire" | "gas_leak" | "explosion" | "electrical_fire" | "pipeline_fire" | "medical_emergency" | "suspected_outbreak" | "hospital_issue" | "medicine_shortage" | "contaminated_water" | "food_poisoning" | "flooding" | "heavy_rain" | "storm_damage" | "erosion_landslide" | "drought_water_scarcity" | "power_outage" | "water_outage" | "fuel_scarcity" | "bridge_damage" | "rail_issue" | "building_collapse" | "bridge_collapse" | "road_collapse" | "unsafe_building" | "fallen_power_line" | "missing_person" | "local_warning" | "safe_route" | "community_watch" | "public_gathering" | "aid_needed";
    severity: "Low" | "Medium" | "High" | "Urgent";
    neighborhood: string;
    use_approximate_location: boolean;
    client_ref: string;
    source: string;
    evidence: {
        kind: "photo" | "voice";
        storage_path: string;
        content_type: string;
        size_bytes: number;
        duration_seconds?: number | undefined;
    }[];
    latitude?: number | undefined;
    longitude?: number | undefined;
}>;
export type SubmitIncidentPayload = z.infer<typeof submitIncidentPayload>;
export declare const incidentEvidenceSummary: z.ZodObject<{
    photo_count: z.ZodNumber;
    voice_count: z.ZodNumber;
}, "strip", z.ZodTypeAny, {
    photo_count: number;
    voice_count: number;
}, {
    photo_count: number;
    voice_count: number;
}>;
export type IncidentEvidenceSummary = z.infer<typeof incidentEvidenceSummary>;
export declare const reporterTrustTier: z.ZodEnum<["standard", "trusted"]>;
export type ReporterTrustTier = z.infer<typeof reporterTrustTier>;
export declare const publicIncident: z.ZodObject<{
    title: z.ZodString;
    summary: z.ZodString;
    category: z.ZodEnum<["security", "traffic", "fire", "medical", "weather", "utilities", "structure", "community"]>;
    subtype: z.ZodEnum<["armed_robbery", "kidnapping", "gunshots", "carjacking", "one_chance", "suspicious_activity", "checkpoint_issue", "communal_clash", "crash", "roadblock", "gridlock", "flooded_road", "bad_road", "broken_down_vehicle", "building_fire", "market_fire", "gas_leak", "explosion", "electrical_fire", "pipeline_fire", "medical_emergency", "suspected_outbreak", "hospital_issue", "medicine_shortage", "contaminated_water", "food_poisoning", "flooding", "heavy_rain", "storm_damage", "erosion_landslide", "drought_water_scarcity", "power_outage", "water_outage", "fuel_scarcity", "bridge_damage", "rail_issue", "building_collapse", "bridge_collapse", "road_collapse", "unsafe_building", "fallen_power_line", "missing_person", "local_warning", "safe_route", "community_watch", "public_gathering", "aid_needed"]>;
    severity: z.ZodEnum<["Low", "Medium", "High", "Urgent"]>;
    status: z.ZodEnum<["Active", "Watching", "Resolved"]>;
    neighborhood: z.ZodString;
    latitude: z.ZodOptional<z.ZodNumber>;
    longitude: z.ZodOptional<z.ZodNumber>;
    geohash: z.ZodOptional<z.ZodString>;
    public_h3_cell: z.ZodOptional<z.ZodString>;
    public_h3_resolution: z.ZodOptional<z.ZodNumber>;
    location_reveal_status: z.ZodOptional<z.ZodEnum<["revealed", "pending_k_anonymity"]>>;
    location_privacy_policy: z.ZodOptional<z.ZodEnum<["h3_k_anonymous"]>>;
    k_anonymity_threshold: z.ZodOptional<z.ZodNumber>;
    k_anonymity_distinct_reporters: z.ZodOptional<z.ZodNumber>;
    confirmations: z.ZodNumber;
    disputes: z.ZodNumber;
    unsafe_reports: z.ZodNumber;
    blocked_reports: z.ZodNumber;
    cleared_reports: z.ZodNumber;
    official_updates: z.ZodNumber;
    evidence_summary: z.ZodOptional<z.ZodObject<{
        photo_count: z.ZodNumber;
        voice_count: z.ZodNumber;
    }, "strip", z.ZodTypeAny, {
        photo_count: number;
        voice_count: number;
    }, {
        photo_count: number;
        voice_count: number;
    }>>;
    reported_at: z.ZodString;
    source: z.ZodOptional<z.ZodString>;
    /** Reporter reputation tier at submit time — tier only, never an identity. */
    reporter_trust_tier: z.ZodOptional<z.ZodEnum<["standard", "trusted"]>>;
    /** Attribution for officially ingested incidents (e.g. a weather-alert feed). */
    official_source_name: z.ZodOptional<z.ZodString>;
}, "strip", z.ZodTypeAny, {
    status: "Active" | "Watching" | "Resolved";
    title: string;
    summary: string;
    category: "security" | "traffic" | "fire" | "medical" | "weather" | "utilities" | "structure" | "community";
    subtype: "armed_robbery" | "kidnapping" | "gunshots" | "carjacking" | "one_chance" | "suspicious_activity" | "checkpoint_issue" | "communal_clash" | "crash" | "roadblock" | "gridlock" | "flooded_road" | "bad_road" | "broken_down_vehicle" | "building_fire" | "market_fire" | "gas_leak" | "explosion" | "electrical_fire" | "pipeline_fire" | "medical_emergency" | "suspected_outbreak" | "hospital_issue" | "medicine_shortage" | "contaminated_water" | "food_poisoning" | "flooding" | "heavy_rain" | "storm_damage" | "erosion_landslide" | "drought_water_scarcity" | "power_outage" | "water_outage" | "fuel_scarcity" | "bridge_damage" | "rail_issue" | "building_collapse" | "bridge_collapse" | "road_collapse" | "unsafe_building" | "fallen_power_line" | "missing_person" | "local_warning" | "safe_route" | "community_watch" | "public_gathering" | "aid_needed";
    severity: "Low" | "Medium" | "High" | "Urgent";
    neighborhood: string;
    confirmations: number;
    disputes: number;
    unsafe_reports: number;
    blocked_reports: number;
    cleared_reports: number;
    official_updates: number;
    reported_at: string;
    latitude?: number | undefined;
    longitude?: number | undefined;
    source?: string | undefined;
    geohash?: string | undefined;
    public_h3_cell?: string | undefined;
    public_h3_resolution?: number | undefined;
    location_reveal_status?: "revealed" | "pending_k_anonymity" | undefined;
    location_privacy_policy?: "h3_k_anonymous" | undefined;
    k_anonymity_threshold?: number | undefined;
    k_anonymity_distinct_reporters?: number | undefined;
    evidence_summary?: {
        photo_count: number;
        voice_count: number;
    } | undefined;
    reporter_trust_tier?: "standard" | "trusted" | undefined;
    official_source_name?: string | undefined;
}, {
    status: "Active" | "Watching" | "Resolved";
    title: string;
    summary: string;
    category: "security" | "traffic" | "fire" | "medical" | "weather" | "utilities" | "structure" | "community";
    subtype: "armed_robbery" | "kidnapping" | "gunshots" | "carjacking" | "one_chance" | "suspicious_activity" | "checkpoint_issue" | "communal_clash" | "crash" | "roadblock" | "gridlock" | "flooded_road" | "bad_road" | "broken_down_vehicle" | "building_fire" | "market_fire" | "gas_leak" | "explosion" | "electrical_fire" | "pipeline_fire" | "medical_emergency" | "suspected_outbreak" | "hospital_issue" | "medicine_shortage" | "contaminated_water" | "food_poisoning" | "flooding" | "heavy_rain" | "storm_damage" | "erosion_landslide" | "drought_water_scarcity" | "power_outage" | "water_outage" | "fuel_scarcity" | "bridge_damage" | "rail_issue" | "building_collapse" | "bridge_collapse" | "road_collapse" | "unsafe_building" | "fallen_power_line" | "missing_person" | "local_warning" | "safe_route" | "community_watch" | "public_gathering" | "aid_needed";
    severity: "Low" | "Medium" | "High" | "Urgent";
    neighborhood: string;
    confirmations: number;
    disputes: number;
    unsafe_reports: number;
    blocked_reports: number;
    cleared_reports: number;
    official_updates: number;
    reported_at: string;
    latitude?: number | undefined;
    longitude?: number | undefined;
    source?: string | undefined;
    geohash?: string | undefined;
    public_h3_cell?: string | undefined;
    public_h3_resolution?: number | undefined;
    location_reveal_status?: "revealed" | "pending_k_anonymity" | undefined;
    location_privacy_policy?: "h3_k_anonymous" | undefined;
    k_anonymity_threshold?: number | undefined;
    k_anonymity_distinct_reporters?: number | undefined;
    evidence_summary?: {
        photo_count: number;
        voice_count: number;
    } | undefined;
    reporter_trust_tier?: "standard" | "trusted" | undefined;
    official_source_name?: string | undefined;
}>;
export type PublicIncident = z.infer<typeof publicIncident>;
//# sourceMappingURL=incident.d.ts.map