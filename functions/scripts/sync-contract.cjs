// Firebase deploys only the functions directory. Keep a generated copy of the
// shared runtime contract inside it so Cloud Build can install the dependency.
const fs = require('node:fs');
const path = require('node:path');

const contractRoot = path.resolve(__dirname, '../../packages/contract');
const vendorRoot = path.resolve(__dirname, '../vendor/contract');
const sourceDist = path.join(contractRoot, 'dist');

// A fresh release checkout may not have the ignored contract/dist output yet.
// In that case the committed generated vendor package is already deployable.
if (!fs.existsSync(path.join(sourceDist, 'index.js'))) {
  if (!fs.existsSync(path.join(vendorRoot, 'dist/index.js'))) {
    throw new Error('Build packages/contract before building functions.');
  }
  return;
}

fs.rmSync(vendorRoot, { recursive: true, force: true });
fs.mkdirSync(vendorRoot, { recursive: true });
fs.cpSync(sourceDist, path.join(vendorRoot, 'dist'), { recursive: true });

const sourcePackage = JSON.parse(fs.readFileSync(path.join(contractRoot, 'package.json'), 'utf8'));
const vendorPackage = {
  name: sourcePackage.name,
  version: sourcePackage.version,
  main: sourcePackage.main,
  types: sourcePackage.types,
  dependencies: sourcePackage.dependencies,
};
fs.writeFileSync(path.join(vendorRoot, 'package.json'), JSON.stringify(vendorPackage, null, 2) + '\n');
