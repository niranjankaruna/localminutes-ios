import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { lstat, mkdir, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { promisify, stripVTControlCharacters } from 'node:util';

const execute = promisify(execFile);
export const ghCLI = async (args, options = {}) => (await execute('gh', args, {
  encoding: 'utf8', timeout: 10 * 60 * 1000, maxBuffer: 4 * 1024 * 1024, ...options
})).stdout.trim();

async function fetchFailedJobDiagnostics(gh, repository, runID) {
  const jobs = [], errors = [], messages = [];
  const api = async (endpoint, paginate = false) => JSON.parse(await gh([
    'api', endpoint, ...(paginate ? ['--paginate', '--slurp'] : [])
  ]));
  try {
    const pages = await api(`repos/${repository}/actions/runs/${runID}/jobs?per_page=100`, true);
    for (const job of pages.flatMap(page => page.jobs)) {
      if (['success', 'skipped', 'neutral'].includes(job.conclusion)) continue;
      const report = {
        id: job.id, name: job.name, status: job.status, conclusion: job.conclusion,
        startedAt: job.started_at, completedAt: job.completed_at,
        steps: job.steps, output: null, annotations: []
      };
      jobs.push(report);
      const checkID = job.check_run_url?.match(/\/check-runs\/(\d+)$/)?.[1];
      if (!checkID) continue;
      const checkPath = `repos/${repository}/check-runs/${checkID}`;
      // Runner failures may exist only as annotations, even when step logs stop abruptly.
      try {
        const check = await api(checkPath);
        report.output = check.output;
      } catch (error) { errors.push(`${job.name} check output: ${error.stderr ?? error.message}`); }
      try {
        report.annotations = (await api(`${checkPath}/annotations?per_page=100`, true)).flat();
      } catch (error) { errors.push(`${job.name} annotations: ${error.stderr ?? error.message}`); }
      for (const annotation of report.annotations) {
        if (annotation.annotation_level === 'failure') messages.push(`${job.name}: ${annotation.message}`);
      }
      if (report.output?.summary) messages.push(`${job.name}: ${report.output.summary}`);
    }
  } catch (error) { errors.push(`Workflow jobs: ${error.stderr ?? error.message}`); }
  return { jobs, errors, messages };
}

async function fetchJobLog(gh, repository, jobID) {
  const args = ['api', `repos/${repository}/actions/jobs/${jobID}/logs`];
  const options = { maxBuffer: 32 * 1024 * 1024 };
  let log;
  try { log = await gh(args, options); }
  catch (error) {
    if (!/response contains terminal escape sequences/.test(error.stderr ?? error.message)) throw error;
    // Capture as data, then strip terminal controls before saving or displaying it.
    log = await gh([...args, '--allow-escape-sequences'], options);
  }
  assert.ok(log.trim(), 'GitHub returned no job log.');
  return stripVTControlCharacters(log);
}

// Fetch evidence while the run still exists: deleting a run also deletes its
// logs and check annotations. These files deliberately are not an IPA receipt.
async function saveFailedBuild({ gh, repository, runID, run, workflow, sourceCommit, requestID, outputDirectory }) {
  let log, logError;
  const diagnostics = await fetchFailedJobDiagnostics(gh, repository, runID);
  const jobLogs = [];
  for (const job of diagnostics.jobs) {
    try {
      // gh run view can silently truncate at a compiler line longer than 64 KiB.
      // The raw job endpoint preserves the later error and crash backtrace.
      jobLogs.push(`GitHub job: ${job.name} (${job.id})\n${await fetchJobLog(gh, repository, job.id)}`);
    } catch (error) {
      job.logError = error.stderr ?? error.message;
      diagnostics.errors.push(`${job.name} full log: ${job.logError}`);
    }
  }
  log = jobLogs.join('\n\n');
  if (!log) {
    try {
      log = stripVTControlCharacters(await gh(['run', 'view', String(runID), '--repo', repository, '--log-failed'], {
        maxBuffer: 32 * 1024 * 1024
      }));
    } catch (error) { logError = error.stderr ?? error.message; }
  }
  if (!log?.trim()) logError ??= 'GitHub returned no failed-job log.';
  const jobSummary = diagnostics.jobs.map(job => {
    const failedSteps = (job.steps ?? []).filter(step => step.conclusion === 'failure').map(step => step.name);
    return `${job.name}: ${job.conclusion ?? job.status}${failedSteps.length ? ` (${failedSteps.join(', ')})` : ''}`;
  });
  const diagnosticLines = [...jobSummary, ...diagnostics.messages,
    ...diagnostics.errors.map(error => `Diagnostic retrieval failed: ${error}`)];
  await mkdir(dirname(outputDirectory), { recursive: true });
  await mkdir(outputDirectory);
  const logPath = join(outputDirectory, 'build-failure.log');
  await writeFile(logPath, (log || `Failed-job log unavailable: ${logError}\n`) +
    (diagnosticLines.length ? `\n\nGitHub job diagnostics:\n${diagnosticLines.join('\n')}\n` : ''), { flag: 'wx' });
  await writeFile(join(outputDirectory, 'build-failure.json'), JSON.stringify({
    schemaVersion: 1, repository, workflow, sourceCommit, requestID, runID,
    conclusion: run.conclusion, runURL: run.html_url ?? `https://github.com/${repository}/actions/runs/${runID}`,
    logFile: 'build-failure.log', logError: logError ?? null,
    jobs: diagnostics.jobs, diagnosticErrors: diagnostics.errors
  }, null, 2) + '\n', { flag: 'wx' });
  const errors = [...new Set([...diagnostics.messages, ...(log ?? '').split(/\r?\n/)
    .filter(line => /(?:\berror:|fatal error|##\[error\]|BUILD FAILED|Command .* failed|Failed frontend command:|While emitting IR SIL function|SmallVector unable to grow)/i.test(line))
    .map(line => line.split('\t').at(-1).replace(/^\d{4}-\d{2}-\d{2}T\S+\s*/, '').trim())])].slice(0, 8);
  return `Diagnostics saved to: ${logPath}` +
    (logError ? `\nFailed-job log unavailable: ${logError}` : '') +
    (errors.length ? `\n${errors.join('\n')}` : jobSummary.length ? `\n${jobSummary.join('\n')}` : '') +
    (diagnostics.errors.length ? '\nSome GitHub job diagnostics were unavailable; see build-failure.json.' : '');
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

