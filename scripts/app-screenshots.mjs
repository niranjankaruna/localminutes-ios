import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createHash, randomUUID } from 'node:crypto';
import { copyFile, lstat, mkdir, readFile, readdir, realpath, rename, rm, writeFile } from 'node:fs/promises';
import { basename, dirname, join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const sceneSource = new URL('../Shared/AppScreenshotScene.swift', import.meta.url);
const pngSignature = Buffer.from('89504e470d0a1a0a', 'hex');
// Read existing capture receipts without offering removed UI for a new run.
const retiredScenes = ['models_parakeet_compatibility', 'models_parakeet_requirements',
  'models_import_picker', 'models_pack_picker'];

export function parseScreenshotCatalog(source) {
  const cases = [...source.matchAll(/^\s*case (\w+) = "([a-z0-9_]+)"$/gm)];
  const definitions = [...source.matchAll(/^\s*case \.(\w+): #"(\{.*\})"#$/gm)];
  assert.ok(cases.length > 0 && definitions.length === cases.length, 'Every scene needs a capture contract');
  const byCase = new Map(definitions.map(([, name, json]) => [name, JSON.parse(json)]));
  assert.equal(byCase.size, cases.length, 'Duplicate capture contracts');
  const catalog = Object.fromEntries(cases.map(([, name, scene]) => {
    const spec = byCase.get(name);
    assert.ok(spec && /^[a-z][a-z-]*$/.test(spec.category), `Invalid category: ${scene}`);
    assert.ok(['screen', 'sheet', 'menu', 'confirmation', 'systemSheet', 'systemPermission', 'hostedActivity', 'hostedLaunch'].includes(spec.presentation));
    assert.ok(Array.isArray(spec.required) && spec.required.length > 0 && spec.required.every(id => typeof id === 'string' && id.length > 0));
    assert.equal(new Set(spec.required).size, spec.required.length, `Duplicate targets: ${scene}`);
    assert.ok(Array.isArray(spec.actions) && spec.actions.every(id => typeof id === 'string' && id.length > 0));
    if (spec.expectedText) assert.ok(Object.entries(spec.expectedText).every(([id, value]) =>
      spec.required.includes(id) && typeof value === 'string' && value.length > 0), `Invalid expected text: ${scene}`);
    if (spec.presentation === 'confirmation') {
      assert.ok(typeof spec.alertTitle === 'string' && spec.alertTitle.length > 0 && spec.required.includes('system.cancel'),
        `Confirmation must check its title and Cancel: ${scene}`);
    }
    return [scene, spec];
  }));
  assert.equal(Object.keys(catalog).length, cases.length, 'Duplicate screenshot names');
  return catalog;
}

export const screenshotSpecifications = parseScreenshotCatalog(readFileSync(sceneSource, 'utf8'));
export const screenshotCategories = Object.entries(screenshotSpecifications).reduce((categories, [scene, spec]) => {
  (categories[spec.category] ??= []).push(scene);
  return categories;
}, {});

async function catalogScenes() {
  return Object.keys(screenshotSpecifications);
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

async function checkedSelection(selection, { historical = false } = {}) {
  selection ??= await resolveScreenshotSelection();
  assert.ok(Array.isArray(selection.appearances) && Array.isArray(selection.scenes), 'Invalid screenshot selection');
  if (historical && selection.scenes.some(scene => retiredScenes.includes(scene))) {
    const current = await resolveScreenshotSelection({
      appearance: selection.appearances.length === 2 ? 'both' : selection.appearances[0]
    });
    const known = [...current.scenes, ...retiredScenes];
    assert.ok(selection.scenes.every(scene => known.includes(scene))
      && new Set(selection.scenes).size === selection.scenes.length, 'Invalid historical screenshot selection');
    assert.deepEqual(selection, { appearances: current.appearances, scenes: selection.scenes },
      'Invalid historical screenshot selection');
    return selection;
  }
  const normalized = await resolveScreenshotSelection({
    appearance: selection.appearances.length === 2 ? 'both' : selection.appearances[0],
    screens: selection.scenes.join(',')
  });
  assert.deepEqual(selection, normalized, 'Invalid or non-canonical screenshot selection');
  return normalized;
}

function screenshotPath(scene, appearance) {
  const category = Object.keys(screenshotCategories).find(key => screenshotCategories[key].includes(scene))
    ?? (retiredScenes.includes(scene) ? 'parakeet' : undefined);
  assert.ok(category, `Unknown screenshot scene: ${scene}`);
  return `${appearance}/${category}/${scene}_${appearance}.png`;
}

export async function expectedScreenshotNames(selection, options) {
  const { scenes, appearances } = await checkedSelection(selection, options);
  return scenes.flatMap(scene => appearances.map(appearance => screenshotPath(scene, appearance))).sort();
}

async function historicalScreenshotNames() {
  const current = await resolveScreenshotSelection();
  return expectedScreenshotNames({ ...current, scenes: [...current.scenes, ...retiredScenes] }, { historical: true });
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

function checkedRect(value, label) {
  assert.ok(Array.isArray(value) && value.length === 4 && value.every(Number.isFinite)
    && value[2] > 0 && value[3] > 0, `Invalid ${label} bounds`);
  return value;
}

function contains(outer, inner) {
  const tolerance = 0.5;
  return inner[0] >= outer[0] - tolerance && inner[1] >= outer[1] - tolerance
    && inner[0] + inner[2] <= outer[0] + outer[2] + tolerance
    && inner[1] + inner[3] <= outer[1] + outer[3] + tolerance;
}

function captureContract(spec) {
  return { required: spec.required, presentation: spec.presentation, alertTitle: spec.alertTitle ?? '',
    keyboard: spec.keyboard === true, expectedText: spec.expectedText ?? {} };
}

export function validateScreenshotEvidence(evidence, filename, image, { historical = false } = {}) {
  const match = /^(.*)_(light|dark)\.png$/.exec(basename(filename));
  assert.ok(match, 'Invalid screenshot name');
  const [, scene, appearance] = match;
  const spec = screenshotSpecifications[scene];
  assert.ok(spec, 'Validation references an unknown scene');
  assert.equal(evidence?.schemaVersion, 1, `Missing screenshot validation: ${filename}`);
  const contract = evidence.contract;
  assert.ok(contract && Array.isArray(contract.required) && contract.required.length > 0
    && contract.required.every(id => typeof id === 'string') && new Set(contract.required).size === contract.required.length,
    'Missing capture contract');
  assert.ok(contract.expectedText && typeof contract.expectedText === 'object' && !Array.isArray(contract.expectedText));
  assert.equal(typeof contract.alertTitle, 'string');
  assert.equal(typeof contract.keyboard, 'boolean');
  assert.ok(Object.entries(contract.expectedText).every(([id, value]) => contract.required.includes(id) && typeof value === 'string' && value.length > 0));
  if (!historical) assert.deepEqual(contract, captureContract(spec), 'Capture contract does not match this build');
  assert.equal(evidence.scene, scene, 'Validation scene mismatch');
  assert.equal(evidence.appearance, appearance, 'Validation appearance mismatch');
  assert.equal(evidence.presentation, contract.presentation, 'Validation presentation mismatch');
  assert.equal(evidence.pixelWidth, image.width, 'Validation pixel width mismatch');
  assert.equal(evidence.pixelHeight, image.height, 'Validation pixel height mismatch');
  assert.ok(image.width >= 320 && image.height >= 480, 'Screenshot is too small for an iPhone capture');
  const window = checkedRect(evidence.window, 'window');
  const viewport = checkedRect(evidence.viewport, 'viewport');
  assert.ok(contains(window, viewport), 'Viewport falls outside the screenshot');
  const scale = image.width / window[2];
  assert.ok(scale >= 1 && scale <= 4 && Math.abs(scale - image.height / window[3]) < 0.02,
    'Screenshot does not match the captured window');
  assert.ok(Number.isInteger(evidence.stableSamples) && evidence.stableSamples >= 3, 'Layout was not stable');
  const chrome = evidence.chromeBounds ?? evidence.navigationBars;
  assert.ok(Array.isArray(chrome));
  for (const bar of chrome) assert.ok(contains(window, checkedRect(bar, 'chrome')));
  assert.equal(typeof evidence.keyboardVisible, 'boolean');
  assert.equal(evidence.keyboardVisible, contract.keyboard, 'Unexpected keyboard state');
  assert.equal(evidence.alertTitle, contract.alertTitle, 'Incorrect confirmation title');
  assert.ok(Array.isArray(evidence.checks));
  assert.deepEqual(evidence.checks.map(check => check.identifier), contract.required, 'Required visible elements were not checked');
  if (contract.presentation === 'confirmation') {
    assert.ok(contract.alertTitle && contract.required.includes('system.cancel') && evidence.checks.every(check => check.enabled),
      'Confirmation actions must be available');
  }
  for (const check of evidence.checks) {
    const frame = checkedRect(check.frame, check.identifier);
    assert.equal(typeof check.label, 'string');
    assert.equal(typeof check.enabled, 'boolean');
    assert.ok(['content', 'navigation', 'overlay'].includes(check.region), 'Unknown visibility region');
    if (check.region === 'content') assert.ok(contains(viewport, frame), `Clipped content: ${check.identifier}`);
    if (check.region === 'navigation') assert.ok(chrome.some(bar => contains(bar, frame)), 'Clipped toolbar control');
    if (check.region === 'overlay') {
      assert.ok(['confirmation', 'menu', 'systemSheet', 'systemPermission', 'hostedActivity', 'hostedLaunch'].includes(contract.presentation));
      assert.ok(contains(window, frame), 'Clipped presentation');
    }
    if (check.identifier === 'system.cancel') assert.ok(check.enabled && check.label === 'Cancel', 'Confirmation cannot be cancelled');
    if (contract.expectedText[check.identifier]) {
      assert.ok((check.label + ' ' + (check.value ?? '')).toLowerCase().includes(contract.expectedText[check.identifier].toLowerCase()),
        `Wrong visible state: ${check.identifier}`);
    }
  }
  if (['models_speech_variants', 'models_summary_variants'].includes(scene)) {
    const button = evidence.checks.find(check => check.identifier === 'buttonPrefix:models.download.');
    const label = evidence.checks.find(check => check.identifier === 'textPrefix:models.download.label.');
    assert.ok(button && label && label.label === 'Download' && contains(button.frame, label.frame), 'Download title is missing');
    assert.ok(button.frame[2] >= 44 && button.frame[3] >= 44 && button.frame[3] <= 80, 'Download button has an invalid size');
  }
  return evidence;
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
  const validations = new Map();
  const expected = await expectedScreenshotNames(selection);
  for (const entry of entries) {
    for (const attachment of entry.attachments ?? []) {
      const proof = /^appui_validation__(light|dark)__([a-z0-9]+(?:_[a-z0-9]+)*)__/.exec(attachment.suggestedHumanReadableName ?? '');
      if (proof) {
        const exported = attachment.exportedFileName;
        assert.equal(typeof exported, 'string');
        assert.match(exported, /^[A-Za-z0-9_.-]+\.json$/i, 'Unsafe validation attachment path');
        const filename = screenshotPath(proof[2], proof[1]);
        assert.ok(expected.includes(filename), `Unrequested screenshot validation: ${filename}`);
        assert.ok(!validations.has(filename), `Duplicate capture validation: ${filename}`);
        const path = join(attachmentsDirectory, exported);
        const facts = await lstat(path);
        assert.ok(facts.isFile() && facts.size <= 256 * 1024, 'Expected a regular validation attachment');
        validations.set(filename, JSON.parse(await readFile(path, 'utf8')));
        continue;
      }
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
  const validationFailures = [];
  for (const [filename, path] of images) {
    const facts = await imageFacts(path);
    try { validateScreenshotEvidence(validations.get(filename), filename, facts); }
    catch (error) {
      validationFailures.push({ filename, reason: error.message });
      images.delete(filename);
      diagnostics.set(diagnosticPath(filename), path);
    }
  }
  const missingScreenshots = expected.filter(filename => !images.has(filename));
  const complete = captureSucceeded && missingScreenshots.length === 0 && diagnostics.size === 0;
  if (!allowIncomplete) assert.ok(complete, 'The screenshot set is incomplete' +
    (validationFailures.length ? `; ${validationFailures[0].reason}` : ''));
  await mkdir(outputDirectory);
  const screenshots = [];
  const diagnosticImages = [];
  for (const [filename, source] of [...images, ...diagnostics].sort(([a], [b]) => a.localeCompare(b))) {
    const facts = await imageFacts(source);
    await copyInto(source, outputDirectory, filename);
    (images.has(filename) ? screenshots : diagnosticImages).push({ filename, ...facts,
      ...(images.has(filename) ? { validation: validations.get(filename) } : {}) });
  }
  let log;
  if (logFile) {
    log = { filename: 'capture.log', ...await logFacts(logFile) };
    await copyFile(logFile, join(outputDirectory, log.filename));
  }
  await writeFile(join(outputDirectory, 'manifest.json'), JSON.stringify({
    schemaVersion: 3, selection, sourceCommit, device, fixtureData: true,
    capturedAt: new Date().toISOString(), complete, captureSucceeded, missingScreenshots,
    screenshots, diagnostics: diagnosticImages, validationFailures, ...(log ? { log } : {})
  }, null, 2) + '\n');
  await verifyScreenshotBundle(outputDirectory, sourceCommit, selection);
  return outputDirectory;
}

export async function verifyScreenshotBundle(directory, sourceCommit, requestedSelection) {
  assert.ok((await lstat(directory)).isDirectory(), 'Screenshot download must be a real directory');
  const manifestPath = join(directory, 'manifest.json');
  assert.ok((await lstat(manifestPath)).isFile(), 'Expected a regular screenshot manifest');
  const manifest = JSON.parse(await readFile(manifestPath, 'utf8'));
  assert.ok([1, 2, 3].includes(manifest.schemaVersion), 'Unknown screenshot manifest version');
  assert.equal(manifest.sourceCommit, sourceCommit, 'Screenshot source commit does not match the request');
  assert.equal(manifest.fixtureData, true);
  assert.ok(typeof manifest.device === 'string' && manifest.device.length > 0);
  let selection = manifest.selection;
  if (manifest.schemaVersion === 1) {
    const reported = [...(manifest.screenshots ?? []).map(image => image.filename), ...(manifest.missingScreenshots ?? [])];
    const current = await resolveScreenshotSelection();
    const historical = [...current.scenes, ...retiredScenes];
    selection = { appearances: current.appearances,
      scenes: historical.filter(scene => reported.some(name => ['light', 'dark'].some(appearance => basename(name) === `${scene}_${appearance}.png`))) };
  }
  assert.ok(selection, 'Missing screenshot selection');
  await checkedSelection(selection, { historical: true });
  if (requestedSelection) assert.deepEqual(selection, await checkedSelection(requestedSelection),
    'Screenshot selection does not match the request');
  const paths = await expectedScreenshotNames(selection, { historical: true });
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
  for (const { filename, validation, ...expectedFacts } of [...manifest.screenshots, ...manifest.diagnostics]) {
    const facts = await imageFacts(join(directory, filename));
    assert.deepEqual(facts, expectedFacts,
      `Screenshot checksum or dimensions do not match: ${filename}`);
    if (validation || (manifest.schemaVersion === 3 && names.includes(filename))) validateScreenshotEvidence(validation, filename, facts);
  }
  return manifest;
}

export async function verifyScreenshots(directory, sourceCommit, selection, { requireValidation = false } = {}) {
  const report = await verifyScreenshotBundle(directory, sourceCommit, selection);
  if (requireValidation) assert.equal(report.schemaVersion, 3, 'A new capture must include native visibility validation');
  assert.ok(report.complete, `Capture failed; ${report.missingScreenshots.length} screenshots missing. ` +
    `The capture report, available images, and any log remain at ${directory}. Previous screenshots were not replaced.`);
  return directory;
}

export async function verifyScreenshotGallery(directory) {
  assert.ok((await lstat(directory)).isDirectory(), 'Screenshot gallery must be a real directory');
  const manifestPath = join(directory, 'manifest.json');
  assert.ok((await lstat(manifestPath)).isFile(), 'Expected a regular gallery manifest');
  const gallery = JSON.parse(await readFile(manifestPath, 'utf8'));
  assert.ok([2, 3].includes(gallery.schemaVersion));
  assert.equal(gallery.kind, 'gallery');
  assert.equal(gallery.fixtureData, true);
  const expected = await historicalScreenshotNames();
  const names = gallery.screenshots.map(image => image.filename);
  assert.ok(names.length > 0 && names.every(name => expected.includes(name)), 'Unexpected gallery screenshot');
  assert.equal(new Set(names).size, names.length, 'Duplicate gallery screenshot');
  await checkedSelection(gallery.lastCapture.selection, { historical: true });
  const files = [...names, 'manifest.json'];
  if (gallery.log) {
    assert.equal(gallery.log.filename, 'capture.log');
    files.push(gallery.log.filename);
  }
  await verifyContents(directory, files);
  for (const { filename, sourceCommit, device, capturedAt, validation, ...facts } of gallery.screenshots) {
    assert.match(sourceCommit, /^[0-9a-f]{40}$/);
    assert.ok(typeof device === 'string' && device.length > 0 && Number.isFinite(Date.parse(capturedAt)),
      'Missing screenshot provenance');
    assert.deepEqual(await imageFacts(join(directory, filename)), facts,
      `Screenshot checksum or dimensions do not match: ${filename}`);
    if (validation) validateScreenshotEvidence(validation, filename, facts, { historical: true });
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
  const paths = await historicalScreenshotNames();
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
  assert.ok([2, 3].includes(report.schemaVersion), 'New captures must use the categorized screenshot format');
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
    schemaVersion: 3, kind: 'gallery', fixtureData: true,
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
