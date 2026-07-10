import { cellToLatLng, cellToParent, latLngToCell } from 'h3-js';
import { Timestamp } from './admin';
import { encodeGeohash } from '../geohash';
import { withoutUndefined } from './util';

const DEFAULT_H3_RESOLUTION = 8;
const DEFAULT_H3_FALLBACK_RESOLUTION = 7;
const DEFAULT_K_ANONYMITY_THRESHOLD = 3;
const MAX_EXISTING_REPORTS_TO_CONSIDER = 50;

type Transaction = {
  get(refOrQuery: any): Promise<any>;
  update(ref: any, data: any): any;
};

type PublicLocationDecision = {
  status: 'revealed' | 'pending_k_anonymity';
  latitude?: number;
  longitude?: number;
  geohash?: string;
  publicH3Cell?: string;
  publicH3Resolution?: number;
  privateH3Cell: string;
  privateH3Resolution: number;
  privateH3ParentCell: string;
  privateH3ParentResolution: number;
  distinctReporterCount: number;
  threshold: number;
  existingReportIdsToReveal: string[];
};

export function incidentLocationPrivacy(latitude: number, longitude: number) {
  const policy = h3Policy();
  const privateH3Cell = latLngToCell(latitude, longitude, policy.resolution);
  const privateH3ParentCell = cellToParent(privateH3Cell, policy.fallbackResolution);

  return {
    privateH3Cell,
    privateH3Resolution: policy.resolution,
    privateH3ParentCell,
    privateH3ParentResolution: policy.fallbackResolution,
    threshold: policy.threshold,
  };
}

export async function publicLocationDecisionForIncident({
  transaction,
  reportsCollection,
  uid,
  now,
  latitude,
  longitude,
}: {
  transaction: Transaction;
  reportsCollection: any;
  uid: string;
  now: Date;
  latitude: number;
  longitude: number;
}): Promise<PublicLocationDecision> {
  const privacy = incidentLocationPrivacy(latitude, longitude);
  const exact = await revealCandidate({
    transaction,
    reportsCollection,
    field: 'privateH3Cell',
    cell: privacy.privateH3Cell,
    resolution: privacy.privateH3Resolution,
    uid,
    now,
    threshold: privacy.threshold,
  });

  if (exact.revealed) {
    return revealedDecision({ ...privacy, ...exact });
  }

  const parent = await revealCandidate({
    transaction,
    reportsCollection,
    field: 'privateH3ParentCell',
    cell: privacy.privateH3ParentCell,
    resolution: privacy.privateH3ParentResolution,
    uid,
    now,
    threshold: privacy.threshold,
  });

  if (parent.revealed) {
    return revealedDecision({ ...privacy, ...parent });
  }

  const [previewLatitude, previewLongitude] = cellToLatLng(privacy.privateH3ParentCell);

  return {
    status: 'pending_k_anonymity',
    latitude: previewLatitude,
    longitude: previewLongitude,
    geohash: encodeGeohash(previewLatitude, previewLongitude),
    publicH3Cell: privacy.privateH3ParentCell,
    publicH3Resolution: privacy.privateH3ParentResolution,
    ...privacy,
    distinctReporterCount: Math.max(exact.distinctReporterCount, parent.distinctReporterCount),
    existingReportIdsToReveal: [],
  };
}

export function publicLocationFields(decision: PublicLocationDecision) {
  const pendingPreview = decision.status === 'pending_k_anonymity'
    ? pendingPreviewFields(decision)
    : {};
  return withoutUndefined({
    latitude: decision.latitude,
    longitude: decision.longitude,
    geohash: decision.geohash,
    public_h3_cell: decision.publicH3Cell,
    public_h3_resolution: decision.publicH3Resolution,
    ...pendingPreview,
    location_reveal_status: decision.status,
    location_privacy_policy: 'h3_k_anonymous',
    k_anonymity_threshold: decision.threshold,
    k_anonymity_distinct_reporters: decision.distinctReporterCount,
  });
}

export function revealExistingPublicIncidentLocations(transaction: Transaction, decision: PublicLocationDecision, publicCollection: any) {
  if (decision.status !== 'revealed') return;
  const fields = withoutUndefined({
    latitude: decision.latitude,
    longitude: decision.longitude,
    geohash: decision.geohash,
    public_h3_cell: decision.publicH3Cell,
    public_h3_resolution: decision.publicH3Resolution,
    location_reveal_status: decision.status,
    location_privacy_policy: 'h3_k_anonymous',
    k_anonymity_threshold: decision.threshold,
    k_anonymity_distinct_reporters: decision.distinctReporterCount,
  });

  for (const reportId of decision.existingReportIdsToReveal) {
    transaction.update(publicCollection.doc(reportId), fields);
  }
}

async function revealCandidate({
  transaction,
  reportsCollection,
  field,
  cell,
  resolution,
  uid,
  now,
  threshold,
}: {
  transaction: Transaction;
  reportsCollection: any;
  field: string;
  cell: string;
  resolution: number;
  uid: string;
  now: Date;
  threshold: number;
}) {
  const query = reportsCollection
    .where(field, '==', cell)
    .where('deleteAfter', '>', Timestamp.fromDate(now))
    .limit(MAX_EXISTING_REPORTS_TO_CONSIDER);
  const snap = await transaction.get(query);
  const reporterUids = new Set<string>([uid]);
  const existingReportIdsToReveal: string[] = [];

  for (const doc of snap.docs || []) {
    const report = doc.data();
    if (report?.ownerUid) {
      reporterUids.add(report.ownerUid);
      existingReportIdsToReveal.push(doc.id);
    }
  }

  return {
    revealed: reporterUids.size >= threshold,
    cell,
    resolution,
    distinctReporterCount: reporterUids.size,
    existingReportIdsToReveal,
  };
}

function pendingPreviewFields(decision: PublicLocationDecision) {
  if (decision.latitude != null && decision.longitude != null && decision.publicH3Cell) {
    return {};
  }

  const [latitude, longitude] = cellToLatLng(decision.privateH3ParentCell);
  return {
    latitude,
    longitude,
    geohash: encodeGeohash(latitude, longitude),
    public_h3_cell: decision.privateH3ParentCell,
    public_h3_resolution: decision.privateH3ParentResolution,
  };
}

function revealedDecision(decision: any): PublicLocationDecision {
  const [latitude, longitude] = cellToLatLng(decision.cell);
  return {
    status: 'revealed',
    latitude,
    longitude,
    geohash: encodeGeohash(latitude, longitude),
    publicH3Cell: decision.cell,
    publicH3Resolution: decision.resolution,
    privateH3Cell: decision.privateH3Cell,
    privateH3Resolution: decision.privateH3Resolution,
    privateH3ParentCell: decision.privateH3ParentCell,
    privateH3ParentResolution: decision.privateH3ParentResolution,
    distinctReporterCount: decision.distinctReporterCount,
    threshold: decision.threshold,
    existingReportIdsToReveal: decision.existingReportIdsToReveal,
  };
}

function h3Policy() {
  const resolution = integerEnv('PULSETRACKR_PUBLIC_H3_RESOLUTION', DEFAULT_H3_RESOLUTION);
  const fallbackResolution = Math.min(
    integerEnv('PULSETRACKR_PUBLIC_H3_FALLBACK_RESOLUTION', DEFAULT_H3_FALLBACK_RESOLUTION),
    resolution,
  );
  const threshold = Math.max(2, integerEnv('PULSETRACKR_K_ANONYMITY_THRESHOLD', DEFAULT_K_ANONYMITY_THRESHOLD));

  return { resolution, fallbackResolution, threshold };
}

function integerEnv(name: string, fallback: number): number {
  const value = Number(process.env[name]);
  return Number.isInteger(value) ? value : fallback;
}
