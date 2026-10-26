import assert from 'node:assert/strict';
import { createHash, randomUUID } from 'node:crypto';
import { copyFile, lstat, mkdir, readFile, readdir, realpath, rename, rm, writeFile } from 'node:fs/promises';
import { basename, dirname, join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const sceneSource = new URL('../Shared/AppScreenshotScene.swift', import.meta.url);
const pngSignature = Buffer.from('89504e470d0a1a0a', 'hex');

export const screenshotCategories = {
  recording: ['record_idle', 'record_speech_model_required', 'record_active', 'record_live_transcript', 'record_live_notes'],
  library: ['meetings_empty', 'meetings_history', 'meetings_actions', 'meetings_backup_ready',
    'meetings_restore_picker', 'meetings_search', 'meeting_delete_confirmation'],
  notes: ['meeting_notes'],
  transcript: ['meeting_transcript', 'meeting_transcript_search', 'meeting_no_transcript'],
  summary: ['meeting_summary', 'meeting_summary_reset_confirmation', 'meeting_no_summary', 'meeting_summary_model_required'],
  questions: ['meeting_questions_and_answers'],
  sharing: ['meeting_export', 'meeting_share_sheet'],
  models: ['models_speech', 'models_summary'],
  parakeet: ['models_parakeet_repository', 'models_parakeet_source', 'models_parakeet_compatibility',
    'models_parakeet_requirements', 'models_parakeet_download', 'models_import_picker', 'models_pack_picker', 'models_model_card'],
  downloads: ['models_downloading', 'models_verifying'],
  'installed-models': ['models_installed_summary', 'models_installed_details', 'models_remove_confirmation'],
  settings: ['models_storage_check', 'models_about', 'models_device']
};

async function catalogScenes() {
  const source = await readFile(sceneSource, 'utf8');
  const names = [...source.matchAll(/^\s*case \w+ = "([a-z0-9_]+)"$/gm)].map(match => match[1]);
  assert.ok(names.length > 0, 'The screenshot catalog must declare its scenes');
  assert.equal(new Set(names).size, names.length, 'Duplicate screenshot names in the catalog');
  assert.deepEqual(Object.values(screenshotCategories).flat().sort(), [...names].sort(),
    'Every screenshot scene must belong to exactly one category');
  return names;
}

function csv(value, label) {
  assert.equal(typeof value, 'string', `${label} must be a comma-separated string`);
  if (!value.trim()) return [];
  const items = value.split(',').map(item => item.trim());
  assert.ok(items.every(Boolean), `Empty item in ${label}`);
  return [...new Set(items)];
}

export async function resolveScreenshotSelection({ appearance = 'both', categories = '', screens = '', related = false } = {}) {
  const scenes = await catalogScenes();
  assert.ok(['both', 'light', 'dark'].includes(appearance), 'Appearance must be both, light, or dark');
  assert.equal(typeof related, 'boolean');
  const groups = csv(categories, 'categories'), requested = csv(screens, 'screens');
  assert.ok(groups.every(group => group === 'all' || Object.hasOwn(screenshotCategories, group)),
    `Unknown category. Choose: ${Object.keys(screenshotCategories).join(', ')}`);
  assert.ok(requested.every(scene => scenes.includes(scene)), 'Unknown screen. Use --list to see exact screen names');
  assert.ok(!related || requested.length > 0, '--related requires at least one screen');
  const selected = new Set(requested);
  for (const [category, members] of Object.entries(screenshotCategories)) {
    if (groups.includes(category) || (related && members.some(scene => selected.has(scene)))) {
      for (const scene of members) selected.add(scene);
    }
  }
  if (groups.includes('all') || (!groups.length && !requested.length)) scenes.forEach(scene => selected.add(scene));
  return { appearances: appearance === 'both' ? ['light', 'dark'] : [appearance],
    scenes: scenes.filter(scene => selected.has(scene)) };
}

async function checkedSelection(selection) {
  selection ??= await resolveScreenshotSelection();
  assert.ok(Array.isArray(selection.appearances) && Array.isArray(selection.scenes), 'Invalid screenshot selection');
  const normalized = await resolveScreenshotSelection({
    appearance: selection.appearances.length === 2 ? 'both' : selection.appearances[0],
    screens: selection.scenes.join(',')
  });
  assert.deepEqual(selection, normalized, 'Invalid or non-canonical screenshot selection');
  return normalized;
}

function screenshotPath(scene, appearance) {
  const category = Object.keys(screenshotCategories).find(key => screenshotCategories[key].includes(scene));
  assert.ok(category, `Unknown screenshot scene: ${scene}`);
  return `${appearance}/${category}/${scene}_${appearance}.png`;
}

export async function expectedScreenshotNames(selection) {
  const { scenes, appearances } = await checkedSelection(selection);
  return scenes.flatMap(scene => appearances.map(appearance => screenshotPath(scene, appearance))).sort();
}

async function imageFacts(file) {
  const info = await lstat(file);
  assert.ok(info.isFile() && info.size >= 45 && info.size <= 30 * 1024 * 1024,
    `Expected a regular PNG screenshot: ${basename(file)}`);
  const data = await readFile(file);
  assert.ok(data.subarray(0, 8).equals(pngSignature), 'Invalid PNG signature');
  assert.equal(data.readUInt32BE(8), 13, 'Invalid PNG header');
  assert.equal(data.toString('ascii', 12, 16), 'IHDR', 'Invalid PNG header');
  assert.equal(data.toString('ascii', data.length - 8, data.length - 4), 'IEND', 'Incomplete PNG');
  const width = data.readUInt32BE(16), height = data.readUInt32BE(20);
  assert.ok(width > 0 && height > 0, 'Empty screenshot');
  return { sizeBytes: data.length, width, height, sha256: createHash('sha256').update(data).digest('hex') };
}

async function logFacts(file) {
  const info = await lstat(file);
  assert.ok(info.isFile() && info.size <= 100 * 1024 * 1024, 'Expected a regular capture log');
  const data = await readFile(file);
  return { sizeBytes: data.length, sha256: createHash('sha256').update(data).digest('hex') };
}

function diagnosticPath(filename) {
  return filename.replace(/(^|\/)([^/]+)$/, '$1diagnostic_$2');
}

async function copyInto(source, directory, filename) {
  const target = join(directory, filename);
  await mkdir(dirname(target), { recursive: true });
  await copyFile(source, target);
}

async function verifyContents(directory, files) {
  const expected = new Set(files);
  for (const filename of files) {
    const parts = filename.split('/');
    for (let i = 1; i < parts.length; i++) expected.add(parts.slice(0, i).join('/') + '/');
  }
  const found = [];
  async function walk(prefix = '') {
    for (const name of await readdir(join(directory, prefix))) {
      const relative = prefix + name;
      const info = await lstat(join(directory, relative));
      assert.ok(info.isFile() || info.isDirectory(), 'Screenshot contents must not contain links');
      found.push(relative + (info.isDirectory() ? '/' : ''));
      if (info.isDirectory()) await walk(relative + '/');
    }
  }
  await walk();
  assert.deepEqual(found.sort(), [...expected].sort(), 'Unexpected screenshot download contents');
}

export async function collectScreenshots({ attachmentsDirectory, outputDirectory, sourceCommit, device,
  allowIncomplete = false, captureSucceeded = true, logFile, selection }) {
  assert.match(sourceCommit, /^[0-9a-f]{40}$/);
  assert.ok(typeof device === 'string' && device.length > 0);
  selection = await checkedSelection(selection);
  const rawManifest = await readFile(join(attachmentsDirectory, 'manifest.json'), 'utf8').catch(error => {
    if (allowIncomplete && error.code === 'ENOENT') return '[]';
    throw error;
  });
  const entries = JSON.parse(rawManifest);
  assert.ok(Array.isArray(entries), 'Unexpected xcresult attachment manifest');
  const images = new Map();
  const diagnostics = new Map();
  const expected = await expectedScreenshotNames(selection);
  for (const entry of entries) {
    for (const attachment of entry.attachments ?? []) {
      const match = /^(appui|diagnostic)__(light|dark)__([a-z0-9]+(?:_[a-z0-9]+)*)__/.exec(attachment.suggestedHumanReadableName ?? '');
      if (!match) continue;
      const exported = attachment.exportedFileName;
      assert.equal(typeof exported, 'string');
      assert.match(exported, /^[A-Za-z0-9_.-]+\.png$/i, 'Unsafe exported screenshot path');
      const sceneName = screenshotPath(match[3], match[2]);
      assert.ok(expected.includes(sceneName), `Unrequested screenshot: ${sceneName}`);
      const filename = match[1] === 'diagnostic' ? diagnosticPath(sceneName) : sceneName;
      const collection = match[1] === 'diagnostic' ? diagnostics : images;
      assert.ok(!collection.has(filename), `Duplicate capture: ${filename}`);
      collection.set(filename, join(attachmentsDirectory, exported));
    }
  }
  const missingScreenshots = expected.filter(filename => !images.has(filename));
  const complete = captureSucceeded && missingScreenshots.length === 0 && diagnostics.size === 0;
  if (!allowIncomplete) assert.ok(complete, 'The screenshot set is incomplete');
  await mkdir(outputDirectory);
  const screenshots = [];
  const diagnosticImages = [];
  for (const [filename, source] of [...images, ...diagnostics].sort(([a], [b]) => a.localeCompare(b))) {
    const facts = await imageFacts(source);
    await copyInto(source, outputDirectory, filename);
    (images.has(filename) ? screenshots : diagnosticImages).push({ filename, ...facts });
  }
  let log;
  if (logFile) {
    log = { filename: 'capture.log', ...await logFacts(logFile) };
    await copyFile(logFile, join(outputDirectory, log.filename));
  }
  await writeFile(join(outputDirectory, 'manifest.json'), JSON.stringify({
    schemaVersion: 2, selection, sourceCommit, device, fixtureData: true,
    capturedAt: new Date().toISOString(), complete, captureSucceeded, missingScreenshots,
    screenshots, diagnostics: diagnosticImages, ...(log ? { log } : {})
  }, null, 2) + '\n');
  await verifyScreenshotBundle(outputDirectory, sourceCommit, selection);
  return outputDirectory;
}

export async function verifyScreenshotBundle(directory, sourceCommit, requestedSelection) {
  assert.ok((await lstat(directory)).isDirectory(), 'Screenshot download must be a real directory');
  const manifestPath = join(directory, 'manifest.json');
  assert.ok((await lstat(manifestPath)).isFile(), 'Expected a regular screenshot manifest');
  const manifest = JSON.parse(await readFile(manifestPath, 'utf8'));
  assert.ok([1, 2].includes(manifest.schemaVersion), 'Unknown screenshot manifest version');
  assert.equal(manifest.sourceCommit, sourceCommit, 'Screenshot source commit does not match the request');
  assert.equal(manifest.fixtureData, true);
  assert.ok(typeof manifest.device === 'string' && manifest.device.length > 0);
  const selection = manifest.schemaVersion === 1 ? await resolveScreenshotSelection() : manifest.selection;
  assert.ok(selection, 'Missing screenshot selection');
  await checkedSelection(selection);
  if (requestedSelection) assert.deepEqual(selection, await checkedSelection(requestedSelection),
    'Screenshot selection does not match the request');
  const paths = await expectedScreenshotNames(selection);
  const expected = manifest.schemaVersion === 1 ? paths.map(name => basename(name)).sort() : paths;
  assert.equal(typeof manifest.captureSucceeded, 'boolean');
  assert.ok(Array.isArray(manifest.screenshots) && Array.isArray(manifest.diagnostics));
  const names = manifest.screenshots.map(image => image.filename);
  const diagnostics = manifest.diagnostics.map(image => image.filename);
  assert.ok(names.every(name => expected.includes(name)), 'Unexpected screenshot');
  assert.ok(diagnostics.every(name => expected.map(diagnosticPath).includes(name)),
    'Unexpected diagnostic screenshot');
  assert.equal(new Set([...names, ...diagnostics]).size, names.length + diagnostics.length, 'Duplicate screenshot');
  assert.deepEqual(manifest.missingScreenshots, expected.filter(name => !names.includes(name)),
    'Missing screenshots do not match the report');
  assert.equal(manifest.complete, manifest.captureSucceeded && names.length === expected.length && diagnostics.length === 0,
    'Incorrect capture completion status');
  const files = [...names, ...diagnostics, 'manifest.json'];
  if (manifest.log) {
    assert.equal(manifest.log.filename, 'capture.log');
    const { filename, ...facts } = manifest.log;
    assert.deepEqual(await logFacts(join(directory, filename)), facts, 'Capture log checksum does not match');
    files.push(filename);
  }
  await verifyContents(directory, files);
  for (const { filename, ...expectedFacts } of [...manifest.screenshots, ...manifest.diagnostics]) {
    assert.deepEqual(await imageFacts(join(directory, filename)), expectedFacts,
      `Screenshot checksum or dimensions do not match: ${filename}`);
  }
  return manifest;
}

export async function verifyScreenshots(directory, sourceCommit, selection) {
  const report = await verifyScreenshotBundle(directory, sourceCommit, selection);
  assert.ok(report.complete, `Capture failed; ${report.missingScreenshots.length} screenshots missing. ` +
    `The capture report, available images, and any log remain at ${directory}. Previous screenshots were not replaced.`);
  return directory;
}

export async function verifyScreenshotGallery(directory) {
  assert.ok((await lstat(directory)).isDirectory(), 'Screenshot gallery must be a real directory');
  const manifestPath = join(directory, 'manifest.json');
  assert.ok((await lstat(manifestPath)).isFile(), 'Expected a regular gallery manifest');
  const gallery = JSON.parse(await readFile(manifestPath, 'utf8'));
  assert.equal(gallery.schemaVersion, 2);
  assert.equal(gallery.kind, 'gallery');
  assert.equal(gallery.fixtureData, true);
  const expected = await expectedScreenshotNames();
  const names = gallery.screenshots.map(image => image.filename);
  assert.ok(names.length > 0 && names.every(name => expected.includes(name)), 'Unexpected gallery screenshot');
  assert.equal(new Set(names).size, names.length, 'Duplicate gallery screenshot');
  await checkedSelection(gallery.lastCapture.selection);
  const files = [...names, 'manifest.json'];
  if (gallery.log) {
    assert.equal(gallery.log.filename, 'capture.log');
    files.push(gallery.log.filename);
  }
  await verifyContents(directory, files);
  for (const { filename, sourceCommit, device, capturedAt, ...facts } of gallery.screenshots) {
    assert.match(sourceCommit, /^[0-9a-f]{40}$/);
    assert.ok(typeof device === 'string' && device.length > 0 && Number.isFinite(Date.parse(capturedAt)),
      'Missing screenshot provenance');
    assert.deepEqual(await imageFacts(join(directory, filename)), facts,
      `Screenshot checksum or dimensions do not match: ${filename}`);
  }
  if (gallery.log) {
    const { filename, ...facts } = gallery.log;
    assert.deepEqual(await logFacts(join(directory, filename)), facts, 'Capture log checksum does not match');
  }
  return gallery;
}

async function previousGallery(directory) {
  const manifestPath = join(directory, 'manifest.json');
  assert.ok((await lstat(manifestPath)).isFile(), 'Expected a regular gallery manifest');
  const manifest = JSON.parse(await readFile(manifestPath, 'utf8'));
  if (manifest.kind === 'gallery') {
    return (await verifyScreenshotGallery(directory)).screenshots.map(image => ({ image, source: image.filename }));
  }
  await verifyScreenshots(directory, manifest.sourceCommit);
  const paths = await expectedScreenshotNames();
  return manifest.screenshots.map(image => ({
    source: image.filename,
    image: { ...image, filename: paths.find(name => basename(name) === basename(image.filename)),
      sourceCommit: manifest.sourceCommit, device: manifest.device, capturedAt: manifest.capturedAt }
  }));
}

export async function replaceScreenshots({ repositoryRoot, stagingDirectory, sourceCommit, selection }) {
  const root = await realpath(repositoryRoot);
  const staging = resolve(stagingDirectory);
  const local = join(root, '.agent-local');
  assert.equal(await realpath(local), local, 'Screenshot staging cannot use a linked directory');
  assert.equal(dirname(staging), local, 'Screenshot staging must be inside this project');
  assert.match(basename(staging), /^screenshots-[0-9a-f-]{36}$/);
  await verifyScreenshots(staging, sourceCommit, selection);
  const report = await verifyScreenshotBundle(staging, sourceCommit, selection);
  assert.equal(report.schemaVersion, 2, 'New captures must use the categorized screenshot format');
  const destination = join(root, 'AppUI_Screenshots');
  const previous = await lstat(destination).catch(error => {
    if (error.code !== 'ENOENT') throw error;
    return undefined;
  });
  if (previous) assert.ok(previous.isDirectory(), 'AppUI_Screenshots must be a real directory, not a link');
  const ready = join(local, `screenshots-ready-${randomUUID()}`);
  const images = new Map();
  const fullCapture = report.screenshots.length === (await expectedScreenshotNames()).length;
  if (previous && !fullCapture) {
    for (const { image, source } of await previousGallery(destination)) {
      images.set(image.filename, { image, source: join(destination, source) });
    }
  }
  const { capturedAt, device } = report;
  for (const image of report.screenshots) {
    images.set(image.filename, { image: { ...image, sourceCommit, device, capturedAt }, source: join(staging, image.filename) });
  }
  await mkdir(ready);
  for (const [filename, { source }] of images) await copyInto(source, ready, filename);
  if (report.log) await copyInto(join(staging, report.log.filename), ready, report.log.filename);
  await writeFile(join(ready, 'manifest.json'), JSON.stringify({
    schemaVersion: 2, kind: 'gallery', fixtureData: true,
    lastCapture: { sourceCommit, device, capturedAt, selection: report.selection },
    screenshots: [...images.values()].map(entry => entry.image).sort((a, b) => a.filename.localeCompare(b.filename)),
    ...(report.log ? { log: report.log } : {})
  }, null, 2) + '\n');
  await verifyScreenshotGallery(ready);
  const backup = join(local, `screenshots-previous-${randomUUID()}`);
  if (previous) await rename(destination, backup);
  try { await rename(ready, destination); }
  catch (error) {
    throw new Error(`Could not install the new screenshot set. New files remain at ${staging} and ${ready}.` +
      (previous ? ` Previous files remain at ${backup}.` : ''), { cause: error });
  }
  if (previous) {
    assert.equal(dirname(resolve(backup)), local);
    await rm(backup, { recursive: true });
  }
  await rm(staging, { recursive: true });
  return destination;
}

if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  const [attachmentsDirectory, outputDirectory, sourceCommit, device, captureOutcome, logFile, selectionFile] = process.argv.slice(2);
  assert.ok(captureOutcome === undefined || ['success', 'failure'].includes(captureOutcome), 'Invalid capture outcome');
  const selection = selectionFile ? JSON.parse(await readFile(selectionFile, 'utf8')) : undefined;
  collectScreenshots({ attachmentsDirectory, outputDirectory, sourceCommit, device, logFile, selection,
    allowIncomplete: captureOutcome !== undefined, captureSucceeded: captureOutcome !== 'failure' })
    .then(directory => console.log(`Screenshot capture report: ${directory}`))
    .catch(error => { console.error(error.message); process.exitCode = 1; });
}
