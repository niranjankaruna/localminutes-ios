import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { lstat, mkdir, readFile, readdir } from 'node:fs/promises';
import { homedir } from 'node:os';
import { basename, dirname, join, resolve } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { pathToFileURL } from 'node:url';
import { promisify } from 'node:util';
import { verifyFileSHA256 } from './ios-artifacts.mjs';

const execute = promisify(execFile);
const ghCLI = async args => (await execute('gh', args, {
  encoding: 'utf8', timeout: 10 * 60 * 1000, maxBuffer: 4 * 1024 * 1024
})).stdout.trim();

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

// The injected CLI and delay let lifecycle tests exercise failures without GitHub writes.
export async function buildAndDownload({ repository, ref, sourceCommit, outputDirectory,
  requestID = randomUUID(), gh = ghCLI, sleep = delay, cancelled = () => false }) {
  assert.match(repository, /^[\w.-]+\/[\w.-]+$/);
  assert.match(sourceCommit, /^[0-9a-f]{40}$/);
  assert.match(requestID, /^[0-9a-f-]{36}$/);
  assert.equal(await lstat(outputDirectory).then(() => true, error => {
    if (error.code === 'ENOENT') return false;
    throw error;
  }), false, 'Choose a new output directory; existing downloads are never overwritten');

  const api = async endpoint => JSON.parse(await gh(['api', endpoint]));
  const runBase = `repos/${repository}/actions/runs`;
  const failures = [];
  let runID, ipa;
  const findRun = async () => {
    const runs = JSON.parse(await gh(['run', 'list', '--repo', repository,
      '--workflow', 'build-ipa.yml', '--event', 'workflow_dispatch', '--limit', '100',
      '--json', 'databaseId,displayTitle']));
    return runs.find(run => run.displayTitle === `IPA ${requestID}`)?.databaseId;
  };
  const checkWaiting = deadline => {
    if (cancelled()) throw new Error('Local download cancelled');
    if (Date.now() >= deadline) throw new Error('Timed out waiting for the IPA workflow');
  };
  const deleteIfPresent = async endpoint => {
    try { await gh(['api', '--method', 'DELETE', endpoint]); }
    catch (error) { if (!/HTTP 404/.test(error.stderr ?? error.message)) throw error; }
  };

  try {
    await gh(['workflow', 'run', 'build-ipa.yml', '--repo', repository, '--ref', ref,
      '-f', `request_id=${requestID}`]);
    const deadline = Date.now() + 120 * 60 * 1000;
    while (!runID) {
      checkWaiting(deadline);
      runID = await findRun();
      if (!runID) await sleep(5000);
    }
    const runPath = `${runBase}/${runID}`;
    let artifact;
    while (!artifact) {
      checkWaiting(deadline);
      const run = await api(runPath);
      assert.equal(run.head_sha, sourceCommit, 'Workflow checked out a different source commit');
      const result = await api(`${runPath}/artifacts`);
      artifact = result.artifacts.find(item => item.name === 'ipa-transfer' && !item.expired);
      if (!artifact && run.status === 'completed') {
        throw new Error(`Build finished (${run.conclusion}) without a transferable IPA`);
      }
      if (!artifact) await sleep(10000);
    }

    await mkdir(dirname(outputDirectory), { recursive: true });
    await mkdir(outputDirectory);
    await gh(['run', 'download', String(runID), '--repo', repository,
      '--name', 'ipa-transfer', '--dir', outputDirectory]);
    ipa = await verifyDownloadedIPA(outputDirectory, sourceCommit);
    // Deleting the verified transfer copy also releases the workflow's waiting job.
    await deleteIfPresent(`repos/${repository}/actions/artifacts/${artifact.id}`);
    let run;
    do {
      checkWaiting(deadline);
      run = await api(runPath);
      if (run.status !== 'completed') await sleep(5000);
    } while (run.status !== 'completed');
    assert.equal(run.conclusion, 'success', 'IPA workflow did not finish successfully');
  } catch (error) {
    failures.push(error);
  }

  // Clean up only this uniquely identified request, including on verification failure.
  try {
    runID ??= await findRun();
    if (runID) {
      const runPath = `${runBase}/${runID}`;
      let run = await api(runPath);
      if (run.status !== 'completed') {
        try { await gh(['run', 'cancel', String(runID), '--repo', repository]); }
        catch (error) {
          if ((await api(runPath)).status !== 'completed') throw error;
        }
        const deadline = Date.now() + 2 * 60 * 1000;
        while (run.status !== 'completed') {
          if (Date.now() >= deadline) throw new Error('Workflow cancellation did not finish');
          await sleep(2000);
          run = await api(runPath);
        }
      }
      for (const artifact of (await api(`${runPath}/artifacts`)).artifacts) {
        await deleteIfPresent(`repos/${repository}/actions/artifacts/${artifact.id}`);
      }
      await deleteIfPresent(runPath);
    }
  } catch (error) {
    failures.push(new Error(`Remote cleanup failed for ${repository}, run ${runID ?? requestID}. ` +
      `Delete that build run in GitHub Actions: ${error.message}`));
  }
  if (failures.length) throw new AggregateError(failures, failures.map(error => error.message).join('\n'));
  return ipa;
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
