import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import test from 'node:test';

// Reads actual compiled Mach-O bytes. Missing products fail; source-text checks
// or a fabricated buffer are not evidence that Release excluded the hook.
const releaseRoot = resolve(process.env.LOCALMINUTES_RELEASE_APP_PATH ??
  'build/device/Build/Products/Release-iphoneos/LocalMinutes.app');
const debugRoot = resolve(process.env.LOCALMINUTES_DEBUG_APP_PATH ??
  'build/simulator/Build/Products/Debug-iphonesimulator/LocalMinutes.app');
const canary = 'LOCALMINUTES_DEBUG_LIBRARY_FIXTURE_CANARY_v1';
const markers = [canary, '--ui-test-library-fixture', 'LOCALMINUTES_UI_LIBRARY_TOKEN',
  'UI Library Alpha', 'UI Library Beta', 'Alpha shared-term original transcript.',
  'Beta shared-term original transcript.', 'Original Alpha manual note.', 'Original Beta manual note.',
  'Seeded Alpha generated summary.', 'Seeded Beta generated summary.', 'Seeded Beta private answer.'];

test('actual compiled Release app and extension exclude every library fixture mode and seed marker', () => {
  for (const executable of [join(releaseRoot, 'LocalMinutes'),
    join(releaseRoot, 'PlugIns/LocalMinutesLiveActivity.appex/LocalMinutesLiveActivity')]) {
    const bytes = readFileSync(executable);
    assert.ok(bytes.length > 0, 'Actual compiled product is required');
    for (const marker of markers) {
      assert.equal(bytes.includes(Buffer.from(marker, 'utf8')), false,
        `A DEBUG-only library fixture marker was compiled into Release: ${marker}`);
    }
  }
});

test('actual compiled Debug app contains the linked library fixture canary and launch mode', () => {
  const bytes = readFileSync(join(debugRoot, 'LocalMinutes'));
  assert.ok(bytes.includes(Buffer.from(canary, 'utf8')), 'A positive Debug control proves the hook was compiled/linked');
  assert.ok(bytes.includes(Buffer.from('--ui-test-library-fixture', 'utf8')));
});
