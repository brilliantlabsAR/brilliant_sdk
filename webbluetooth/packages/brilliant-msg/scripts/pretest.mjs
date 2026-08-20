// Ensure the bundles the tests import actually exist and are current.
//
// The unit tests import ../dist/brilliant-msg.es.js (node can't run the TS
// sources directly), and building it needs the locally-linked sibling
// ../brilliant-ble to have been built too. In a fresh checkout neither dist
// exists, which used to make `npm test` fail with a cryptic
// "MagCalibration is not a constructor".
import { existsSync } from 'node:fs';
import { execSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const run = (cmd, cwd) => execSync(cmd, { cwd, stdio: 'inherit' });

const msgDir = fileURLToPath(new URL('..', import.meta.url));
const bleDir = fileURLToPath(new URL('../../brilliant-ble', import.meta.url));

if (!existsSync(`${bleDir}/node_modules`)) {
    run('npm ci', bleDir);
}
if (!existsSync(`${bleDir}/dist`)) {
    run('npm run build', bleDir);
}

// Always rebuild brilliant-msg so the tests exercise the current sources.
run('npm run build', msgDir);
