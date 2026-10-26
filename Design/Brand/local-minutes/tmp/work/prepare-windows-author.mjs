import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { createRequire } from 'node:module';

const work = dirname(fileURLToPath(import.meta.url));
const scripts = process.env.APP_ICON_SKILL_SCRIPTS || 'C:/Users/NiMo/.agents/skills/app-icon-gen/scripts';
const require = createRequire(join(scripts, 'package.json'));
let source = await readFile(join(scripts, 'author_icon.mjs'), 'utf8');
const oldDepthCheck = 'canonical.split("/").filter(Boolean).length < 3';
const newDepthCheck = 'canonical.split(String.fromCharCode(92)).join("/").split("/").filter(Boolean).length < 3';
if (source.includes(oldDepthCheck)) {
  source = source.replace(oldDepthCheck, newDepthCheck);
} else if (!source.includes(newDepthCheck)) {
  throw new Error('The author tool has changed. Review its path safety check before patching.');
}
// Keep the installed skill unmodified. This local copy only corrects Windows
// separator handling; root, ownership, symlink, and containment guards remain.
source = source.replace('from "@resvg/resvg-js"', `from "${pathToFileURL(require.resolve('@resvg/resvg-js')).href}"`);
for (const lib of ['apple_export_profiles.mjs', 'icon_contract.mjs']) {
  source = source.replace(`from "./lib/${lib}"`, `from "${pathToFileURL(join(scripts, 'lib', lib)).href}"`);
}
const runtime = join(work, 'icon-tooling');
await mkdir(runtime, { recursive: true });
await writeFile(join(runtime, 'author_icon.mjs'), source);
await writeFile(join(runtime, 'package.json'), JSON.stringify({
  name: 'localminutes-icon-tooling', private: true, type: 'module',
  scripts: { 'author-icon': 'node author_icon.mjs' },
}, null, 2) + '\n');
console.log('Prepared the original author-icon tool with a Windows-aware path depth check.');
