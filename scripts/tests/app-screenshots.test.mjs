import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { lstat, mkdir, mkdtemp, readFile, readdir, rm, rmdir, symlink, writeFile } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { collectScreenshots, expectedScreenshotNames, replaceScreenshots, verifyScreenshotBundle, verifyScreenshots } from '../app-screenshots.mjs';
import { captureAndDownload } from '../download-screenshots.mjs';

const commit = 'a'.repeat(40);
const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=', 'base64');

async function withProject(body) {
  const parent = resolve('.agent-local');
  await mkdir(parent, { recursive: true });
  const root = await mkdtemp(join(parent, 'screenshot-test-'));
  try { await mkdir(join(root, '.agent-local')); await body(root); }
  finally {
    assert.equal(dirname(resolve(root)), parent);
    await rm(root, { recursive: true, force: true });
  }
}

async function exportedAttachments(root) {
  const directory = join(root, `attachments-${randomUUID()}`);
  await mkdir(directory);
  const attachments = [];
  for (const filename of await expectedScreenshotNames()) {
    const match = /^(.*)_(light|dark)\.png$/.exec(filename);
    const exportedFileName = `${randomUUID()}.png`;
    await writeFile(join(directory, exportedFileName), png);
    attachments.push({ exportedFileName,
      suggestedHumanReadableName: `appui__${match[2]}__${match[1]}___0_${randomUUID()}.png` });
  }
  await writeFile(join(directory, 'manifest.json'), JSON.stringify([{ attachments }]));
  return directory;
}

async function prepareDownload(root, outputDirectory) {
  return collectScreenshots({ attachmentsDirectory: await exportedAttachments(root), outputDirectory,
    sourceCommit: commit, device: 'Synthetic PNG test fixture, not an iOS capture' });
}

test('exported XCTest attachments get stable meaningful names, complete light/dark coverage, and verified receipts', async () => {
  await withProject(async root => {
    const directory = await prepareDownload(root, join(root, 'download'));
    const names = await expectedScreenshotNames();
    assert.equal(names.length, 82);
    assert.ok(names.includes('meeting_summary_light.png') && names.includes('record_active_dark.png'));
    assert.equal(await verifyScreenshots(directory, commit), directory);
    assert.deepEqual((await readdir(directory)).sort(), [...names, 'manifest.json'].sort());
    await assert.rejects(() => verifyScreenshots(directory, 'b'.repeat(40)), /source commit/);
    await writeFile(join(directory, names[0]), Buffer.alloc(png.length));
    await assert.rejects(() => verifyScreenshots(directory, commit), /PNG/);
  });
});

test('missing and duplicate captures are rejected before publishing an incomplete set', async () => {
  await withProject(async root => {
    const attachmentsDirectory = await exportedAttachments(root);
    const manifestPath = join(attachmentsDirectory, 'manifest.json');
    const manifest = JSON.parse(await readFile(manifestPath, 'utf8'));
    const removed = manifest[0].attachments.pop();
    await writeFile(manifestPath, JSON.stringify(manifest));
    const outputDirectory = join(root, 'download');
    const options = { attachmentsDirectory, outputDirectory, sourceCommit: commit, device: 'Fixture' };
    await assert.rejects(() => collectScreenshots(options), /incomplete/);
    await assert.rejects(() => lstat(outputDirectory), { code: 'ENOENT' });
    manifest[0].attachments.push(removed, removed);
    await writeFile(manifestPath, JSON.stringify(manifest));
    await assert.rejects(() => collectScreenshots(options), /Duplicate capture/);
  });
});

test('untrusted attachment paths and extra download files are rejected', async () => {
  await withProject(async root => {
    const attachmentsDirectory = await exportedAttachments(root);
    const manifestPath = join(attachmentsDirectory, 'manifest.json');
    const manifest = JSON.parse(await readFile(manifestPath, 'utf8'));
    manifest[0].attachments[0].exportedFileName = '../outside.png';
    await writeFile(manifestPath, JSON.stringify(manifest));
    await assert.rejects(() => collectScreenshots({ attachmentsDirectory, outputDirectory: join(root, 'bad'),
      sourceCommit: commit, device: 'Fixture' }), /Unsafe/);
    const directory = await prepareDownload(root, join(root, 'download'));
    await writeFile(join(directory, 'unexpected.txt'), 'Not part of the screenshot set');
    await assert.rejects(() => verifyScreenshots(directory, commit), /contents/);
  });
});

test('a failed scene exports diagnostics and a checked log without replacing the previous gallery', async () => {
  await withProject(async root => {
    const attachmentsDirectory = await exportedAttachments(root);
    const manifestPath = join(attachmentsDirectory, 'manifest.json');
    const manifest = JSON.parse(await readFile(manifestPath, 'utf8'));
    manifest[0].attachments[0].suggestedHumanReadableName =
      manifest[0].attachments[0].suggestedHumanReadableName.replace('appui__', 'diagnostic__');
    await writeFile(manifestPath, JSON.stringify(manifest));
    const logFile = join(root, 'test.log');
    await writeFile(logFile, 'APPUI_FAILURE: expected view did not become ready\n');
    const destination = join(root, 'AppUI_Screenshots');
    await mkdir(destination);
    await writeFile(join(destination, 'previous.png'), png);
    const stagingDirectory = await collectScreenshots({ attachmentsDirectory,
      outputDirectory: join(root, '.agent-local', `screenshots-${randomUUID()}`),
      sourceCommit: commit, device: 'Fixture', allowIncomplete: true, captureSucceeded: false, logFile });
    const report = await verifyScreenshotBundle(stagingDirectory, commit);
    assert.equal(report.complete, false);
    assert.equal(report.missingScreenshots.length, 1);
    assert.equal(report.diagnostics.length, 1);
    assert.equal(report.screenshots.length, 81);
    assert.equal(await readFile(join(stagingDirectory, 'capture.log'), 'utf8'), await readFile(logFile, 'utf8'));
    await assert.rejects(() => replaceScreenshots({ repositoryRoot: root, stagingDirectory, sourceCommit: commit }),
      /Capture failed.*Previous screenshots were not replaced/);
    assert.deepEqual(await readdir(destination), ['previous.png']);
    await writeFile(join(stagingDirectory, 'capture.log'), 'Changed');
    await assert.rejects(() => verifyScreenshotBundle(stagingDirectory, commit), /log checksum/);
  });
});

test('build failures without an xcresult still produce a downloadable failure report', async () => {
  await withProject(async root => {
    const logFile = join(root, 'build.log');
    await writeFile(logFile, 'Build failed before tests started\n');
    const directory = await collectScreenshots({ attachmentsDirectory: join(root, 'no-attachments'),
      outputDirectory: join(root, 'report'), sourceCommit: commit, device: 'Fixture',
      allowIncomplete: true, captureSucceeded: false, logFile });
    const report = await verifyScreenshotBundle(directory, commit);
    assert.equal(report.screenshots.length, 0);
    assert.equal(report.missingScreenshots.length, 82);
    await assert.rejects(() => verifyScreenshots(directory, commit), /Capture failed/);
  });
});

test('a verified repeat replaces the old folder and removes obsolete screenshot names', async () => {
  await withProject(async root => {
    const destination = join(root, 'AppUI_Screenshots');
    await mkdir(destination);
    await writeFile(join(destination, 'old_screen.png'), png);
    await writeFile(join(root, 'keep.txt'), 'Other project content');
    const stagingDirectory = await prepareDownload(root, join(root, '.agent-local', `screenshots-${randomUUID()}`));
    assert.equal(await replaceScreenshots({ repositoryRoot: root, stagingDirectory, sourceCommit: commit }), destination);
    await verifyScreenshots(destination, commit);
    await assert.rejects(() => lstat(join(destination, 'old_screen.png')), { code: 'ENOENT' });
    assert.equal(await readFile(join(root, 'keep.txt'), 'utf8'), 'Other project content');
    assert.deepEqual(await readdir(join(root, '.agent-local')), []);
  });
});

test('an invalid new set leaves previous local screenshots intact', async () => {
  await withProject(async root => {
    const destination = join(root, 'AppUI_Screenshots');
    await mkdir(destination);
    await writeFile(join(destination, 'previous.png'), png);
    const stagingDirectory = await prepareDownload(root, join(root, '.agent-local', `screenshots-${randomUUID()}`));
    await rm(join(stagingDirectory, (await expectedScreenshotNames())[0]));
    await assert.rejects(() => replaceScreenshots({ repositoryRoot: root, stagingDirectory, sourceCommit: commit }));
    assert.deepEqual(await readdir(destination), ['previous.png']);
  });
});

test('replacement refuses a linked destination and leaves its target untouched', async () => {
  await withProject(async root => {
    const outside = join(root, 'other-content');
    await mkdir(outside);
    await writeFile(join(outside, 'keep.txt'), 'Keep');
    await symlink(outside, join(root, 'AppUI_Screenshots'), 'junction');
    const stagingDirectory = await prepareDownload(root, join(root, '.agent-local', `screenshots-${randomUUID()}`));
    await assert.rejects(() => replaceScreenshots({ repositoryRoot: root, stagingDirectory, sourceCommit: commit }), /real directory/);
    assert.equal(await readFile(join(outside, 'keep.txt'), 'utf8'), 'Keep');
  });
});

for (const captureFailed of [false, true]) {
test(`screenshot transfer cleans its remote run and ${captureFailed ? 'preserves local failure diagnostics' : 'replaces a complete gallery'}`, async () => {
  await withProject(async root => {
    const requestID = randomUUID();
    let completed = false, artifactExists = true;
    const calls = [];
    const gh = async args => {
      calls.push(args.join(' '));
      if (args[0] === 'workflow') {
        assert.equal(args[2], 'app-screenshots.yml');
        return '';
      }
      if (args[0] === 'run' && args[1] === 'list') return JSON.stringify([
        { databaseId: 99, displayTitle: 'Screenshots unrelated' },
        { databaseId: 17, displayTitle: `Screenshots ${requestID}` }
      ]);
      if (args[0] === 'run' && args[1] === 'download') {
        assert.ok(args.includes('app-ui-screenshots-transfer'));
        const directory = args[args.indexOf('--dir') + 1];
        // The shared downloader creates the directory before invoking gh.
        await rmdir(directory);
        await prepareDownload(root, directory);
        if (captureFailed) {
          const manifestPath = join(directory, 'manifest.json');
          const report = JSON.parse(await readFile(manifestPath, 'utf8'));
          report.complete = false;
          report.captureSucceeded = false;
          await writeFile(manifestPath, JSON.stringify(report));
        }
        return '';
      }
      if (args[0] === 'run' && args[1] === 'cancel') { completed = true; return ''; }
      if (args[0] === 'api' && args[1] === '--method') {
        if (args[3].endsWith('/artifacts/42')) { artifactExists = false; completed = true; }
        else assert.ok(args[3].endsWith('/runs/17'));
        return '';
      }
      if (args[0] === 'api' && args[1].endsWith('/artifacts')) return JSON.stringify({
        artifacts: artifactExists ? [{ id: 42, name: 'app-ui-screenshots-transfer', expired: false }] : []
      });
      if (args[0] === 'api' && args[1].endsWith('/runs/17')) return JSON.stringify({
        head_sha: commit, status: completed ? 'completed' : 'in_progress', conclusion: captureFailed ? 'failure' : 'success'
      });
      throw new Error(`Unexpected CLI call: ${args.join(' ')}`);
    };
    const transfer = captureAndDownload({ repositoryRoot: root, repository: 'owner/repo', ref: 'main',
      sourceCommit: commit, requestID, gh, sleep: async () => {} });
    if (captureFailed) {
      await assert.rejects(() => transfer, /Capture failed/);
      const report = await verifyScreenshotBundle(join(root, '.agent-local', `screenshots-${requestID}`), commit);
      assert.equal(report.complete, false);
      await assert.rejects(() => lstat(join(root, 'AppUI_Screenshots')), { code: 'ENOENT' });
    } else {
      const directory = await transfer;
      assert.equal(directory, join(root, 'AppUI_Screenshots'));
      await verifyScreenshots(directory, commit);
    }
    const deletion = calls.findIndex(call => call.includes('DELETE repos/owner/repo/actions/artifacts/42'));
    assert.ok(deletion > calls.findIndex(call => call.startsWith('run download 17')));
    assert.ok(calls.some(call => call.includes('DELETE repos/owner/repo/actions/runs/17')));
    assert.equal(calls.some(call => call.includes('/runs/99')), false);
  });
});
}
