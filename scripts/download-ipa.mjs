import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { lstat, readFile, readdir } from 'node:fs/promises';
import { homedir } from 'node:os';
import { basename, join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { promisify } from 'node:util';
import { verifyFileSHA256 } from './ios-artifacts.mjs';
import { downloadWorkflowArtifact, ghCLI } from './github-transfer.mjs';

const execute = promisify(execFile);

export async function verifyDownloadedIPA(directory, sourceCommit) {
  const manifestPath = join(directory, 'build-manifest.json');
  assert.ok((await lstat(manifestPath)).isFile(), 'Expected a regular build manifest');
  const manifest = JSON.parse(await readFile(manifestPath, 'utf8'));
  assert.equal(manifest.schemaVersion, 1);
  assert.equal(manifest.sourceCommit, sourceCommit, 'Downloaded source commit does not match the request');
  assert.equal(manifest.signing, 'unsigned');
  assert.match(manifest.sha256, /^[0-9a-f]{64}$/);
  assert.equal(manifest.artifact, basename(manifest.artifact));
  assert.match(manifest.artifact, /^LocalMinutes-[\d.]+-[0-9a-f]{40}-unsigned\.ipa$/);
  assert.deepEqual((await readdir(directory)).sort(),
    [manifest.artifact, `${manifest.artifact}.sha256`, 'build-manifest.json'].sort());
  const ipa = join(directory, manifest.artifact);
  const checksum = `${ipa}.sha256`;
  for (const file of [ipa, checksum]) {
    assert.ok((await lstat(file)).isFile(), 'Downloads must be regular files');
  }
  assert.equal((await lstat(ipa)).size, manifest.sizeBytes);
  assert.equal(await readFile(checksum, 'utf8'), `${manifest.sha256}  ${manifest.artifact}\n`);
  await verifyFileSHA256(ipa, manifest.sha256);
  return ipa;
}

export function buildAndDownload(options) {
  return downloadWorkflowArtifact({ ...options, workflow: 'build-ipa.yml', runNamePrefix: 'IPA',
    artifactName: 'ipa-transfer', verifyDownload: verifyDownloadedIPA });
}

async function main() {
  const args = process.argv.slice(2);
  if (args.includes('--help')) {
    console.log('Usage: node scripts/download-ipa.mjs [--ref BRANCH_OR_TAG] [--output NEW_DIRECTORY]\n' +
      'Requires Node.js 22, Git, and authenticated GitHub CLI with Actions write access.\n' +
      'Builds the pushed local commit, verifies the download, then deletes the artifact and build run.');
    return;
  }
  const options = {};
  for (let i = 0; i < args.length; i += 2) {
    assert.ok(['--ref', '--output'].includes(args[i]) && args[i + 1], 'Unknown or incomplete option');
    options[args[i]] = args[i + 1];
  }
  const git = async args => (await execute('git', args, { encoding: 'utf8' })).stdout.trim();
  assert.equal(await git(['status', '--porcelain']), '', 'Commit and push local changes before building');
  const sourceCommit = await git(['rev-parse', 'HEAD']);
  const ref = options['--ref'] ?? await git(['branch', '--show-current']);
  assert.ok(ref, 'Pass --ref for a detached checkout');
  const repository = await ghCLI(['repo', 'view', '--json', 'nameWithOwner', '--jq', '.nameWithOwner']);
  const remote = JSON.parse(await ghCLI(['api', `repos/${repository}/commits/${encodeURIComponent(ref)}`]));
  assert.equal(remote.sha, sourceCommit, 'Push this commit to the selected ref before building');
  const requestID = randomUUID();
  const outputDirectory = resolve(options['--output'] ?? join(homedir(), 'Downloads', 'LocalMinutes', requestID));
  let cancelled = false;
  const interrupt = () => { cancelled = true; console.error('Cancelling; waiting for remote cleanup…'); };
  process.on('SIGINT', interrupt);
  try {
    console.log(`Building ${sourceCommit}; download destination: ${outputDirectory}`);
    const ipa = await buildAndDownload({ repository, ref, sourceCommit, outputDirectory, requestID,
      cancelled: () => cancelled });
    console.log(`Verified IPA: ${ipa}\nTemporary GitHub artifact and build run deleted.`);
  } finally { process.off('SIGINT', interrupt); }
}

if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  main().catch(error => { console.error(error.message); process.exitCode = 1; });
}
