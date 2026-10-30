import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, lstatSync, mkdirSync, mkdtempSync, rmSync, symlinkSync, unlinkSync, writeFileSync } from 'node:fs';
import { basename, dirname, join, resolve } from 'node:path';
import { auditInputTree, validatePackagePaths } from '../package-ios.mjs';

// Filesystem boundary fixtures only. They are not native products or inference.
function withFixture(body) {
  const root = resolve('.agent-local'); mkdirSync(root, { recursive: true });
  const folder = mkdtempSync(join(root, 'package-audit-'));
  const appPath = join(folder, 'LocalMinutes.app');
  const alias = join(folder, 'alias');
  try {
    for (const name of ['Info.plist', 'LocalMinutes', 'PlugIns/LocalMinutesLiveActivity.appex/Info.plist',
      'PlugIns/LocalMinutesLiveActivity.appex/LocalMinutesLiveActivity']) {
      const file = join(appPath, name); mkdirSync(dirname(file), { recursive: true });
      writeFileSync(file, 'synthetic filesystem fixture, not a native binary');
    }
    body({ folder, appPath, alias, outputDirectory: join(folder, 'output') });
  } finally {
    // Remove the owned junction/link itself before recursive fixture cleanup.
    if (existsSync(alias) && lstatSync(alias).isSymbolicLink()) unlinkSync(alias);
    if (dirname(folder) !== root || !basename(folder).startsWith('package-audit-')) throw new Error('Unsafe audit fixture cleanup');
    rmSync(folder, { recursive: true, force: true });
  }
}

test('filesystem audit accepts a clean synthetic tree and fresh external output', () => {
  withFixture(value => {
    assert.doesNotThrow(() => auditInputTree(value.appPath));
    assert.doesNotThrow(() => validatePackagePaths(value));
    assert.equal(existsSync(value.outputDirectory), false);
  });
});

for (const name of ['meeting.db-wal', 'meeting.db-shm']) {
  test(`rejects private database sidecar ${name}`, () => {
    withFixture(({ appPath }) => {
      writeFileSync(join(appPath, name), 'synthetic boundary fixture');
      assert.throws(() => auditInputTree(appPath), /private|forbidden|secret/i);
    });
  });
}

for (const name of ['transcripts', 'recordings', 'device-evidence', 'diagnostics-raw']) {
  test(`rejects the private directory ${name}`, () => {
    withFixture(({ appPath }) => {
      const directory = join(appPath, 'PlugIns/LocalMinutesLiveActivity.appex', name);
      mkdirSync(directory); writeFileSync(join(directory, 'fixture.txt'), 'synthetic boundary fixture');
      assert.throws(() => auditInputTree(appPath), /private|forbidden|secret/i);
    });
  });
}

test('rejects output whose ancestor alias resolves inside the input app', () => {
  withFixture(value => {
    symlinkSync(value.appPath, value.alias, process.platform === 'win32' ? 'junction' : 'dir');
    value.outputDirectory = join(value.alias, 'package-output');
    assert.throws(() => validatePackagePaths(value), /output|inside|input|bundle/i);
    assert.equal(existsSync(value.outputDirectory), false);
  });
});
