import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { buildAndDownload, verifyDownloadedIPA } from '../download-ipa.mjs';

const commit = 'a'.repeat(40);
const requestID = '12345678-1234-1234-1234-123456789012';

async function withDirectory(body) {
  const parent = resolve('.agent-local');
  await mkdir(parent, { recursive: true });
  const root = await mkdtemp(join(parent, 'ipa-transfer-test-'));
  try { await body(root); }
  finally {
    assert.equal(dirname(resolve(root)), parent);
    await rm(root, { recursive: true, force: true });
  }
}

async function writeReceipt(directory, { source = commit, corrupt = false, escape = false } = {}) {
  const bytes = Buffer.from('synthetic IPA receipt fixture');
  const artifact = `LocalMinutes-1.0-${commit}-unsigned.ipa`;
  const sha256 = createHash('sha256').update(bytes).digest('hex');
  await writeFile(join(directory, artifact), corrupt ? Buffer.from('x'.repeat(bytes.length)) : bytes);
  await writeFile(join(directory, `${artifact}.sha256`), `${sha256}  ${artifact}\n`);
  await writeFile(join(directory, 'build-manifest.json'), JSON.stringify({
    schemaVersion: 1, sourceCommit: source, signing: 'unsigned',
    artifact: escape ? `../${artifact}` : artifact, sha256, sizeBytes: bytes.length
  }));
  return join(directory, artifact);
}

test('download verification checks the receipt, file size, and actual checksum', async () => {
  await withDirectory(async directory => {
    const ipa = await writeReceipt(directory);
    assert.equal(await verifyDownloadedIPA(directory, commit), ipa);
    await writeReceipt(directory, { corrupt: true });
    await assert.rejects(() => verifyDownloadedIPA(directory, commit), /checksum|hash/i);
  });
});

test('download verification rejects the wrong source and escaping artifact names', async () => {
  await withDirectory(async directory => {
    await writeReceipt(directory, { source: 'b'.repeat(40) });
    await assert.rejects(() => verifyDownloadedIPA(directory, commit), /source commit/i);
    await writeReceipt(directory, { escape: true });
    await assert.rejects(() => verifyDownloadedIPA(directory, commit));
  });
});

function githubFixture({ outputDirectory, corrupt = false, dispatchFailure = false }) {
  let completed = false, artifactExists = true;
  const calls = [];
  const gh = async args => {
    calls.push(args.join(' '));
    if (args[0] === 'workflow') {
      if (dispatchFailure) throw new Error('Dispatch failed');
      return '';
    }
    if (args[0] === 'run' && args[1] === 'list') {
      return JSON.stringify([
        { databaseId: 99, displayTitle: 'IPA another-request' },
        ...(dispatchFailure ? [] : [{ databaseId: 17, displayTitle: `IPA ${requestID}` }])
      ]);
    }
    if (args[0] === 'run' && args[1] === 'download') {
      await writeReceipt(outputDirectory, { corrupt });
      return '';
    }
    if (args[0] === 'run' && args[1] === 'cancel') { completed = true; return ''; }
    if (args[0] === 'api' && args[1] === '--method') {
      if (args[3].endsWith('/artifacts/42')) { artifactExists = false; completed = true; }
      else assert.ok(args[3].endsWith('/runs/17'));
      return '';
    }
    if (args[0] === 'api' && args[1].endsWith('/artifacts')) {
      return JSON.stringify({ artifacts: artifactExists ? [{ id: 42, name: 'ipa-transfer', expired: false }] : [] });
    }
    if (args[0] === 'api' && args[1].endsWith('/runs/17')) {
      return JSON.stringify({ head_sha: commit, status: completed ? 'completed' : 'in_progress', conclusion: 'success' });
    }
    throw new Error(`Unexpected CLI call: ${args.join(' ')}`);
  };
  return { gh, calls };
}

test('successful handoff verifies locally before deleting the artifact and exact build run', async () => {
  await withDirectory(async directory => {
    const outputDirectory = join(directory, 'download');
    const { gh, calls } = githubFixture({ outputDirectory });
    const ipa = await buildAndDownload({ repository: 'owner/repository', ref: 'main',
      sourceCommit: commit, outputDirectory, requestID, gh, sleep: async () => {} });
    assert.equal(await verifyDownloadedIPA(outputDirectory, commit), ipa);
    const download = calls.findIndex(call => call.startsWith('run download 17'));
    const deleteArtifact = calls.findIndex(call => call.includes('DELETE repos/owner/repository/actions/artifacts/42'));
    const deleteRun = calls.findIndex(call => call.includes('DELETE repos/owner/repository/actions/runs/17'));
    assert.ok(download < deleteArtifact && deleteArtifact < deleteRun);
    assert.equal(calls.some(call => call.includes('/runs/99')), false);
  });
});

for (const endpoint of ['discovery', 'status', 'artifacts']) {
  test(`a transient GitHub ${endpoint} timeout retries without cancelling the build`, async () => {
    await withDirectory(async directory => {
      const outputDirectory = join(directory, 'download');
      const fixture = githubFixture({ outputDirectory });
      let interrupted = false;
      const waits = [], progress = [];
      const gh = async (args, options = {}) => {
        const matches = endpoint === 'discovery' ? args[0] === 'run' && args[1] === 'list'
          : args[0] === 'api' && args[1].endsWith(endpoint === 'status' ? '/runs/17' : '/artifacts');
        if (matches && !interrupted) {
          assert.equal(options.timeout, 30_000, 'A lost read connection must not hang for ten minutes');
          interrupted = true;
          throw new Error('dial tcp 4.208.26.200:443: connectex: A connection attempt failed');
        }
        return fixture.gh(args);
      };
      const ipa = await buildAndDownload({ repository: 'owner/repository', ref: 'main',
        sourceCommit: commit, outputDirectory, requestID, gh,
        sleep: async milliseconds => waits.push(milliseconds), onProgress: message => progress.push(message) });
      assert.equal(await verifyDownloadedIPA(outputDirectory, commit), ipa);
      assert.equal(interrupted, true);
      assert.ok(waits.some(milliseconds => milliseconds > 0));
      assert.ok(progress.some(message => /retry/i.test(message)));
      assert.equal(fixture.calls.some(call => call.startsWith('run cancel')), false);
    });
  });
}

test('an exhausted connection outage preserves the remote run instead of cancelling or deleting it', async () => {
  await withDirectory(async directory => {
    const outputDirectory = join(directory, 'download');
    const fixture = githubFixture({ outputDirectory });
    let reads = 0;
    const gh = async args => {
      if (args[0] === 'api' && args[1].endsWith('/runs/17')) {
        reads++;
        throw new Error('Get https://api.github.com: net/http: TLS handshake timeout');
      }
      return fixture.gh(args);
    };
    await assert.rejects(() => buildAndDownload({ repository: 'owner/repository', ref: 'main',
      sourceCommit: commit, outputDirectory, requestID, gh, sleep: async () => {} }), error => {
      assert.match(error.message, /connection|timeout/i);
      assert.match(error.message, /left running|preserved/i);
      assert.ok(error.message.includes('https://github.com/owner/repository/actions/runs/17'));
      return true;
    });
    assert.equal(reads, 5, 'Reads have a bounded retry budget');
    assert.equal(fixture.calls.some(call => call.startsWith('run cancel') || call.includes('DELETE')), false);
  });
});

test('an explicit cancellation during retry still cancels and cleans the matching run', async () => {
  await withDirectory(async directory => {
    const outputDirectory = join(directory, 'download');
    const fixture = githubFixture({ outputDirectory });
    let interrupted = false, cancelled = false;
    const gh = async args => {
      if (args[0] === 'api' && args[1].endsWith('/runs/17') && !interrupted) {
        interrupted = true;
        throw new Error('read tcp: connection reset by peer');
      }
      return fixture.gh(args);
    };
    await assert.rejects(() => buildAndDownload({ repository: 'owner/repository', ref: 'main',
      sourceCommit: commit, outputDirectory, requestID, gh,
      cancelled: () => cancelled, sleep: async () => { cancelled = true; } }), /cancelled/i);
    assert.ok(fixture.calls.some(call => call.startsWith('run cancel 17')));
    assert.ok(fixture.calls.some(call => call.includes('DELETE repos/owner/repository/actions/runs/17')));
  });
});

test('a timed-out dispatch is not retried or treated as permission to cancel a possibly accepted build', async () => {
  await withDirectory(async directory => {
    const calls = [];
    await assert.rejects(() => buildAndDownload({ repository: 'owner/repository', ref: 'main',
      sourceCommit: commit, outputDirectory: join(directory, 'download'), requestID,
      gh: async args => {
        calls.push(args);
        throw Object.assign(new Error('Request connection timed out'), { code: 'ETIMEDOUT' });
      }, sleep: async () => { throw new Error('Dispatch must not retry'); } }), error => {
      assert.match(error.message, /Remote run preserved/);
      assert.ok(error.message.includes(requestID));
      return true;
    });
    assert.equal(calls.length, 1);
    assert.deepEqual(calls[0].slice(0, 3), ['workflow', 'run', 'build-ipa.yml']);
  });
});

test('a corrupt download fails and still cancels and removes its remote build', async () => {
  await withDirectory(async directory => {
    const outputDirectory = join(directory, 'download');
    const { gh, calls } = githubFixture({ outputDirectory, corrupt: true });
    await assert.rejects(() => buildAndDownload({ repository: 'owner/repository', ref: 'main',
      sourceCommit: commit, outputDirectory, requestID, gh, sleep: async () => {} }), /checksum|hash/i);
    assert.ok(calls.some(call => call.startsWith('run cancel 17')));
    assert.ok(calls.some(call => call.includes('DELETE repos/owner/repository/actions/artifacts/42')));
    assert.ok(calls.some(call => call.includes('DELETE repos/owner/repository/actions/runs/17')));
  });
});

test('failed dispatch never deletes an unrelated workflow run', async () => {
  await withDirectory(async directory => {
    const outputDirectory = join(directory, 'download');
    const { gh, calls } = githubFixture({ outputDirectory, dispatchFailure: true });
    await assert.rejects(() => buildAndDownload({ repository: 'owner/repository', ref: 'main',
      sourceCommit: commit, outputDirectory, requestID, gh, sleep: async () => {} }), /Dispatch failed/);
    assert.equal(calls.some(call => call.includes('DELETE') || call.startsWith('run cancel')), false);
  });
});

test('remote cleanup failure is reported even when the local IPA verified', async () => {
  await withDirectory(async directory => {
    const outputDirectory = join(directory, 'download');
    const fixture = githubFixture({ outputDirectory });
    const gh = async args => {
      if (args[0] === 'api' && args[2] === 'DELETE' && args[3].endsWith('/runs/17')) {
        throw new Error('Actions deletion denied');
      }
      return fixture.gh(args);
    };
    await assert.rejects(() => buildAndDownload({ repository: 'owner/repository', ref: 'main',
      sourceCommit: commit, outputDirectory, requestID, gh, sleep: async () => {} }), /Remote cleanup failed/);
    await verifyDownloadedIPA(outputDirectory, commit);
  });
});

test('an existing local directory is preserved without dispatching a build', async () => {
  await withDirectory(async outputDirectory => {
    const marker = join(outputDirectory, 'keep.txt');
    await writeFile(marker, 'existing download');
    let called = false;
    await assert.rejects(() => buildAndDownload({ repository: 'owner/repository', ref: 'main',
      sourceCommit: commit, outputDirectory, requestID,
      gh: async () => { called = true; throw new Error('Must not dispatch'); } }), /new output directory/);
    assert.equal(called, false);
  });
});

for (const failureKind of ['source error', 'large compiler failure log', 'logs unavailable']) {
  test(`failed builds preserve local diagnostics before deleting the run (${failureKind})`, async () => {
    await withDirectory(async directory => {
      const outputDirectory = join(directory, 'failed-build');
      const calls = [];
      const logsUnavailable = failureKind === 'logs unavailable';
      const largeLog = failureKind === 'large compiler failure log';
      const compilerError = largeLog ? 'Command SwiftCompile failed with a nonzero exit code' :
        '/runner/App/MeetingView.swift:42:12: error: no exact matches in call to initializer';
      const failedLog = (largeLog ? 'compiler progress\n'.repeat(300_000) : '') +
        `build\tBuild unsigned device app\t2026-10-26T12:00:00Z ${compilerError}\n** BUILD FAILED **\n`;
      const gh = async (args, options = {}) => {
        calls.push(args.join(' '));
        if (args[0] === 'workflow') return '';
        if (args[0] === 'run' && args[1] === 'list') return JSON.stringify([
          { databaseId: 99, displayTitle: 'IPA unrelated-request' },
          { databaseId: 17, displayTitle: `IPA ${requestID}` }
        ]);
        if (args[0] === 'run' && args[1] === 'view') {
          assert.equal(args[2], '17');
          assert.ok(args.includes('--log-failed'));
          if (logsUnavailable) throw new Error('Logs unavailable');
          if (Buffer.byteLength(failedLog) > (options.maxBuffer ?? 4 * 1024 * 1024)) {
            throw new Error('stdout maxBuffer length exceeded');
          }
          return failedLog;
        }
        if (args[0] === 'api' && args[1].endsWith('/artifacts')) return JSON.stringify({ artifacts: [] });
        if (args[0] === 'api' && args[1].endsWith('/jobs?per_page=100')) return JSON.stringify([{ jobs: [] }]);
        if (args[0] === 'api' && args[1].endsWith('/runs/17')) return JSON.stringify({
          head_sha: commit, status: 'completed', conclusion: 'failure'
        });
        if (args[0] === 'api' && args[1] === '--method') {
          assert.equal(args[2], 'DELETE');
          assert.equal(args[3], 'repos/owner/repository/actions/runs/17');
          // The diagnostics must already be durable before their source is removed.
          const log = await readFile(join(outputDirectory, 'build-failure.log'), 'utf8');
          if (logsUnavailable) assert.match(log, /Failed-job log unavailable: Logs unavailable/);
          else assert.equal(log, failedLog);
          const report = JSON.parse(await readFile(join(outputDirectory, 'build-failure.json'), 'utf8'));
          assert.equal(report.sourceCommit, commit);
          assert.equal(report.runID, 17);
          assert.equal(report.conclusion, 'failure');
          assert.equal(report.logError, logsUnavailable ? 'Logs unavailable' : null);
          return '';
        }
        throw new Error(`Unexpected CLI call: ${args.join(' ')}`);
      };
      await assert.rejects(() => buildAndDownload({ repository: 'owner/repository', ref: 'main',
        sourceCommit: commit, outputDirectory, requestID, gh, sleep: async () => {} }), error => {
        assert.match(error.message, /without a transferable artifact/);
        assert.ok(error.message.includes(join(outputDirectory, 'build-failure.log')));
        if (logsUnavailable) assert.match(error.message, /Failed-job log unavailable/);
        else assert.ok(error.message.includes(compilerError));
        return true;
      });
      assert.ok(calls.findIndex(call => call.startsWith('run view 17')) <
        calls.findIndex(call => call.includes('DELETE repos/owner/repository/actions/runs/17')));
      assert.equal(calls.some(call => call.startsWith('run download') || call.includes('/runs/99')), false);
    });
  });
}

for (const failureKind of ['runner annotations', 'check output unavailable', 'jobs unavailable', 'annotations unavailable',
  'long raw log', 'escaped raw log', 'raw log unavailable']) {
  test(`an interrupted build preserves GitHub job diagnostics (${failureKind})`, async () => {
    await withDirectory(async directory => {
      const outputDirectory = join(directory, 'interrupted-build');
      const partialLog = 'SwiftExplicitDependencyGeneratePcm arm64 UIKit.pcm\n';
      const longLine = 'SwiftCompile ' + 'x'.repeat(80 * 1024);
      const crashLine = 'While emitting IR SIL function "compiler-generated-thunk"';
      const fullLog = partialLog + (failureKind === 'long raw log' ? `${longLine}\n${crashLine}\n** BUILD FAILED **\n` : '');
      const runnerMessage = 'The hosted runner lost communication with the server.';
      const summary = 'Build worker stopped before compiler finished.';
      const job = { id: 42, name: 'build', status: 'completed', conclusion: 'failure',
        check_run_url: 'https://api.github.com/owner/repository/check-runs/700',
        steps: [{ name: 'Build unsigned device app', conclusion: 'failure' }] };
      let deleted = false;
      let usedFallback = false;
      const gh = async args => {
        if (args[0] === 'workflow') return '';
        if (args[0] === 'run' && args[1] === 'list') return JSON.stringify([
          { databaseId: 17, displayTitle: `IPA ${requestID}` }
        ]);
        if (args[0] === 'run' && args[1] === 'view') { usedFallback = true; return partialLog; }
        if (args[0] === 'api' && args[1].endsWith('/artifacts')) return JSON.stringify({ artifacts: [] });
        if (args[0] === 'api' && args[1].endsWith('/runs/17')) return JSON.stringify({
          head_sha: commit, status: 'completed', conclusion: 'failure'
        });
        if (args[0] === 'api' && args[1].endsWith('/jobs?per_page=100')) {
          assert.ok(args.includes('--paginate') && args.includes('--slurp'));
          if (failureKind === 'jobs unavailable') throw new Error('Jobs API unavailable');
          return JSON.stringify([{ jobs: [{ name: 'unrelated success', conclusion: 'success' }] }, { jobs: [job] }]);
        }
        if (args[0] === 'api' && args[1] === 'repos/owner/repository/actions/jobs/42/logs') {
          if (failureKind === 'raw log unavailable') throw new Error('Full job log unavailable');
          if (failureKind === 'escaped raw log') {
            if (!args.includes('--allow-escape-sequences')) throw new Error('the response contains terminal escape sequences');
            return `\u001b[31m${fullLog}\u001b[0m`;
          }
          return fullLog;
        }
        if (args[0] === 'api' && args[1] === 'repos/owner/repository/check-runs/700') {
          if (failureKind === 'check output unavailable') throw new Error('Check output unavailable');
          return JSON.stringify({ output: { summary } });
        }
        if (args[0] === 'api' && args[1] === 'repos/owner/repository/check-runs/700/annotations?per_page=100') {
          assert.ok(args.includes('--paginate') && args.includes('--slurp'));
          if (failureKind === 'annotations unavailable') throw new Error('Annotations API unavailable');
          return JSON.stringify([
            [{ annotation_level: 'warning', message: 'An unrelated warning' }],
            [{ annotation_level: 'failure', message: runnerMessage }]
          ]);
        }
        if (args[0] === 'api' && args[1] === '--method') {
          assert.deepEqual(args.slice(2), ['DELETE', 'repos/owner/repository/actions/runs/17']);
          const log = await readFile(join(outputDirectory, 'build-failure.log'), 'utf8');
          const report = JSON.parse(await readFile(join(outputDirectory, 'build-failure.json'), 'utf8'));
          assert.ok(log.includes(partialLog));
          assert.equal(log.includes('\u001b'), false, 'Terminal controls are removed from captured logs');
          if (failureKind === 'long raw log') {
            assert.ok(log.includes(longLine));
            assert.ok(log.includes(crashLine), 'The compiler failure after a line over 64 KiB must survive');
          }
          assert.equal(report.logError, null);
          if (failureKind === 'jobs unavailable') {
            assert.deepEqual(report.jobs, []);
            assert.match(log, /Jobs API unavailable/);
          } else {
            assert.equal(report.jobs.length, 1);
            assert.deepEqual(report.jobs[0].steps, job.steps);
            if (failureKind === 'annotations unavailable') {
              assert.deepEqual(report.jobs[0].annotations, []);
              assert.ok(log.includes(summary));
            } else {
              assert.equal(report.jobs[0].annotations.length, 2);
              assert.ok(log.includes(runnerMessage));
            }
          }
          assert.equal(report.diagnosticErrors.length,
            ['runner annotations', 'long raw log', 'escaped raw log'].includes(failureKind) ? 0 : 1);
          deleted = true;
          return '';
        }
        throw new Error(`Unexpected CLI call: ${args.join(' ')}`);
      };
      await assert.rejects(() => buildAndDownload({ repository: 'owner/repository', ref: 'main',
        sourceCommit: commit, outputDirectory, requestID, gh, sleep: async () => {} }), error => {
        assert.match(error.message, /Build finished \(failure\)/);
        if (!['jobs unavailable', 'annotations unavailable'].includes(failureKind)) {
          assert.ok(error.message.includes(runnerMessage));
        } else if (failureKind === 'annotations unavailable') assert.ok(error.message.includes(summary));
        else assert.match(error.message, /Some GitHub job diagnostics were unavailable/);
        if (failureKind === 'long raw log') assert.ok(error.message.includes(crashLine));
        return true;
      });
      assert.equal(deleted, true, 'Remote cleanup follows durable local job diagnostics');
      assert.equal(usedFallback, ['jobs unavailable', 'raw log unavailable'].includes(failureKind));
    });
  });
}
