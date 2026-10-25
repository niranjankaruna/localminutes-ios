import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { mkdir, realpath } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { promisify } from 'node:util';
import { downloadWorkflowArtifact, ghCLI } from './github-transfer.mjs';
import { replaceScreenshots, verifyScreenshots } from './app-screenshots.mjs';

export async function captureAndDownload({ repositoryRoot, repository, ref, sourceCommit,
  requestID = randomUUID(), gh = ghCLI, sleep, cancelled }) {
  const root = await realpath(repositoryRoot);
  const local = join(root, '.agent-local');
  await mkdir(local, { recursive: true });
  assert.equal(await realpath(local), local, 'Screenshot staging cannot use a linked directory');
  const stagingDirectory = join(local, `screenshots-${requestID}`);
  await downloadWorkflowArtifact({ repository, ref, sourceCommit, requestID, gh, sleep, cancelled,
    outputDirectory: stagingDirectory, workflow: 'app-screenshots.yml', runNamePrefix: 'Screenshots',
    artifactName: 'app-ui-screenshots-transfer', verifyDownload: verifyScreenshots });
  return replaceScreenshots({ repositoryRoot: root, stagingDirectory, sourceCommit });
}

async function main() {
  const args = process.argv.slice(2);
  if (args.includes('--help')) {
    console.log('Usage: node scripts/download-screenshots.mjs [--ref BRANCH_OR_TAG]\n' +
      'Runs the iOS app on hosted macOS and replaces this project\'s AppUI_Screenshots folder.\n' +
      'Requires Node.js 22, Git, and authenticated GitHub CLI with Actions write access.\n' +
      'The checkout must be clean and pushed. Temporary artifacts and the run are deleted.');
    return;
  }
  assert.ok(args.length === 0 || (args.length === 2 && args[0] === '--ref' && args[1]), 'Unknown or incomplete option');
  const root = await realpath(fileURLToPath(new URL('..', import.meta.url)));
  const execute = promisify(execFile);
  const git = async args => (await execute('git', args, { cwd: root, encoding: 'utf8' })).stdout.trim();
  const gh = args => ghCLI(args, { cwd: root });
  assert.equal(await git(['status', '--porcelain']), '', 'Commit and push local changes before taking screenshots');
  const sourceCommit = await git(['rev-parse', 'HEAD']);
  const ref = args[1] ?? await git(['branch', '--show-current']);
  assert.ok(ref, 'Pass --ref for a detached checkout');
  const repository = await gh(['repo', 'view', '--json', 'nameWithOwner', '--jq', '.nameWithOwner']);
  const remote = JSON.parse(await gh(['api', `repos/${repository}/commits/${encodeURIComponent(ref)}`]));
  assert.equal(remote.sha, sourceCommit, 'Push this commit to the selected ref before taking screenshots');
  let cancelled = false;
  const interrupt = () => { cancelled = true; console.error('Cancelling; waiting for remote cleanup…'); };
  process.on('SIGINT', interrupt);
  try {
    console.log(`Capturing ${sourceCommit}; destination: ${join(root, 'AppUI_Screenshots')}`);
    const destination = await captureAndDownload({ repositoryRoot: root, repository, ref, sourceCommit, gh,
      cancelled: () => cancelled });
    console.log(`Screenshots replaced: ${destination}\nTemporary GitHub artifact and workflow run deleted.`);
  } finally { process.off('SIGINT', interrupt); }
}

if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  main().catch(error => { console.error(error.message); process.exitCode = 1; });
}
