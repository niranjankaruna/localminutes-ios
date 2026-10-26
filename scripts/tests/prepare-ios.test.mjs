import test from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { existsSync } from 'node:fs';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { promisify } from 'node:util';

const execute = promisify(execFile);
const script = resolve('scripts/prepare-ios.sh').replaceAll('\\', '/');
const bash = process.platform === 'win32' && existsSync('C:/Program Files/Git/bin/bash.exe')
  ? 'C:/Program Files/Git/bin/bash.exe' : 'bash';

// Exercise the real shell argument routing with offline command boundaries.
// No Python interpreter, network, model weights, or Xcode build is invoked.
async function withPreparation(body) {
  const parent = resolve('.agent-local');
  await mkdir(parent, { recursive: true });
  const root = await mkdtemp(join(parent, 'prepare-ios-test-'));
  try {
    const bin = join(root, 'commands');
    await mkdir(bin);
    for (const command of ['python3', 'curl', 'shasum', 'unzip']) {
      await writeFile(join(bin, command), '#!/usr/bin/env bash\n' +
        `printf '${command}:%s\\n' "$*" >> "$PREPARE_TRACE"\n` +
        (command === 'shasum' ? 'while IFS= read -r line; do :; done\n' : ''), { mode: 0o755 });
    }
    const tools = join(root, '.agent-local/tools/xcodegen/bin');
    await mkdir(tools, { recursive: true });
    await writeFile(join(tools, 'xcodegen'), '#!/usr/bin/env bash\nprintf "xcodegen:%s\\n" "$*" >> "$PREPARE_TRACE"\n',
      { mode: 0o755 });
    await writeFile(join(root, 'project.yml'), 'name: synthetic-preparation-fixture\n');
    await writeFile(join(root, 'Package.swift'), '// Synthetic preparation boundary\n');
    const env = { ...process.env, PREPARE_TRACE: 'trace.txt' };
    // Git Bash prepends its own tools when started from Windows. Put the stubs
    // first from inside the shell so curl/unzip cannot reach the real network.
    const run = args => execute(bash, ['--noprofile', '--norc', '-c',
      'export PATH="$PWD/commands:$PATH"; exec bash "$@"', 'prepare-ios-test', script, ...args],
      { cwd: root, env });
    await body({ run, trace: () => readFile(join(root, 'trace.txt'), 'utf8') });
  } finally {
    assert.equal(dirname(resolve(root)), parent);
    await rm(root, { recursive: true, force: true });
  }
}

test('device-only preparation uses the verified prebuilt framework without building a simulator', async () => {
  await withPreparation(async ({ run, trace }) => {
    await run(['--device-only']);
    const calls = await trace();
    assert.match(calls, /^python3:scripts\/fixtures\/prepare_native_summary\.py --framework-only$/m);
    assert.doesNotMatch(calls, /--with-simulator/);
    assert.match(calls, /^xcodegen:generate --spec project\.yml$/m);
  });
});

test('default preparation retains simulator support for screenshot and iOS test workflows', async () => {
  await withPreparation(async ({ run, trace }) => {
    await run([]);
    assert.match(await trace(), /^python3:scripts\/fixtures\/prepare_native_summary\.py --framework-only --with-simulator$/m);
  });
});

test('invalid preparation arguments fail before any native preparation or downloads', async () => {
  for (const args of [['--unknown'], ['--device-only', '--with-simulator']]) {
    await withPreparation(async ({ run, trace }) => {
      await assert.rejects(() => run(args), error => error.code === 2 && /Usage:/.test(error.stderr));
      await assert.rejects(trace, { code: 'ENOENT' });
    });
  }
});
