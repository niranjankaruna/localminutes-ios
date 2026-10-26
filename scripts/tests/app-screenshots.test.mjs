import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { lstat, mkdir, mkdtemp, readFile, readdir, rename, rm, rmdir, symlink, writeFile } from 'node:fs/promises';
import { basename, dirname, join, resolve } from 'node:path';
import { collectScreenshots, expectedScreenshotNames, replaceScreenshots, resolveScreenshotSelection,
  verifyScreenshotBundle, verifyScreenshotGallery, verifyScreenshots } from '../app-screenshots.mjs';
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

async function exportedAttachments(root, selection) {
  const directory = join(root, `attachments-${randomUUID()}`);
  await mkdir(directory);
  const attachments = [];
  for (const filename of await expectedScreenshotNames(selection)) {
    const match = /^(.*)_(light|dark)\.png$/.exec(basename(filename));
    const exportedFileName = `${randomUUID()}.png`;
    await writeFile(join(directory, exportedFileName), png);
    attachments.push({ exportedFileName,
      suggestedHumanReadableName: `appui__${match[2]}__${match[1]}___0_${randomUUID()}.png` });
  }
  await writeFile(join(directory, 'manifest.json'), JSON.stringify([{ attachments }]));
  return directory;
}

async function prepareDownload(root, outputDirectory, { selection, sourceCommit = commit } = {}) {
  return collectScreenshots({ attachmentsDirectory: await exportedAttachments(root, selection), outputDirectory,
    sourceCommit, selection, device: 'Synthetic PNG test fixture, not an iOS capture' });
}

test('appearance, categories, exact screens, and related screens resolve one deduplicated capture plan', async () => {
  assert.equal((await expectedScreenshotNames()).length, 82);
  const transcript = await resolveScreenshotSelection({ appearance: 'dark', categories: 'transcript' });
  assert.deepEqual(await expectedScreenshotNames(transcript), [
    'dark/transcript/meeting_no_transcript_dark.png',
    'dark/transcript/meeting_transcript_dark.png',
    'dark/transcript/meeting_transcript_search_dark.png'
  ]);
  const exact = await resolveScreenshotSelection({ appearance: 'light', screens: 'meeting_transcript' });
  assert.deepEqual(await expectedScreenshotNames(exact), ['light/transcript/meeting_transcript_light.png']);
  const related = await resolveScreenshotSelection({ screens: 'meeting_transcript', related: true });
  assert.equal((await expectedScreenshotNames(related)).length, 6);
  const combined = await resolveScreenshotSelection({ categories: ' transcript,transcript ',
    screens: 'meeting_transcript, meeting_export,meeting_export' });
  assert.equal((await expectedScreenshotNames(combined)).length, 8);
  assert.deepEqual(await resolveScreenshotSelection({ categories: 'all' }), await resolveScreenshotSelection());
});

test('invalid filters fail before any hosted capture can start', async () => {
  for (const options of [
    { appearance: 'dakr' }, { categories: 'transcripts' }, { screens: 'meeting_transcrip' },
    { categories: 'summary,,transcript' }, { screens: 'meeting_summary,' }, { related: true },
    { screens: '../escape' }, { categories: '__proto__' }
  ]) await assert.rejects(() => resolveScreenshotSelection(options));
});

test('a selected bundle requires exactly the requested scenes and appearances', async () => {
  await withProject(async root => {
    const selection = await resolveScreenshotSelection({ appearance: 'light', categories: 'transcript' });
    const directory = await prepareDownload(root, join(root, 'selected'), { selection });
    const report = await verifyScreenshotBundle(directory, commit, selection);
    assert.equal(report.complete, true);
    assert.equal(report.screenshots.length, 3);
    const all = await resolveScreenshotSelection();
    await assert.rejects(() => verifyScreenshots(directory, commit, all), /selection does not match/);
    const attachmentsDirectory = await exportedAttachments(root);
    await assert.rejects(() => collectScreenshots({ attachmentsDirectory,
      outputDirectory: join(root, 'unrequested'), sourceCommit: commit, device: 'Fixture', selection }), /Unrequested/);
  });
});

test('exported XCTest attachments get stable meaningful names, complete light/dark coverage, and verified receipts', async () => {
  await withProject(async root => {
    const directory = await prepareDownload(root, join(root, 'download'));
    const names = await expectedScreenshotNames();
    assert.equal(names.length, 82);
    assert.ok(names.includes('light/summary/meeting_summary_light.png') && names.includes('dark/recording/record_active_dark.png'));
    assert.equal(await verifyScreenshots(directory, commit), directory);
    assert.deepEqual((await verifyScreenshotBundle(directory, commit)).screenshots.map(image => image.filename).sort(), names);
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
    const gallery = await verifyScreenshotGallery(destination);
    assert.equal(gallery.screenshots.length, 82);
    assert.ok(gallery.screenshots.every(image => image.sourceCommit === commit));
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

test('partial updates preserve other appearances and scenes with their original commit provenance', async () => {
  await withProject(async root => {
    const first = await prepareDownload(root, join(root, '.agent-local', `screenshots-${randomUUID()}`));
    const destination = await replaceScreenshots({ repositoryRoot: root, stagingDirectory: first, sourceCommit: commit });
    const oldGallery = await verifyScreenshotGallery(destination);
    const selection = await resolveScreenshotSelection({ appearance: 'dark', categories: 'transcript' });
    const newerCommit = 'b'.repeat(40);
    const stagingDirectory = await prepareDownload(root, join(root, '.agent-local', `screenshots-${randomUUID()}`),
      { selection, sourceCommit: newerCommit });
    await replaceScreenshots({ repositoryRoot: root, stagingDirectory, sourceCommit: newerCommit, selection });
    const gallery = await verifyScreenshotGallery(destination);
    const selectedPaths = await expectedScreenshotNames(selection);
    assert.equal(gallery.screenshots.length, 82);
    assert.deepEqual(gallery.lastCapture.selection, selection);
    for (const image of gallery.screenshots) {
      if (selectedPaths.includes(image.filename)) assert.equal(image.sourceCommit, newerCommit);
      else assert.deepEqual(image, oldGallery.screenshots.find(old => old.filename === image.filename));
    }
    assert.deepEqual(await readdir(join(root, '.agent-local')), []);
  });
});

test('a failed partial capture leaves the complete gallery untouched', async () => {
  await withProject(async root => {
    const first = await prepareDownload(root, join(root, '.agent-local', `screenshots-${randomUUID()}`));
    const destination = await replaceScreenshots({ repositoryRoot: root, stagingDirectory: first, sourceCommit: commit });
    const original = await readFile(join(destination, 'manifest.json'), 'utf8');
    const selection = await resolveScreenshotSelection({ appearance: 'light', screens: 'meeting_summary' });
    const stagingDirectory = await collectScreenshots({ attachmentsDirectory: join(root, 'missing'),
      outputDirectory: join(root, '.agent-local', `screenshots-${randomUUID()}`), sourceCommit: commit,
      device: 'Fixture', selection, allowIncomplete: true, captureSucceeded: false });
    const report = await verifyScreenshotBundle(stagingDirectory, commit, selection);
    assert.deepEqual(report.missingScreenshots, ['light/summary/meeting_summary_light.png']);
    await assert.rejects(() => replaceScreenshots({ repositoryRoot: root, stagingDirectory, sourceCommit: commit, selection }),
      /Capture failed/);
    assert.equal(await readFile(join(destination, 'manifest.json'), 'utf8'), original);
    await verifyScreenshotGallery(destination);
  });
});

test('an existing flat gallery is reorganized during a partial update without losing other captures', async () => {
  await withProject(async root => {
    const destination = await prepareDownload(root, join(root, 'AppUI_Screenshots'));
    const manifestPath = join(destination, 'manifest.json');
    const legacy = JSON.parse(await readFile(manifestPath, 'utf8'));
    const parents = new Set();
    for (const image of legacy.screenshots) {
      parents.add(dirname(image.filename));
      await rename(join(destination, image.filename), join(destination, basename(image.filename)));
      image.filename = basename(image.filename);
    }
    for (const category of parents) await rmdir(join(destination, category));
    await rmdir(join(destination, 'light'));
    await rmdir(join(destination, 'dark'));
    legacy.schemaVersion = 1;
    delete legacy.selection;
    await writeFile(manifestPath, JSON.stringify(legacy));
    await verifyScreenshots(destination, commit);
    const selection = await resolveScreenshotSelection({ appearance: 'light', screens: 'meeting_summary' });
    const stagingDirectory = await prepareDownload(root, join(root, '.agent-local', `screenshots-${randomUUID()}`), { selection });
    await replaceScreenshots({ repositoryRoot: root, stagingDirectory, sourceCommit: commit, selection });
    assert.equal((await verifyScreenshotGallery(destination)).screenshots.length, 82);
    assert.deepEqual((await readdir(destination)).sort(), ['dark', 'light', 'manifest.json']);
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

for (const scenario of ['full', 'failed', 'selected', 'mismatched']) {
test(`screenshot transfer verifies its selection and cleans its remote run: ${scenario}`, async () => {
  await withProject(async root => {
    const captureFailed = scenario === 'failed';
    const filtered = scenario === 'selected' || scenario === 'mismatched';
    const filters = filtered ? { appearance: 'dark', screens: 'meeting_summary', related: true } : {};
    const selection = await resolveScreenshotSelection(filters);
    const requestID = randomUUID();
    let completed = false, artifactExists = true;
    const calls = [];
    const gh = async args => {
      calls.push(args.join(' '));
      if (args[0] === 'workflow') {
        assert.equal(args[2], 'app-screenshots.yml');
        assert.ok(args.includes(`appearance=${filtered ? 'dark' : 'both'}`));
        assert.ok(args.includes(`screens=${filtered ? 'meeting_summary' : ''}`));
        assert.ok(args.includes(`related=${filtered}`));
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
        await prepareDownload(root, directory, { selection: scenario === 'mismatched' ? undefined : selection });
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
    const transfer = captureAndDownload({ ...filters, repositoryRoot: root, repository: 'owner/repo', ref: 'main',
      sourceCommit: commit, requestID, gh, sleep: async () => {} });
    if (captureFailed || scenario === 'mismatched') {
      await assert.rejects(() => transfer, captureFailed ? /Capture failed/ : /selection does not match/);
      const report = await verifyScreenshotBundle(join(root, '.agent-local', `screenshots-${requestID}`), commit);
      assert.equal(report.complete, !captureFailed);
      await assert.rejects(() => lstat(join(root, 'AppUI_Screenshots')), { code: 'ENOENT' });
    } else {
      const directory = await transfer;
      assert.equal(directory, join(root, 'AppUI_Screenshots'));
      const gallery = await verifyScreenshotGallery(directory);
      assert.deepEqual(gallery.lastCapture.selection, selection);
      assert.equal(gallery.screenshots.length, filtered ? 4 : 82);
    }
    const deletion = calls.findIndex(call => call.includes('DELETE repos/owner/repo/actions/artifacts/42'));
    assert.ok(deletion > calls.findIndex(call => call.startsWith('run download 17')));
    assert.ok(calls.some(call => call.includes('DELETE repos/owner/repo/actions/runs/17')));
    assert.equal(calls.some(call => call.includes('/runs/99')), false);
  });
});
}
