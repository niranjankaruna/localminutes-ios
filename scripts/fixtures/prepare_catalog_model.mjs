#!/usr/bin/env node
import { createHash, randomUUID } from 'node:crypto';
import { createReadStream } from 'node:fs';
import { lstat, mkdir, open, readFile, rename, unlink } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const projectRoot = fileURLToPath(new URL('../../', import.meta.url));
export const defaultCatalogPath = join(projectRoot, 'Models', 'Resources', 'SummaryCatalog.json');
export const defaultFixturesRoot = join(projectRoot, '.agent-local', 'catalog-fixtures');
const officialPublishers = { qwen25: 'Qwen', qwen3: 'Qwen', phi3: 'microsoft', phi4: 'microsoft', gemma3: 'google', gemma4: 'google' };
const component = /^[a-zA-Z0-9][a-zA-Z0-9._-]{0,127}$/;
const maximumModelBytes = 8 * 1024 * 1024 * 1024;

function repositoryParts(value) {
  const parts = typeof value === 'string' ? value.split('/') : [];
  if (parts.length !== 2 || !parts.every(part => component.test(part))) throw new Error('Invalid catalogue repository');
  return parts;
}

export function validateVariant(variant) {
  if (!variant || !component.test(variant.id ?? '') || !component.test(variant.fileName ?? '') ||
      !variant.fileName.endsWith('.gguf') || !Object.hasOwn(officialPublishers, variant.family) ||
      !/^[a-f0-9]{40}$/.test(variant.revision ?? '') || !/^[a-f0-9]{64}$/.test(variant.sha256 ?? '') ||
      !Number.isSafeInteger(variant.byteCount) || variant.byteCount <= 0 || variant.byteCount > maximumModelBytes) {
    throw new Error('Invalid catalogue variant or immutable artifact pin');
  }
  const [publisher] = repositoryParts(variant.repository);
  const official = officialPublishers[variant.family];
  const conversion = (publisher === 'unsloth' && ['qwen3', 'phi4'].includes(variant.family)) ||
    (publisher === 'ggml-org' && variant.family === 'gemma3');
  if (publisher !== official && !conversion) throw new Error('Catalogue publisher is not approved for this model family');
  if (conversion && (!variant.sourceRepository || repositoryParts(variant.sourceRepository)[0] !== official)) {
    throw new Error('Organization conversions must identify their official upstream model');
  }
  const expectedLicense = variant.family.startsWith('phi') ? 'MIT' : variant.family === 'gemma3' ? 'Gemma' : 'Apache-2.0';
  if (variant.licenseIdentifier !== expectedLicense) throw new Error('Unexpected model licence');
  let license;
  try { license = new URL(variant.licenseURL); } catch { throw new Error('Invalid model licence URL'); }
  if (license.protocol !== 'https:' || license.username || license.password ||
      !['www.apache.org', 'huggingface.co', 'ai.google.dev'].includes(license.hostname)) {
    throw new Error('Invalid model licence URL');
  }
  return variant;
}

export async function loadCatalog(path = defaultCatalogPath) {
  const catalog = JSON.parse(await readFile(path, 'utf8'));
  if (catalog.schemaVersion !== 1 || !Array.isArray(catalog.families) || !catalog.families.length) {
    throw new Error('Unsupported model catalogue');
  }
  const ids = new Set();
  const families = new Set();
  const variants = [];
  for (const family of catalog.families) {
    if (!Object.hasOwn(officialPublishers, family.id) || families.has(family.id) ||
        !Array.isArray(family.variants) || !family.variants.length) throw new Error('Invalid model family');
    families.add(family.id);
    for (const candidate of family.variants) {
      const variant = validateVariant(candidate);
      if (variant.family !== family.id || ids.has(variant.id)) throw new Error('Duplicate or misplaced model variant');
      ids.add(variant.id);
      variants.push(variant);
    }
  }
  return variants;
}

export function parseArguments(args) {
  if (args.length !== 2 || args[0] !== '--variant' || !component.test(args[1])) {
    throw new Error('Usage: node scripts/fixtures/prepare_catalog_model.mjs --variant <catalogue-variant-id>');
  }
  return args[1];
}

async function statOrMissing(path) {
  try { return await lstat(path); }
  catch (error) { if (error.code === 'ENOENT') return undefined; throw error; }
}

// Walk ancestors too: an existing .agent-local or variant symlink must never
// redirect downloaded weights or cleanup outside the selected fixture root.
async function ensureDirectory(path) {
  const parent = dirname(path);
  if (parent !== path) await ensureDirectory(parent);
  const stats = await statOrMissing(path);
  if (!stats) {
    try { await mkdir(path, { mode: 0o700 }); }
    catch (error) { if (error.code !== 'EEXIST') throw error; }
    const created = await lstat(path);
    if (!created.isDirectory() || created.isSymbolicLink()) throw new Error('Unsafe fixture directory');
  } else if (!stats.isDirectory() || stats.isSymbolicLink()) {
    throw new Error('Unsafe fixture directory');
  }
}

async function verifiedExisting(path, variant) {
  const stats = await statOrMissing(path);
  if (!stats) return false;
  if (!stats.isFile() || stats.isSymbolicLink() || stats.nlink !== 1) throw new Error('Unsafe fixture model file');
  if (stats.size !== variant.byteCount) return false;
  const hash = createHash('sha256');
  let count = 0;
  for await (const chunk of createReadStream(path, { highWaterMark: 1024 * 1024 })) {
    count += chunk.length;
    if (count > variant.byteCount) return false;
    hash.update(chunk);
  }
  return count === variant.byteCount && hash.digest('hex') === variant.sha256;
}

/** Download exactly one reviewed artifact. Injection is for offline transport
 * tests; the CLI always uses the repository catalogue and owned fixture root. */
export async function prepareVariant(candidate, { fixturesRoot = defaultFixturesRoot, fetchImpl = globalThis.fetch } = {}) {
  const variant = validateVariant(candidate);
  const root = resolve(fixturesRoot);
  const directory = join(root, variant.id);
  const modelPath = join(directory, variant.fileName);
  await ensureDirectory(directory);
  if (await verifiedExisting(modelPath, variant)) {
    return { variantID: variant.id, modelPath, byteCount: variant.byteCount, sha256: variant.sha256, downloaded: false };
  }
  const url = new URL('https://huggingface.co/');
  url.pathname = '/' + [variant.repository, 'resolve', variant.revision, variant.fileName].join('/');
  const temporary = join(directory, '.' + variant.fileName + '.' + randomUUID() + '.part');
  let file;
  let response;
  try {
    response = await fetchImpl(url, { redirect: 'follow', signal: AbortSignal.timeout(60 * 60 * 1000) });
    if (!response.ok || !response.body) throw new Error('Model download failed with HTTP ' + response.status);
    const length = response.headers.get('content-length');
    if (length !== null && (!/^\d+$/.test(length) || Number(length) !== variant.byteCount)) {
      throw new Error('Model Content-Length does not match the reviewed artifact');
    }
    file = await open(temporary, 'wx', 0o600);
    const hash = createHash('sha256');
    let count = 0;
    for await (const chunk of response.body) {
      if (!(chunk instanceof Uint8Array)) throw new Error('Invalid model response body');
      count += chunk.byteLength;
      if (count > variant.byteCount) throw new Error('Model download exceeded the reviewed size');
      hash.update(chunk);
      // FileHandle.write may be partial; never assume one write persisted a chunk.
      let offset = 0;
      while (offset < chunk.byteLength) {
        const written = await file.write(chunk, offset, chunk.byteLength - offset);
        if (written.bytesWritten <= 0) throw new Error('Model fixture write made no progress');
        offset += written.bytesWritten;
      }
    }
    if (count !== variant.byteCount) throw new Error('Model download was truncated');
    if (hash.digest('hex') !== variant.sha256) throw new Error('Model SHA-256 does not match the reviewed artifact');
    await file.sync();
    await file.close(); file = undefined;
    // Recheck the destination before atomic publication, including cache races.
    const current = await statOrMissing(modelPath);
    if (current && (!current.isFile() || current.isSymbolicLink() || current.nlink !== 1)) {
      throw new Error('Unsafe fixture model file');
    }
    await rename(temporary, modelPath);
    return { variantID: variant.id, modelPath, byteCount: count, sha256: variant.sha256, downloaded: true };
  } finally {
    await file?.close().catch(() => {});
    await response?.body?.cancel().catch(() => {});
    await unlink(temporary).catch(error => { if (error.code !== 'ENOENT') throw error; });
  }
}

export async function main(args = process.argv.slice(2)) {
  const id = parseArguments(args);
  const variant = (await loadCatalog()).find(candidate => candidate.id === id);
  if (!variant) throw new Error('Unknown catalogue variant: ' + id);
  const result = await prepareVariant(variant);
  process.stdout.write(JSON.stringify(result) + '\n');
}

if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  main().catch(error => { process.stderr.write(error.message + '\n'); process.exitCode = 1; });
}
