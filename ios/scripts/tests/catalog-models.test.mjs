import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdtemp, mkdir, readFile, readdir, realpath, rm, symlink, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { loadCatalog, main, parseArguments, prepareVariant, validateVariant } from '../fixtures/prepare_catalog_model.mjs';

const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const bytes = Buffer.from('GGUF synthetic fixture bytes; not inference evidence');
const fixtureVariant = (overrides = {}) => ({
  id: 'qwen-test-fixture', family: 'qwen25', repository: 'Qwen/Synthetic-GGUF',
  revision: 'a'.repeat(40), fileName: 'synthetic.gguf', byteCount: bytes.length,
  sha256: digest(bytes), licenseIdentifier: 'Apache-2.0',
  licenseURL: 'https://www.apache.org/licenses/LICENSE-2.0',
  contextWindow: { maximumTokens: 32768, maximumOutputTokens: 8192 }, contextSourceURL: 'https://huggingface.co/Qwen/Synthetic-GGUF', ...overrides,
});

async function temporary(body) {
  const parent = await realpath(tmpdir());
  const root = await mkdtemp(join(parent, 'localminutes-catalog-test-'));
  try { await body(root); } finally { await rm(root, { recursive: true, force: true }); }
}

function streamedResponse(chunks, headers = {}) {
  return new Response(new ReadableStream({
    start(controller) {
      for (const chunk of chunks) controller.enqueue(new Uint8Array(chunk));
      controller.close();
    },
  }), { status: 200, headers });
}

async function assertNoPublishedOrPartial(directory) {
  let entries;
  try { entries = await readdir(directory); }
  catch (error) { if (error.code === 'ENOENT') return; throw error; }
  assert.deepEqual(entries, [], 'A failed transfer must not leave model bytes or partial files');
}

test('catalogue contains exactly the requested commercially usable family variants with organization provenance', async () => {
  const variants = await loadCatalog();
  const expected = {
    qwen25: ['qwen2.5-0.5b-instruct-q4_k_m', 'qwen2.5-1.5b-instruct-q4_k_m'],
    qwen3: ['qwen3-0.6b-q8_0', 'qwen3-1.7b-q8_0', 'qwen3-4b-q4_k_m', 'qwen3-4b-instruct-2507-q4_k_m'],
    phi3: ['phi3-mini-4k-instruct-q4'],
    phi4: ['phi4-mini-instruct-q4_k_m'],
    gemma3: ['gemma3-1b-it-qat-q4_0', 'gemma3-4b-it-qat-q4_0'],
    gemma4: ['gemma4-e2b-it-qat-q4_0', 'gemma4-e4b-it-qat-q4_0'],
  };
  assert.equal(variants.length, 12);
  for (const [family, ids] of Object.entries(expected)) {
    assert.deepEqual(variants.filter(variant => variant.family === family).map(variant => variant.id).sort(), ids.sort());
  }
  assert.equal(variants.some(variant => /qwen2[.]5-3b/i.test(variant.repository)), false);
  for (const variant of variants) {
    assert.match(variant.revision, /^[a-f0-9]{40}$/);
    assert.match(variant.sha256, /^[a-f0-9]{64}$/);
    assert.ok(variant.byteCount > 100_000_000 && variant.byteCount < 6_000_000_000);
    assert.ok(['Qwen', 'microsoft', 'google', 'unsloth', 'ggml-org'].includes(variant.repository.split('/')[0]));
    if (/^(unsloth|ggml-org)\//.test(variant.repository)) {
      assert.match(variant.sourceRepository, /^(Qwen|microsoft|google)\//);
    }
    assert.equal(variant.licenseIdentifier, variant.family.startsWith('phi') ? 'MIT' : variant.family === 'gemma3' ? 'Gemma' : 'Apache-2.0');
  }
});

test('explicit one-variant CLI rejects missing, traversal, URL, and extra arguments', async () => {
  assert.equal(parseArguments(['--variant', 'qwen3-0.6b-q8_0']), 'qwen3-0.6b-q8_0');
  for (const args of [[], ['--all'], ['--variant'], ['--variant', '../escape'], ['--variant', '/tmp/model'],
    ['--variant', 'https://example.com/model'], ['--variant', 'safe', '--output', '/tmp/out'],
    ['--variant', 'safe\nUNTRUSTED=1'], ['--variant', '..'], ['--variant', 'a\\b']]) {
    assert.throws(() => parseArguments(args), /Usage:/);
  }
  await assert.rejects(main(['--variant', 'not-in-reviewed-catalogue']), /Unknown catalogue variant/);
});

test('every pinned variant has its verified maximum and required positional scaling', async () => {
  const variants = await loadCatalog();
  const expected = {
    'qwen2.5-0.5b-instruct-q4_k_m': 32768, 'qwen2.5-1.5b-instruct-q4_k_m': 32768,
    'qwen3-0.6b-q8_0': 32768, 'qwen3-1.7b-q8_0': 32768,
    'qwen3-4b-q4_k_m': 131072, 'qwen3-4b-instruct-2507-q4_k_m': 262144,
    'phi3-mini-4k-instruct-q4': 4096, 'phi4-mini-instruct-q4_k_m': 131072,
    'gemma3-1b-it-qat-q4_0': 32768, 'gemma3-4b-it-qat-q4_0': 131072,
    'gemma4-e2b-it-qat-q4_0': 131072, 'gemma4-e4b-it-qat-q4_0': 131072,
  };
  assert.deepEqual(Object.fromEntries(variants.map(v => [v.id, v.contextWindow.maximumTokens])), expected);
  assert.deepEqual(variants.filter(v => v.contextWindow.yarnOriginalContextTokens != null).map(v => v.id), ['qwen3-4b-q4_k_m']);
  assert.equal(variants.find(v => v.id === 'qwen3-4b-q4_k_m').contextWindow.yarnOriginalContextTokens, 32768);
  for (const variant of variants) assert.equal(new URL(variant.contextSourceURL).protocol, 'https:');
});

test('missing, oversized and unsupported context profiles fail before a download', () => {
  for (const contextWindow of [undefined, {}, { maximumTokens: 0 }, { maximumTokens: -1 },
    { maximumTokens: 32768.5 }, { maximumTokens: 262145 },
    { maximumTokens: 131072, yarnOriginalContextTokens: 32768 }]) {
    assert.throws(() => validateVariant(fixtureVariant({ contextWindow })), /context window/);
  }
  assert.throws(() => validateVariant(fixtureVariant({ contextSourceURL: 'http://example.com' })), /context source/);
});

test('output budgets are variant-specific and leave room for input', async () => {
  const variants = await loadCatalog();
  const expected = {
    'qwen2.5-0.5b-instruct-q4_k_m': 8192, 'qwen2.5-1.5b-instruct-q4_k_m': 8192,
    'qwen3-0.6b-q8_0': 16384, 'qwen3-1.7b-q8_0': 16384,
    'qwen3-4b-q4_k_m': 16384, 'qwen3-4b-instruct-2507-q4_k_m': 16384,
    'phi3-mini-4k-instruct-q4': 2048, 'phi4-mini-instruct-q4_k_m': 16384,
    'gemma3-1b-it-qat-q4_0': 8192, 'gemma3-4b-it-qat-q4_0': 8192,
    'gemma4-e2b-it-qat-q4_0': 16384, 'gemma4-e4b-it-qat-q4_0': 16384,
  };
  assert.deepEqual(Object.fromEntries(variants.map(v => [v.id, v.contextWindow.maximumOutputTokens])), expected);
  for (const variant of variants) assert.ok(variant.contextWindow.maximumOutputTokens < variant.contextWindow.maximumTokens);
  for (const maximumOutputTokens of [undefined, 0, -1, 8192.5, 8193, 32768, Number.MAX_SAFE_INTEGER]) {
    assert.throws(() => validateVariant(fixtureVariant({ contextWindow: { maximumTokens: 32768, maximumOutputTokens } })), /context window/);
  }
});

test('variant validation rejects untrusted publishers, mutable pins, unsafe paths, and unbounded sizes before download', () => {
  for (const invalid of [
    { repository: 'individual-person/Model-GGUF' }, { repository: 'Qwen/../escape' },
    { family: 'phi4', repository: 'unsloth/Phi-4-GGUF', licenseIdentifier: 'MIT' },
    { revision: 'main' }, { sha256: 'invalid' }, { id: '../escape' },
    { fileName: '../escape.gguf' }, { fileName: 'nested/model.gguf' }, { fileName: 'model.bin' },
    { byteCount: -1 }, { byteCount: 1.5 }, { byteCount: Number.MAX_SAFE_INTEGER },
    { licenseIdentifier: 'qwen-research' }, { licenseURL: 'http://www.apache.org/license' },
  ]) assert.throws(() => validateVariant(fixtureVariant(invalid)));
});

test('download streams one pinned artifact, validates it, and reuses only a hash-verified cached file', async () => {
  await temporary(async root => {
    const variant = fixtureVariant();
    const requests = [];
    const fetchImpl = async (url, options) => {
      requests.push(url.href);
      assert.equal(options.redirect, 'follow');
      return streamedResponse([bytes.subarray(0, 3), bytes.subarray(3, 17), bytes.subarray(17)], { 'content-length': String(bytes.length) });
    };
    const first = await prepareVariant(variant, { fixturesRoot: root, fetchImpl });
    assert.equal(first.downloaded, true);
    assert.equal(first.modelPath, join(root, variant.id, variant.fileName));
    assert.deepEqual(await readFile(first.modelPath), bytes);
    assert.deepEqual(requests, ['https://huggingface.co/Qwen/Synthetic-GGUF/resolve/' + variant.revision + '/synthetic.gguf']);
    const cached = await prepareVariant(variant, { fixturesRoot: root, fetchImpl: () => { throw new Error('Verified cache must avoid the network'); } });
    assert.equal(cached.downloaded, false);
    assert.deepEqual(await readdir(join(root, variant.id)), [variant.fileName]);
    // Same-size cache corruption must trigger a fresh verified download.
    await writeFile(first.modelPath, Buffer.alloc(bytes.length, 0));
    const repaired = await prepareVariant(variant, { fixturesRoot: root, fetchImpl });
    assert.equal(repaired.downloaded, true);
    assert.deepEqual(await readFile(repaired.modelPath), bytes);
    assert.equal(requests.length, 2);
  });
});

test('truncated, oversized, and wrong-digest streams are rejected with no published model or partial bytes', async () => {
  const cases = [
    { body: bytes.subarray(0, -1), error: /truncated/ },
    { body: Buffer.concat([bytes, Buffer.from('!')]), error: /exceeded/ },
    { body: Buffer.alloc(bytes.length, 1), error: /SHA-256/ },
  ];
  for (const entry of cases) await temporary(async root => {
    const variant = fixtureVariant();
    await assert.rejects(prepareVariant(variant, { fixturesRoot: root,
      fetchImpl: async () => streamedResponse([entry.body.subarray(0, 4), entry.body.subarray(4)]),
    }), entry.error);
    await assertNoPublishedOrPartial(join(root, variant.id));
  });
});

test('incorrect Content-Length and HTTP failures cancel without creating fixture bytes', async () => {
  for (const response of [
    () => new Response(bytes, { headers: { 'content-length': String(bytes.length + 1) } }),
    () => new Response(bytes, { headers: { 'content-length': 'not-a-number' } }),
    () => new Response('unavailable', { status: 503 }),
  ]) await temporary(async root => {
    const variant = fixtureVariant();
    await assert.rejects(prepareVariant(variant, { fixturesRoot: root, fetchImpl: async () => response() }), /Content-Length|HTTP/);
    await assertNoPublishedOrPartial(join(root, variant.id));
  });
});

test('transport interruption cleans partial bytes and does not return an inference-ready path', async () => {
  await temporary(async root => {
    const variant = fixtureVariant();
    let reads = 0;
    const response = new Response(new ReadableStream({
      pull(controller) {
        if (reads++ === 0) controller.enqueue(new Uint8Array(bytes.subarray(0, 8)));
        else controller.error(new Error('Synthetic interrupted transfer'));
      },
    }));
    await assert.rejects(prepareVariant(variant, { fixturesRoot: root, fetchImpl: async () => response }), /interrupted transfer/);
    await assertNoPublishedOrPartial(join(root, variant.id));
  });
});

test('fixture roots cannot follow directory links or replace a non-file target', async () => {
  await temporary(async root => {
    const outside = join(root, 'outside');
    const link = join(root, 'linked-root');
    await mkdir(outside);
    await symlink(outside, link, process.platform === 'win32' ? 'junction' : 'dir');
    const fetchImpl = () => { throw new Error('Unsafe paths must be rejected before HTTP'); };
    await assert.rejects(prepareVariant(fixtureVariant(), { fixturesRoot: link, fetchImpl }), /Unsafe fixture directory/);
    assert.deepEqual(await readdir(outside), []);
    const variant = fixtureVariant();
    const directory = join(root, variant.id);
    await mkdir(join(directory, variant.fileName), { recursive: true });
    await assert.rejects(prepareVariant(variant, { fixturesRoot: root, fetchImpl }), /Unsafe fixture model file/);
  });
});
