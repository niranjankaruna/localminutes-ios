import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
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
