import assert from 'node:assert/strict';
import { createHash, randomUUID } from 'node:crypto';
import { copyFile, lstat, mkdir, readFile, readdir, realpath, rename, rm, writeFile } from 'node:fs/promises';
import { basename, dirname, join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const sceneSource = new URL('../Shared/AppScreenshotScene.swift', import.meta.url);
const pngSignature = Buffer.from('89504e470d0a1a0a', 'hex');

export async function expectedScreenshotNames() {
  const source = await readFile(sceneSource, 'utf8');
  const names = [...source.matchAll(/^\s*case \w+ = "([a-z0-9_]+)"$/gm)].map(match => match[1]);
  assert.ok(names.length > 0, 'The screenshot catalog must declare its scenes');
  assert.equal(new Set(names).size, names.length, 'Duplicate screenshot names in the catalog');
  return names.flatMap(name => ['light', 'dark'].map(appearance => `${name}_${appearance}.png`)).sort();
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

export async function collectScreenshots({ attachmentsDirectory, outputDirectory, sourceCommit, device,
  allowIncomplete = false, captureSucceeded = true, logFile }) {
  assert.match(sourceCommit, /^[0-9a-f]{40}$/);
  assert.ok(typeof device === 'string' && device.length > 0);
  const rawManifest = await readFile(join(attachmentsDirectory, 'manifest.json'), 'utf8').catch(error => {
    if (allowIncomplete && error.code === 'ENOENT') return '[]';
    throw error;
  });
  const entries = JSON.parse(rawManifest);
  assert.ok(Array.isArray(entries), 'Unexpected xcresult attachment manifest');
  const images = new Map();
  const diagnostics = new Map();
  const expected = await expectedScreenshotNames();
  for (const entry of entries) {
    for (const attachment of entry.attachments ?? []) {
      const match = /^(appui|diagnostic)__(light|dark)__([a-z0-9]+(?:_[a-z0-9]+)*)__/.exec(attachment.suggestedHumanReadableName ?? '');
      if (!match) continue;
      const exported = attachment.exportedFileName;
      assert.equal(typeof exported, 'string');
      assert.match(exported, /^[A-Za-z0-9_.-]+\.png$/i, 'Unsafe exported screenshot path');
      const sceneName = `${match[3]}_${match[2]}.png`;
      assert.ok(expected.includes(sceneName), `Unknown screenshot scene: ${sceneName}`);
      const filename = match[1] === 'diagnostic' ? `diagnostic_${sceneName}` : sceneName;
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
    await copyFile(source, join(outputDirectory, filename));
    (images.has(filename) ? screenshots : diagnosticImages).push({ filename, ...facts });
  }
  let log;
  if (logFile) {
    log = { filename: 'capture.log', ...await logFacts(logFile) };
    await copyFile(logFile, join(outputDirectory, log.filename));
  }
  await writeFile(join(outputDirectory, 'manifest.json'), JSON.stringify({
    schemaVersion: 1, sourceCommit, device, fixtureData: true,
    capturedAt: new Date().toISOString(), complete, captureSucceeded, missingScreenshots,
    screenshots, diagnostics: diagnosticImages, ...(log ? { log } : {})
  }, null, 2) + '\n');
  await verifyScreenshotBundle(outputDirectory, sourceCommit);
  return outputDirectory;
}

export async function verifyScreenshotBundle(directory, sourceCommit) {
  assert.ok((await lstat(directory)).isDirectory(), 'Screenshot download must be a real directory');
  const manifestPath = join(directory, 'manifest.json');
  assert.ok((await lstat(manifestPath)).isFile(), 'Expected a regular screenshot manifest');
  const manifest = JSON.parse(await readFile(manifestPath, 'utf8'));
  assert.equal(manifest.schemaVersion, 1);
  assert.equal(manifest.sourceCommit, sourceCommit, 'Screenshot source commit does not match the request');
  assert.equal(manifest.fixtureData, true);
  assert.ok(typeof manifest.device === 'string' && manifest.device.length > 0);
  const expected = await expectedScreenshotNames();
  assert.equal(typeof manifest.captureSucceeded, 'boolean');
  assert.ok(Array.isArray(manifest.screenshots) && Array.isArray(manifest.diagnostics));
  const names = manifest.screenshots.map(image => image.filename);
  const diagnostics = manifest.diagnostics.map(image => image.filename);
  assert.ok(names.every(name => expected.includes(name)), 'Unexpected screenshot');
  assert.ok(diagnostics.every(name => name.startsWith('diagnostic_') && expected.includes(name.slice(11))),
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
  assert.deepEqual((await readdir(directory)).sort(), files.sort(),
    'Unexpected screenshot download contents');
  for (const { filename, ...expectedFacts } of [...manifest.screenshots, ...manifest.diagnostics]) {
    assert.deepEqual(await imageFacts(join(directory, filename)), expectedFacts,
      `Screenshot checksum or dimensions do not match: ${filename}`);
  }
  return manifest;
}

export async function verifyScreenshots(directory, sourceCommit) {
  const report = await verifyScreenshotBundle(directory, sourceCommit);
  assert.ok(report.complete, `Capture failed; ${report.missingScreenshots.length} screenshots missing. ` +
    `The capture report, available images, and any log remain at ${directory}. Previous screenshots were not replaced.`);
  return directory;
}

export async function replaceScreenshots({ repositoryRoot, stagingDirectory, sourceCommit }) {
  const root = await realpath(repositoryRoot);
  const staging = resolve(stagingDirectory);
  const local = join(root, '.agent-local');
  assert.equal(await realpath(local), local, 'Screenshot staging cannot use a linked directory');
  assert.equal(dirname(staging), local, 'Screenshot staging must be inside this project');
  assert.match(basename(staging), /^screenshots-[0-9a-f-]{36}$/);
  await verifyScreenshots(staging, sourceCommit);
  const destination = join(root, 'AppUI_Screenshots');
  const previous = await lstat(destination).catch(error => {
    if (error.code !== 'ENOENT') throw error;
    return undefined;
  });
  const backup = join(local, `screenshots-previous-${randomUUID()}`);
  if (previous) {
    assert.ok(previous.isDirectory(), 'AppUI_Screenshots must be a real directory, not a link');
    await rename(destination, backup);
  }
  try { await rename(staging, destination); }
  catch (error) {
    throw new Error(`Could not install the new screenshot set. New files remain at ${staging}.` +
      (previous ? ` Previous files remain at ${backup}.` : ''), { cause: error });
  }
  if (previous) {
    assert.equal(dirname(resolve(backup)), local);
    await rm(backup, { recursive: true });
  }
  return destination;
}

if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  const [attachmentsDirectory, outputDirectory, sourceCommit, device, captureOutcome, logFile] = process.argv.slice(2);
  assert.ok(captureOutcome === undefined || ['success', 'failure'].includes(captureOutcome), 'Invalid capture outcome');
  collectScreenshots({ attachmentsDirectory, outputDirectory, sourceCommit, device, logFile,
    allowIncomplete: captureOutcome !== undefined, captureSucceeded: captureOutcome !== 'failure' })
    .then(directory => console.log(`Screenshot capture report: ${directory}`))
    .catch(error => { console.error(error.message); process.exitCode = 1; });
}
