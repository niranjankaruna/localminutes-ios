import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { lstat, mkdir, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { promisify } from 'node:util';

const execute = promisify(execFile);
export const ghCLI = async (args, options = {}) => (await execute('gh', args, {
  encoding: 'utf8', timeout: 10 * 60 * 1000, maxBuffer: 4 * 1024 * 1024, ...options
})).stdout.trim();

// Fetch evidence while the run still exists: deleting a run also deletes its
// logs and check annotations. These files deliberately are not an IPA receipt.
async function saveFailedBuild({ gh, repository, runID, run, workflow, sourceCommit, requestID, outputDirectory }) {
  let log, logError;
  try { log = await gh(['run', 'view', String(runID), '--repo', repository, '--log-failed']); }
  catch (error) { logError = error.stderr ?? error.message; }
  if (!log?.trim()) logError ??= 'GitHub returned no failed-job log.';
  await mkdir(dirname(outputDirectory), { recursive: true });
  await mkdir(outputDirectory);
  const logPath = join(outputDirectory, 'build-failure.log');
  await writeFile(logPath, log || `Failed-job log unavailable: ${logError}\n`, { flag: 'wx' });
  await writeFile(join(outputDirectory, 'build-failure.json'), JSON.stringify({
    schemaVersion: 1, repository, workflow, sourceCommit, requestID, runID,
    conclusion: run.conclusion, runURL: run.html_url ?? `https://github.com/${repository}/actions/runs/${runID}`,
    logFile: 'build-failure.log', logError: logError ?? null
  }, null, 2) + '\n', { flag: 'wx' });
  const errors = [...new Set((log ?? '').split(/\r?\n/)
    .filter(line => /(?:\berror:|fatal error|##\[error\]|BUILD FAILED)/i.test(line))
    .map(line => line.split('\t').at(-1).replace(/^\d{4}-\d{2}-\d{2}T\S+\s*/, '').trim()))].slice(0, 8);
  return `Diagnostics saved to: ${logPath}` +
    (logError ? `\nFailed-job log unavailable: ${logError}` : '') +
    (errors.length ? `\n${errors.join('\n')}` : '');
}

// The injected CLI and delay let lifecycle tests exercise failures without GitHub writes.
export async function downloadWorkflowArtifact({ repository, ref, sourceCommit, outputDirectory,
  workflow, runNamePrefix, artifactName, verifyDownload, workflowInputs = {},
  requestID = randomUUID(), gh = ghCLI, sleep = delay, cancelled = () => false }) {
  assert.match(repository, /^[\w.-]+\/[\w.-]+$/);
  assert.match(sourceCommit, /^[0-9a-f]{40}$/);
  assert.match(requestID, /^[0-9a-f-]{36}$/);
  const inputArguments = [];
  for (const [name, value] of Object.entries(workflowInputs)) {
    assert.match(name, /^[a-z][a-z0-9_]*$/);
    assert.notEqual(name, 'request_id', 'The transfer owns its request ID');
    assert.equal(typeof value, 'string');
    inputArguments.push('-f', `${name}=${value}`);
  }
  assert.equal(await lstat(outputDirectory).then(() => true, error => {
    if (error.code === 'ENOENT') return false;
    throw error;
  }), false, 'Choose a new output directory; existing downloads are never overwritten');

  const api = async endpoint => JSON.parse(await gh(['api', endpoint]));
  const runBase = `repos/${repository}/actions/runs`;
  const failures = [];
  let runID, downloaded;
  const findRun = async () => {
    const runs = JSON.parse(await gh(['run', 'list', '--repo', repository,
      '--workflow', workflow, '--event', 'workflow_dispatch', '--limit', '100',
      '--json', 'databaseId,displayTitle']));
    return runs.find(run => run.displayTitle === `${runNamePrefix} ${requestID}`)?.databaseId;
  };
  const checkWaiting = deadline => {
    if (cancelled()) throw new Error('Local download cancelled');
    if (Date.now() >= deadline) throw new Error('Timed out waiting for the workflow');
  };
  const deleteIfPresent = async endpoint => {
    try { await gh(['api', '--method', 'DELETE', endpoint]); }
    catch (error) { if (!/HTTP 404/.test(error.stderr ?? error.message)) throw error; }
  };

  try {
    await gh(['workflow', 'run', workflow, '--repo', repository, '--ref', ref,
      '-f', `request_id=${requestID}`, ...inputArguments]);
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
      artifact = result.artifacts.find(item => item.name === artifactName && !item.expired);
      if (!artifact && run.status === 'completed') {
        let details;
        try {
          details = await saveFailedBuild({ gh, repository, runID, run, workflow, sourceCommit, requestID, outputDirectory });
        } catch (error) { details = `Could not save build diagnostics: ${error.message}`; }
        throw new Error(`Build finished (${run.conclusion}) without a transferable artifact\n${details}`);
      }
      if (!artifact) await sleep(10000);
    }

    await mkdir(dirname(outputDirectory), { recursive: true });
    await mkdir(outputDirectory);
    await gh(['run', 'download', String(runID), '--repo', repository,
      '--name', artifactName, '--dir', outputDirectory]);
    downloaded = await verifyDownload(outputDirectory, sourceCommit);
    // Deleting the verified transfer copy also releases the workflow's waiting job.
    await deleteIfPresent(`repos/${repository}/actions/artifacts/${artifact.id}`);
    let run;
    do {
      checkWaiting(deadline);
      run = await api(runPath);
      if (run.status !== 'completed') await sleep(5000);
    } while (run.status !== 'completed');
    assert.equal(run.conclusion, 'success', 'Workflow did not finish successfully');
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
  return downloaded;
}

