import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { lstat, mkdir, mkdtemp, readFile, readdir, rename, rm, rmdir, symlink, writeFile } from 'node:fs/promises';
import { basename, dirname, join, resolve } from 'node:path';
import { deflateSync } from 'node:zlib';
import { collectScreenshots, expectedScreenshotNames, replaceScreenshots, resolveScreenshotSelection,
  screenshotSpecifications, parseScreenshotCatalog, validateScreenshotEvidence,
  verifyScreenshotBundle, verifyScreenshotGallery, verifyScreenshots } from '../app-screenshots.mjs';
import { captureAndDownload } from '../download-screenshots.mjs';

const commit = 'a'.repeat(40);
const fullCount = 236;
// A valid, blank iPhone-sized PNG for transport/receipt tests, never UI evidence.
function pngChunk(type, data) {
  const payload = Buffer.concat([Buffer.from(type), data]);
  let crc = 0xffffffff;
  for (const byte of payload) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ (crc & 1 ? 0xedb88320 : 0);
  }
  const size = Buffer.alloc(4), checksum = Buffer.alloc(4);
  size.writeUInt32BE(data.length); checksum.writeUInt32BE((crc ^ 0xffffffff) >>> 0);
  return Buffer.concat([size, payload, checksum]);
}
const header = Buffer.alloc(13);
header.writeUInt32BE(640); header.writeUInt32BE(1136, 4); header[8] = 8; header[9] = 6;
const rows = Buffer.alloc((640 * 4 + 1) * 1136, 255);
for (let y = 0; y < 1136; y++) rows[y * (640 * 4 + 1)] = 0;
const png = Buffer.concat([Buffer.from('89504e470d0a1a0a', 'hex'), pngChunk('IHDR', header),
  pngChunk('IDAT', deflateSync(rows)), pngChunk('IEND', Buffer.alloc(0))]);

function syntheticEvidence(scene, appearance) {
  const spec = screenshotSpecifications[scene];
  const overlay = ['confirmation', 'menu', 'systemSheet', 'systemPermission', 'hostedActivity', 'hostedLaunch'].includes(spec.presentation);
  const checks = spec.required.map((identifier, index) => ({ identifier,
    frame: [20, 60 + index * 50, 200, 44], region: overlay ? 'overlay' : 'content',
    label: identifier === 'system.cancel' ? 'Cancel' : spec.expectedText?.[identifier] ?? 'Synthetic test element', enabled: true }));
  if (scene.endsWith('_variants')) {
    checks[1].frame = [20, 110, 150, 48];
    checks[2].frame = [52, 124, 95, 20]; checks[2].label = 'Download';
  }
  return { schemaVersion: 1, scene, appearance, presentation: spec.presentation,
    window: [0, 0, 320, 568], viewport: [0, 44, 320, spec.keyboard ? 300 : 516],
    chromeBounds: [[0, 0, 320, 44]], pixelWidth: 640, pixelHeight: 1136,
    stableSamples: 3, checks, alertTitle: spec.alertTitle ?? '', keyboardVisible: spec.keyboard === true,
    contract: { required: spec.required, presentation: spec.presentation, alertTitle: spec.alertTitle ?? '',
      keyboard: spec.keyboard === true, expectedText: spec.expectedText ?? {} } };
}

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
  const validations = [];
  for (const filename of await expectedScreenshotNames(selection)) {
    const match = /^(.*)_(light|dark)\.png$/.exec(basename(filename));
    const exportedFileName = `${randomUUID()}.png`;
    await writeFile(join(directory, exportedFileName), png);
    attachments.push({ exportedFileName,
      suggestedHumanReadableName: `appui__${match[2]}__${match[1]}___0_${randomUUID()}.png` });
    const proofName = `${randomUUID()}.json`;
    await writeFile(join(directory, proofName), JSON.stringify(syntheticEvidence(match[1], match[2])));
    validations.push({ exportedFileName: proofName,
      suggestedHumanReadableName: `appui_validation__${match[2]}__${match[1]}___0_${randomUUID()}.json` });
  }
  await writeFile(join(directory, 'manifest.json'), JSON.stringify([{ attachments }, { attachments: validations }]));
  return directory;
}

async function prepareDownload(root, outputDirectory, { selection, sourceCommit = commit } = {}) {
  return collectScreenshots({ attachmentsDirectory: await exportedAttachments(root, selection), outputDirectory,
    sourceCommit, selection, device: 'Synthetic PNG test fixture, not an iOS capture' });
}

async function addRetiredCaptures(directory, manifest) {
  manifest.schemaVersion = 2;
  const scenes = ['models_parakeet_compatibility', 'models_parakeet_requirements',
    'models_import_picker', 'models_pack_picker'];
  const names = [];
  for (const scene of scenes) {
    for (const appearance of ['light', 'dark']) {
      const filename = `${appearance}/parakeet/${scene}_${appearance}.png`;
      names.push(filename);
      await writeFile(join(directory, filename), png);
      const { validation, ...legacyImage } = manifest.screenshots[0];
      manifest.screenshots.push({ ...legacyImage, filename });
    }
  }
  (manifest.selection ?? manifest.lastCapture.selection).scenes.push(...scenes);
  return names;
}

test('appearance, categories, exact screens, and related screens resolve one deduplicated capture plan', async () => {
  assert.equal((await expectedScreenshotNames()).length, fullCount);
  const transcript = await resolveScreenshotSelection({ appearance: 'dark', categories: 'transcript' });
  assert.deepEqual(await expectedScreenshotNames(transcript), [
    'dark/transcript/meeting_no_transcript_dark.png',
    'dark/transcript/meeting_transcript_dark.png',
    'dark/transcript/meeting_transcript_no_results_dark.png',
    'dark/transcript/meeting_transcript_recovering_dark.png',
    'dark/transcript/meeting_transcript_search_dark.png'
  ]);
  const exact = await resolveScreenshotSelection({ appearance: 'light', screens: 'meeting_transcript' });
  assert.deepEqual(await expectedScreenshotNames(exact), ['light/transcript/meeting_transcript_light.png']);
  const related = await resolveScreenshotSelection({ screens: 'meeting_transcript', related: true });
  assert.equal((await expectedScreenshotNames(related)).length, 10);
  const combined = await resolveScreenshotSelection({ categories: ' transcript,transcript ',
    screens: 'meeting_transcript, meeting_export,meeting_export' });
  assert.equal((await expectedScreenshotNames(combined)).length, 12);
  assert.deepEqual(await resolveScreenshotSelection({ categories: 'all' }), await resolveScreenshotSelection());
});

test('invalid filters fail before any hosted capture can start', async () => {
  for (const options of [
    { appearance: 'dakr' }, { categories: 'transcripts' }, { screens: 'meeting_transcrip' },
    { categories: 'summary,,transcript' }, { screens: 'meeting_summary,' }, { related: true },
    { screens: '../escape' }, { categories: '__proto__' },
    { screens: 'models_import_picker' }, { screens: 'models_pack_picker' },
    { screens: 'models_parakeet_compatibility' }, { screens: 'models_parakeet_requirements' }
  ]) await assert.rejects(() => resolveScreenshotSelection(options));
});

test('one source catalog covers every confirmation, variant layout, editor, and loading surface', async () => {
  const source = await readFile(new URL('../../Shared/AppScreenshotScene.swift', import.meta.url), 'utf8');
  assert.deepEqual(parseScreenshotCatalog(source), screenshotSpecifications);
  const confirmations = Object.entries(screenshotSpecifications).filter(([, spec]) => spec.presentation === 'confirmation');
  assert.deepEqual(confirmations.map(([scene]) => scene).sort(), [
    'meeting_summary_reset_confirmation', 'meeting_delete_confirmation', 'models_remove_confirmation',
    'meetings_restore_confirmation', 'meetings_delete_confirmation', 'meeting_summary_delete_confirmation',
    'meeting_summary_replace_confirmation', 'meeting_answer_replace_confirmation'
  ].sort());
  for (const [, spec] of confirmations) assert.ok(spec.required.includes('system.cancel') && spec.alertTitle);
  for (const scene of ['models_summary_variants', 'models_speech_variants', 'meeting_notes_editor',
    'meeting_summary_structured', 'meeting_answer_editor', 'meeting_transcript_recovering',
    'meetings_loading', 'settings_storage_preparing', 'launch_screen']) {
    assert.ok(screenshotSpecifications[scene], `Missing ${scene}`);
  }
  assert.throws(() => parseScreenshotCatalog(source.replace('"system.cancel"', '"not.cancel"')), /Cancel/);
  assert.throws(() => parseScreenshotCatalog(source.replace(/\s*case \.recordIdle: #".*"#/, '')), /contract/);
});

test('native receipts reject clipping, unstable layouts, wrong presentation, and the stretched Download regression', () => {
  const scene = 'models_summary_variants';
  const valid = syntheticEvidence(scene, 'light');
  const path = 'light/models/models_summary_variants_light.png';
  const facts = { width: 640, height: 1136 };
  assert.equal(validateScreenshotEvidence(valid, path, facts), valid);
  for (const mutate of [
    proof => { proof.checks[0].frame[1] = 0; },
    proof => { proof.stableSamples = 1; },
    proof => { proof.appearance = 'dark'; },
    proof => { proof.presentation = 'confirmation'; },
    proof => { proof.pixelHeight = 2; },
    proof => { proof.keyboardVisible = true; },
    proof => { proof.checks[1].frame[3] = 180; },
    proof => { proof.checks[2].label = ''; },
    proof => { proof.checks[2].frame[0] = 250; },
    proof => { proof.checks.pop(); },
    proof => { proof.checks[0].region = 'overlay'; }
  ]) {
    const invalid = structuredClone(valid); mutate(invalid);
    assert.throws(() => validateScreenshotEvidence(invalid, path, facts));
  }
  const confirmation = syntheticEvidence('meeting_delete_confirmation', 'dark');
  const confirmationPath = 'dark/library/meeting_delete_confirmation_dark.png';
  confirmation.alertTitle = 'Wrong dialog';
  assert.throws(() => validateScreenshotEvidence(confirmation, confirmationPath, facts), /title/);
  confirmation.alertTitle = screenshotSpecifications.meeting_delete_confirmation.alertTitle;
  confirmation.checks.find(check => check.identifier === 'system.cancel').enabled = false;
  assert.throws(() => validateScreenshotEvidence(confirmation, confirmationPath, facts), /Confirmation/);
  const paused = syntheticEvidence('models_download_paused', 'light');
  paused.checks[0].label = 'Downloading';
  assert.throws(() => validateScreenshotEvidence(paused, 'light/downloads/models_download_paused_light.png', facts), /Wrong visible state/);
});

test('historical receipts keep their original contract while fresh captures must match current targets', () => {
  const past = syntheticEvidence('meeting_summary', 'light');
  past.contract = { ...past.contract, required: ['old.summary.content'] };
  past.checks = [{ ...past.checks[0], identifier: 'old.summary.content' }];
  const path = 'light/summary/meeting_summary_light.png', image = { width: 640, height: 1136 };
  assert.equal(validateScreenshotEvidence(past, path, image, { historical: true }), past);
  assert.throws(() => validateScreenshotEvidence(past, path, image), /Capture contract/);
});

test('an image without native validation remains diagnostic and cannot replace the gallery', async () => {
  await withProject(async root => {
    const selection = await resolveScreenshotSelection({ appearance: 'light', screens: 'models_summary_variants' });
    const attachmentsDirectory = await exportedAttachments(root, selection);
    const manifestPath = join(attachmentsDirectory, 'manifest.json');
    const attachments = JSON.parse(await readFile(manifestPath, 'utf8'));
    attachments[1].attachments = [];
    await writeFile(manifestPath, JSON.stringify(attachments));
    const directory = await collectScreenshots({ attachmentsDirectory, outputDirectory: join(root, 'unverified'),
      sourceCommit: commit, device: 'Synthetic fixture', selection, allowIncomplete: true });
    const report = await verifyScreenshotBundle(directory, commit, selection);
    assert.equal(report.complete, false);
    assert.equal(report.screenshots.length, 0);
    assert.equal(report.diagnostics.length, 1);
    assert.match(report.validationFailures[0].reason, /Missing screenshot validation/);
    await assert.rejects(() => verifyScreenshots(directory, commit, selection), /Capture failed/);
  });
});

test('legacy 37-scene captures stay readable but cannot masquerade as newly validated captures', async () => {
  await withProject(async root => {
    const selection = { appearances: ['light', 'dark'], scenes: Object.keys(screenshotSpecifications).slice(0, 37) };
    const directory = await prepareDownload(root, join(root, 'legacy'), { selection });
    const path = join(directory, 'manifest.json');
    const manifest = JSON.parse(await readFile(path, 'utf8'));
    manifest.schemaVersion = 2;
    for (const image of manifest.screenshots) delete image.validation;
    await writeFile(path, JSON.stringify(manifest));
    assert.equal((await verifyScreenshotBundle(directory, commit, selection)).screenshots.length, 74);
    await assert.rejects(() => verifyScreenshots(directory, commit, selection, { requireValidation: true }), /native visibility/);
  });
});

test('unsafe, duplicate, and wrong-scene validation attachments are rejected', async () => {
  await withProject(async root => {
    const selection = await resolveScreenshotSelection({ appearance: 'light', screens: 'meeting_summary' });
    const attachmentsDirectory = await exportedAttachments(root, selection);
    const path = join(attachmentsDirectory, 'manifest.json');
    const manifest = JSON.parse(await readFile(path, 'utf8'));
    const proof = manifest[1].attachments[0];
    const options = { attachmentsDirectory, outputDirectory: join(root, 'invalid'), sourceCommit: commit,
      device: 'Fixture', selection };
    manifest[1].attachments.push(proof);
    await writeFile(path, JSON.stringify(manifest));
    await assert.rejects(() => collectScreenshots(options), /Duplicate capture validation/);
    manifest[1].attachments.pop();
    const validName = proof.exportedFileName;
    proof.exportedFileName = '../escape.json';
    await writeFile(path, JSON.stringify(manifest));
    await assert.rejects(() => collectScreenshots(options), /Unsafe validation/);
    proof.exportedFileName = validName;
    await writeFile(path, JSON.stringify(manifest));
    const evidence = syntheticEvidence('meeting_summary', 'light');
    evidence.scene = 'meeting_notes';
    await writeFile(join(attachmentsDirectory, validName), JSON.stringify(evidence));
    await assert.rejects(() => collectScreenshots(options), /Validation scene mismatch/);
  });
});

test('a selected bundle requires exactly the requested scenes and appearances', async () => {
  await withProject(async root => {
    const selection = await resolveScreenshotSelection({ appearance: 'light', categories: 'transcript' });
    const directory = await prepareDownload(root, join(root, 'selected'), { selection });
    const report = await verifyScreenshotBundle(directory, commit, selection);
    assert.equal(report.complete, true);
    assert.equal(report.screenshots.length, 5);
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
    assert.equal(names.length, fullCount);
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
    assert.equal(report.screenshots.length, fullCount - 1);
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
    assert.equal(report.missingScreenshots.length, fullCount);
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
    assert.equal(gallery.screenshots.length, fullCount);
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
    assert.equal(gallery.screenshots.length, fullCount);
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

test('partial updates preserve retired scenes in an older gallery until a complete recapture replaces them', async () => {
  await withProject(async root => {
    const first = await prepareDownload(root, join(root, '.agent-local', `screenshots-${randomUUID()}`));
    const destination = await replaceScreenshots({ repositoryRoot: root, stagingDirectory: first, sourceCommit: commit });
    const gallery = await verifyScreenshotGallery(destination);
    const retiredNames = await addRetiredCaptures(destination, gallery);
    await writeFile(join(destination, 'manifest.json'), JSON.stringify(gallery));
    assert.equal((await verifyScreenshotGallery(destination)).screenshots.length, fullCount + 8);

    const selection = await resolveScreenshotSelection({ appearance: 'dark', screens: 'meeting_summary' });
    const newerCommit = 'b'.repeat(40);
    const partial = await prepareDownload(root, join(root, '.agent-local', `screenshots-${randomUUID()}`),
      { selection, sourceCommit: newerCommit });
    await replaceScreenshots({ repositoryRoot: root, stagingDirectory: partial, sourceCommit: newerCommit, selection });
    const updated = await verifyScreenshotGallery(destination);
    assert.equal(updated.screenshots.length, fullCount + 8);
    for (const filename of retiredNames) {
      assert.deepEqual(updated.screenshots.find(image => image.filename === filename),
        gallery.screenshots.find(image => image.filename === filename));
    }

    const complete = await prepareDownload(root, join(root, '.agent-local', `screenshots-${randomUUID()}`),
      { sourceCommit: newerCommit });
    await replaceScreenshots({ repositoryRoot: root, stagingDirectory: complete, sourceCommit: newerCommit });
    const current = await verifyScreenshotGallery(destination);
    assert.equal(current.screenshots.length, fullCount);
    for (const filename of retiredNames) await assert.rejects(() => lstat(join(destination, filename)), { code: 'ENOENT' });
  });
});

test('an existing flat gallery is reorganized during a partial update without losing other captures', async () => {
  await withProject(async root => {
    const destination = await prepareDownload(root, join(root, 'AppUI_Screenshots'));
    const manifestPath = join(destination, 'manifest.json');
    const legacy = JSON.parse(await readFile(manifestPath, 'utf8'));
    await addRetiredCaptures(destination, legacy);
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
    assert.equal((await verifyScreenshotGallery(destination)).screenshots.length, fullCount + 8);
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
      assert.equal(gallery.screenshots.length, (await expectedScreenshotNames(selection)).length);
    }
    const deletion = calls.findIndex(call => call.includes('DELETE repos/owner/repo/actions/artifacts/42'));
    assert.ok(deletion > calls.findIndex(call => call.startsWith('run download 17')));
    assert.ok(calls.some(call => call.includes('DELETE repos/owner/repo/actions/runs/17')));
    assert.equal(calls.some(call => call.includes('/runs/99')), false);
  });
});
}
