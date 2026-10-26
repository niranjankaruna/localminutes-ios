import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { mkdir, realpath } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { parseArgs, promisify } from 'node:util';
import { downloadWorkflowArtifact, ghCLI } from './github-transfer.mjs';
import { expectedScreenshotNames, replaceScreenshots, resolveScreenshotSelection, screenshotCategories,
  verifyScreenshots } from './app-screenshots.mjs';

export async function captureAndDownload({ repositoryRoot, repository, ref, sourceCommit,
  appearance = 'both', categories = '', screens = '', related = false,
  requestID = randomUUID(), gh = ghCLI, sleep, cancelled, onProgress }) {
  const selection = await resolveScreenshotSelection({ appearance, categories, screens, related });
  const root = await realpath(repositoryRoot);
  const local = join(root, '.agent-local');
  await mkdir(local, { recursive: true });
  assert.equal(await realpath(local), local, 'Screenshot staging cannot use a linked directory');
  const stagingDirectory = join(local, `screenshots-${requestID}`);
  await downloadWorkflowArtifact({ repository, ref, sourceCommit, requestID, gh, sleep, cancelled, onProgress,
    outputDirectory: stagingDirectory, workflow: 'app-screenshots.yml', runNamePrefix: 'Screenshots',
    artifactName: 'app-ui-screenshots-transfer', workflowInputs: { appearance, categories, screens, related: String(related) },
    verifyDownload: (directory, commit) => verifyScreenshots(directory, commit, selection) });
  return replaceScreenshots({ repositoryRoot: root, stagingDirectory, sourceCommit, selection });
}

async function main() {
  const { values } = parseArgs({ options: {
    ref: { type: 'string' }, appearance: { type: 'string', default: 'both' },
    categories: { type: 'string', default: '' }, screens: { type: 'string', default: '' },
    related: { type: 'boolean', default: false }, list: { type: 'boolean' }, help: { type: 'boolean' }
  } });
  if (values.help) {
    console.log('Usage: node scripts/download-screenshots.mjs [--ref BRANCH_OR_TAG]\n' +
      '  [--appearance both|light|dark] [--categories NAME,NAME] [--screens NAME,NAME] [--related] [--list]\n' +
      'No filters captures all screens in both appearances. Categories and screen names are combined.\n' +
      '--related includes every screen in the named screen\'s category. --list previews the selection without GitHub.\n' +
      'Output: AppUI_Screenshots/<appearance>/<category>/<screen>_<appearance>.png\n' +
      'Partial captures update only selected images; complete captures replace the gallery.\n' +
      'Requires Node.js 22, Git, and authenticated GitHub CLI with Actions write access.\n' +
      'The checkout must be clean and pushed. Temporary artifacts and the run are deleted.');
    return;
  }
  const selection = await resolveScreenshotSelection(values);
  const names = await expectedScreenshotNames(selection);
  if (values.list) {
    console.log(`Appearances: ${selection.appearances.join(', ')}; ${names.length} screenshots`);
    for (const [category, members] of Object.entries(screenshotCategories)) {
      const selected = members.filter(scene => selection.scenes.includes(scene));
      if (selected.length) console.log(`${category}:\n${selected.map(scene => `  ${scene}`).join('\n')}`);
    }
    return;
  }
  const root = await realpath(fileURLToPath(new URL('..', import.meta.url)));
  const execute = promisify(execFile);
  const git = async args => (await execute('git', args, { cwd: root, encoding: 'utf8' })).stdout.trim();
  const gh = (args, options = {}) => ghCLI(args, { ...options, cwd: root });
  assert.equal(await git(['status', '--porcelain']), '', 'Commit and push local changes before taking screenshots');
  const sourceCommit = await git(['rev-parse', 'HEAD']);
  const ref = values.ref ?? await git(['branch', '--show-current']);
  assert.ok(ref, 'Pass --ref for a detached checkout');
  const repository = await gh(['repo', 'view', '--json', 'nameWithOwner', '--jq', '.nameWithOwner']);
  const remote = JSON.parse(await gh(['api', `repos/${repository}/commits/${encodeURIComponent(ref)}`]));
  assert.equal(remote.sha, sourceCommit, 'Push this commit to the selected ref before taking screenshots');
  let cancelled = false;
  const interrupt = () => { cancelled = true; console.error('Cancelling; waiting for remote cleanup…'); };
  process.on('SIGINT', interrupt);
  try {
    console.log(`Capturing ${names.length} screenshots (${selection.appearances.join(', ')}) at ${sourceCommit}; ` +
      `destination: ${join(root, 'AppUI_Screenshots')}`);
    console.log(names.join('\n'));
    const destination = await captureAndDownload({ ...values, repositoryRoot: root, repository, ref, sourceCommit, gh,
      cancelled: () => cancelled, onProgress: message => console.error(message) });
    console.log(`${names.length} screenshots updated: ${destination}\nTemporary GitHub artifact and workflow run deleted.`);
  } finally { process.off('SIGINT', interrupt); }
}

if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  main().catch(error => { console.error(error.message); process.exitCode = 1; });
}
