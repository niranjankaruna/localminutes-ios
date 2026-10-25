import assert from 'node:assert/strict';
import { createHash, randomUUID } from 'node:crypto';
import { copyFile, lstat, mkdir, readFile, readdir, realpath, rename, rm, writeFile } from 'node:fs/promises';
import { basename, dirname, join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const testSource = new URL('../Tests/NativeUITests/AppScreenshotsUITests.swift', import.meta.url);
const pngSignature = Buffer.from('89504e470d0a1a0a', 'hex');

export async function expectedScreenshotNames() {
  const source = await readFile(testSource, 'utf8');
  const names = [...source.matchAll(/\bcapture\("([a-z0-9_]+)"/g)].map(match => match[1]);
  assert.ok(names.length > 0, 'The screenshot tour must declare its captures');
  assert.equal(new Set(names).size, names.length, 'Duplicate screenshot names in the UI tour');
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

export async function collectScreenshots({ attachmentsDirectory, outputDirectory, sourceCommit, device }) {
  assert.match(sourceCommit, /^[0-9a-f]{40}$/);
  assert.ok(typeof device === 'string' && device.length > 0);
  const entries = JSON.parse(await readFile(join(attachmentsDirectory, 'manifest.json'), 'utf8'));
  assert.ok(Array.isArray(entries), 'Unexpected xcresult attachment manifest');
  const images = new Map();
  for (const entry of entries) {
    for (const attachment of entry.attachments ?? []) {
      const match = /^appui__(light|dark)__([a-z0-9]+(?:_[a-z0-9]+)*)__/.exec(attachment.suggestedHumanReadableName ?? '');
      if (!match) continue;
      const exported = attachment.exportedFileName;
      assert.equal(typeof exported, 'string');
      assert.match(exported, /^[A-Za-z0-9_.-]+\.png$/i, 'Unsafe exported screenshot path');
      const filename = `${match[2]}_${match[1]}.png`;
      assert.ok(!images.has(filename), `Duplicate capture: ${filename}`);
      images.set(filename, join(attachmentsDirectory, exported));
    }
  }
  const expected = await expectedScreenshotNames();
  assert.deepEqual([...images.keys()].sort(), expected, 'The screenshot tour is incomplete');
  await mkdir(outputDirectory);
  const screenshots = [];
  for (const filename of expected) {
    const source = images.get(filename);
    const facts = await imageFacts(source);
    await copyFile(source, join(outputDirectory, filename));
    screenshots.push({ filename, ...facts });
  }
  await writeFile(join(outputDirectory, 'manifest.json'), JSON.stringify({
    schemaVersion: 1, sourceCommit, device, fixtureData: true,
    capturedAt: new Date().toISOString(), screenshots
  }, null, 2) + '\n');
  return verifyScreenshots(outputDirectory, sourceCommit);
}

export async function verifyScreenshots(directory, sourceCommit) {
  assert.ok((await lstat(directory)).isDirectory(), 'Screenshot download must be a real directory');
  const manifestPath = join(directory, 'manifest.json');
  assert.ok((await lstat(manifestPath)).isFile(), 'Expected a regular screenshot manifest');
  const manifest = JSON.parse(await readFile(manifestPath, 'utf8'));
  assert.equal(manifest.schemaVersion, 1);
  assert.equal(manifest.sourceCommit, sourceCommit, 'Screenshot source commit does not match the request');
  assert.equal(manifest.fixtureData, true);
  assert.ok(typeof manifest.device === 'string' && manifest.device.length > 0);
  const expected = await expectedScreenshotNames();
  assert.deepEqual(manifest.screenshots.map(image => image.filename).sort(), expected,
    'Missing, duplicated, or unexpected screenshots');
  assert.deepEqual((await readdir(directory)).sort(), [...expected, 'manifest.json'].sort(),
    'Unexpected screenshot download contents');
  for (const { filename, ...expectedFacts } of manifest.screenshots) {
    assert.deepEqual(await imageFacts(join(directory, filename)), expectedFacts,
      `Screenshot checksum or dimensions do not match: ${filename}`);
  }
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
  const [attachmentsDirectory, outputDirectory, sourceCommit, device] = process.argv.slice(2);
  collectScreenshots({ attachmentsDirectory, outputDirectory, sourceCommit, device })
    .then(directory => console.log(`Verified screenshots: ${directory}`))
    .catch(error => { console.error(error.message); process.exitCode = 1; });
}
