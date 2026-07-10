'use strict';

// Codegen pipeline: zod schemas -> JSON Schema (draft-07) -> Swift Codable types.
//   1. Bundle the named contract schemas into one JSON Schema `definitions` document.
//   2. Run quicktype to emit Swift structs/enums into the app target.
// The app/ folder is an Xcode synchronized root group, so the emitted .swift file
// auto-joins the app target — no project.pbxproj edits needed.
//
// Run with: npm run codegen   (which builds dist first, then invokes this script).

const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const { z } = require('zod');
const { zodToJsonSchema } = require('zod-to-json-schema');
const C = require('../dist/index.js');

const CODEGEN_DIR = __dirname;
const SCHEMA_FILE = path.join(CODEGEN_DIR, 'pulsetrackr-contract.schema.json');
const SWIFT_OUT = path.resolve(CODEGEN_DIR, '../../../app/Generated/PulseTrackrContract.generated.swift');

// Definition name (PascalCase Swift type) -> zod schema. Shared sub-schemas referenced
// by identity (e.g. incidentEvidence inside submitIncidentPayload) become $refs so each
// type is emitted once.
const definitions = {
  // ── enums ──
  IncidentCategory: C.incidentCategory,
  IncidentSeverity: C.incidentSeverity,
  IncidentStatus: C.incidentStatus,
  IncidentSubtype: C.incidentSubtype,
  CommunitySignal: C.communitySignal,
  IncidentConcernReason: C.incidentConcernReason,
  IncidentEvidenceKind: C.incidentEvidenceKind,
  PrivilegedRole: C.privilegedRole,
  DisclosureScope: C.disclosureScope,
  LegalProcessType: C.legalProcessType,
  NotificationChannel: C.notificationChannel,
  ResolutionReason: C.resolutionReason,
  ReporterTrustTier: C.reporterTrustTier,
  PushPlatform: C.pushPlatform,
  // ── incident ──
  IncidentEvidence: C.incidentEvidence,
  IncidentEvidenceSummary: C.incidentEvidenceSummary,
  SubmitIncidentPayload: C.submitIncidentPayload,
  PublicIncident: C.publicIncident,
  IncidentState: C.incidentState,
  // ── sos ──
  SOSLocation: C.sosLocation,
  DirectionOfTravel: C.directionOfTravel,
  SOSDevice: C.sosDevice,
  PrivacyPolicy: C.privacyPolicy,
  TrustedContact: C.trustedContact,
  RedactedTrustedContact: C.redactedTrustedContact,
  ActivationPayload: C.activationPayload,
  LocationUpdatePayload: C.locationUpdatePayload,
  ResolutionPayload: C.resolutionPayload,
  LawEnforcementRequestPayload: C.lawEnforcementRequestPayload,
  LawEnforcementReviewPayload: C.lawEnforcementReviewPayload,
  // ── push ──
  RegisterPushDevicePayload: C.registerPushDevicePayload,
  PushDeviceRecord: C.pushDeviceRecord,
};

// Sanity: every name must resolve to a defined schema (catches a renamed/removed export).
const missing = Object.entries(definitions).filter(([, schema]) => schema === undefined);
if (missing.length > 0) {
  throw new Error(`Contract export(s) missing for: ${missing.map(([name]) => name).join(', ')}`);
}

// Emit all definitions into one document. quicktype only generates types REACHABLE
// from the root, so the root references every definition via $ref; the resulting
// wrapper struct is stripped from the Swift afterward.
const bundle = zodToJsonSchema(z.object({}), { definitions, $refStrategy: 'root' });
const doc = {
  $schema: 'http://json-schema.org/draft-07/schema#',
  title: 'PulseTrackrContractRoot',
  type: 'object',
  properties: Object.fromEntries(
    Object.keys(definitions).map((name) => [name, { $ref: `#/definitions/${name}` }]),
  ),
  definitions: bundle.definitions,
};
fs.writeFileSync(SCHEMA_FILE, `${JSON.stringify(doc, null, 2)}\n`);
console.log(`✓ JSON Schema: ${path.relative(process.cwd(), SCHEMA_FILE)} (${Object.keys(definitions).length} types)`);

// quicktype: schema -> Swift. Default (NOT --just-types) so each type gets Codable
// conformance + CodingKeys that map the snake_case wire keys (e.g. client_ref). The
// `--top-level` wrapper is a reachability anchor we strip below.
execFileSync(
  'npx',
  [
    '--yes', 'quicktype',
    '--src-lang', 'schema',
    '--lang', 'swift',
    '--struct-or-class', 'struct',
    '--swift-5-support',
    '--top-level', 'PulseTrackrContractRoot',
    '-o', SWIFT_OUT,
    SCHEMA_FILE,
  ],
  { stdio: 'inherit', cwd: CODEGEN_DIR },
);

// Post-process: drop quicktype's leading comment block, the wrapper root type, and
// its convenience extension; then prepend our generated-file banner.
let swift = fs.readFileSync(SWIFT_OUT, 'utf8');

// Slice from the first import/declaration to drop quicktype's header comments (which
// reference the wrapper root type we're about to remove).
const startMatch = swift.match(/^(import |(public )?(struct|enum|extension) )/m);
if (startMatch && startMatch.index !== undefined) {
  swift = swift.slice(startMatch.index);
}

// Brace-aware removal of any top-level `struct|enum|extension <name>` block (plus its
// leading `// MARK: - <name>` comment). Used to delete the wrapper root and its
// extension, whose bodies contain nested braces (CodingKeys / helper methods).
function removeDecl(source, name) {
  const header = new RegExp(`(?:// MARK: - ${name}\\n)?(?:public )?(?:struct|enum|extension) ${name}\\b[^{]*\\{`, 'g');
  let result = source;
  for (;;) {
    const match = header.exec(result);
    if (!match) break;
    let depth = 0;
    let end = -1;
    for (let i = match.index + match[0].length - 1; i < result.length; i += 1) {
      const ch = result[i];
      if (ch === '{') depth += 1;
      else if (ch === '}') {
        depth -= 1;
        if (depth === 0) { end = i + 1; break; }
      }
    }
    if (end === -1) break;
    result = result.slice(0, match.index) + result.slice(end).replace(/^\n+/, '\n');
    header.lastIndex = 0;
  }
  return result;
}
swift = removeDecl(swift, 'PulseTrackrContractRoot');
// Drop any orphan line still referencing the stripped wrapper (e.g. quicktype's
// "// MARK: PulseTrackrContractRoot convenience initializers" comment). No real type
// references the wrapper, so this is safe.
swift = swift.split('\n').filter((line) => !line.includes('PulseTrackrContractRoot')).join('\n');

// Remove every top-level `extension`/`func` block. quicktype emits convenience
// initializers (init(data:), jsonData()) as file-scope extensions plus newJSONDecoder/
// newJSONEncoder helpers — none of which are valid inside the namespace enum we wrap
// with below. The Codable conformance + CodingKeys live on the structs themselves, so
// JSON (de)coding still works without these helpers.
function removeTopLevelBlocks(source, keyword) {
  const header = new RegExp(`^(?:public )?${keyword} [^\\n{]*\\{`, 'm');
  let result = source;
  for (;;) {
    const match = header.exec(result);
    if (!match) break;
    let depth = 0;
    let end = -1;
    for (let i = match.index + match[0].length - 1; i < result.length; i += 1) {
      if (result[i] === '{') depth += 1;
      else if (result[i] === '}') {
        depth -= 1;
        if (depth === 0) { end = i + 1; break; }
      }
    }
    if (end === -1) break;
    result = result.slice(0, match.index) + result.slice(end);
  }
  return result;
}
swift = removeTopLevelBlocks(swift, 'extension');
swift = removeTopLevelBlocks(swift, 'func');
// Drop the now-orphaned MARK comments and the helper-section header.
swift = swift.split('\n')
  .filter((line) => !line.includes('convenience initializers and mutators'))
  .filter((line) => !line.includes('Encode/decode helpers'))
  .filter((line) => !line.includes('Helper functions for creating encoders and decoders'))
  .join('\n');

// Wrap all generated types in a namespace enum so they don't collide with the app's
// own domain enums (IncidentCategory, IncidentSeverity, ...). `import` statements must
// stay at file scope, so split them out before wrapping. Internal cross-references
// (e.g. SubmitIncidentPayload -> IncidentEvidence) still resolve unqualified within the
// enclosing enum; callers use ContractDTO.<Type>.
const NAMESPACE = 'ContractDTO';
const lines = swift.trim().split('\n');
const importLines = lines.filter((line) => line.startsWith('import '));
const bodyLines = lines.filter((line) => !line.startsWith('import '));
const generatedSwiftHelpers = `
// MARK: - Generated Incident State Machine
static func applySignal(_ state: IncidentState, signal: CommunitySignal) -> IncidentState {
    var confirmations = state.confirmations
    var disputes = state.disputes
    var unsafeReports = state.unsafeReports
    var blockedReports = state.blockedReports
    var clearedReports = state.clearedReports
    var status = state.status
    var severity = state.severity

    switch signal {
    case .seen:
        confirmations += 1
    case .notSeen:
        disputes += 1
        if status == .active, disputes >= confirmations {
            status = .watching
        }
    case .unsafe:
        unsafeReports += 1
        status = .active
        if severity != .urgent {
            severity = .high
        }
    case .roadBlocked:
        blockedReports += 1
        if severity == .low {
            severity = .medium
        }
    case .cleared:
        clearedReports += 1
        status = clearedReports >= 3 ? .resolved : .watching
    }

    return IncidentState(
        blockedReports: blockedReports,
        clearedReports: clearedReports,
        confirmations: confirmations,
        disputes: disputes,
        severity: severity,
        status: status,
        unsafeReports: unsafeReports
    )
}
`;
const body = `${bodyLines.join('\n').trim()}\n\n${generatedSwiftHelpers.trim()}`;

const banner = [
  '// Generated by @pulsetrackr/contract — DO NOT EDIT BY HAND.',
  '// Source of truth: packages/contract/src/*.ts',
  '// Regenerate with: cd packages/contract && npm run codegen',
  '',
  '',
].join('\n');

swift = `${banner}${importLines.join('\n')}\n\n`
  + `/// Wire DTOs generated from the shared contract. Namespaced to avoid colliding with\n`
  + `/// the app's domain enums; map between them at the remote-store boundary.\n`
  + `enum ${NAMESPACE} {\n${body}\n}\n`;
fs.writeFileSync(SWIFT_OUT, swift);
console.log(`✓ Swift: ${path.relative(process.cwd(), SWIFT_OUT)} (namespace: ${NAMESPACE})`);
