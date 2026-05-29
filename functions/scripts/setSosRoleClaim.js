'use strict';

const { initializeApp, applicationDefault } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');

const ALLOWED_ROLES = new Set(['sosAdmin', 'careTeam', 'lawEnforcement']);

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const uid = args.uid;
  const role = args.role;
  const enabled = args.enable !== 'false';

  if (!uid || !role || !ALLOWED_ROLES.has(role)) {
    usage();
    process.exitCode = 1;
    return;
  }

  initializeApp({
    credential: applicationDefault(),
    projectId: args.project || process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT,
  });

  const auth = getAuth();
  const user = await auth.getUser(uid);
  const claims = { ...(user.customClaims || {}) };
  claims[role] = enabled;

  await auth.setCustomUserClaims(uid, claims);
  console.log(`${enabled ? 'Enabled' : 'Disabled'} ${role} for ${uid}`);
}

function parseArgs(argv) {
  const args = {};
  for (let index = 0; index < argv.length; index += 1) {
    const value = argv[index];
    if (!value.startsWith('--')) continue;
    const key = value.slice(2);
    args[key] = argv[index + 1] && !argv[index + 1].startsWith('--') ? argv[index + 1] : 'true';
  }
  return args;
}

function usage() {
  console.error([
    'Usage:',
    '  GOOGLE_APPLICATION_CREDENTIALS=/path/service-account.json npm run set-sos-claim -- --uid UID --role careTeam --project pulsetracker-0000',
    '',
    'Roles:',
    '  sosAdmin, careTeam, lawEnforcement',
    '',
    'Disable a role:',
    '  npm run set-sos-claim -- --uid UID --role careTeam --enable false --project pulsetracker-0000',
  ].join('\n'));
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
