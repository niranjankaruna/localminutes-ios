import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { basename, join, resolve } from 'node:path';
import test from 'node:test';

// Reads actual compiled Mach-O bytes. Missing products fail; source-text checks
// or a fabricated buffer are not evidence that Release excluded the hook.
const releaseRoot = resolve(process.env.LOCALMINUTES_RELEASE_APP_PATH ??
  'build/device/Build/Products/Release-iphoneos/LocalMinutes.app');
const debugRoot = resolve(process.env.LOCALMINUTES_DEBUG_APP_PATH ??
  'build/simulator/Build/Products/Debug-iphonesimulator/LocalMinutes.app');
const canary = 'LOCALMINUTES_DEBUG_LIBRARY_FIXTURE_CANARY_v1';
const modelCanary = 'LOCALMINUTES_DEBUG_MODEL_ACCESSIBILITY_FIXTURE_CANARY_v1';
const markers = [canary, '--ui-test-library-fixture', 'LOCALMINUTES_UI_LIBRARY_TOKEN',
  'LOCALMINUTES_UI_LIBRARY_AX5',
  '--ui-test-library-content-status',
  '--ui-test-library-pagination', 'UI Earlier Archive Target',
  'UI Library Alpha', 'UI Library Beta', 'Alpha shared-term original transcript.',
  'Beta shared-term original transcript.', 'Original Alpha manual note.', 'Original Beta manual note.',
  'Seeded Alpha generated summary.', 'Seeded Beta generated summary.', 'Seeded Beta private answer.',
  modelCanary, '--ui-test-model-accessibility', 'LOCALMINUTES_UI_MODEL_AX5',
  'LocalMinutesModelAccessibilityUI', 'ui.fixture.models.failure'];

test('actual compiled Release app and extension exclude every library and model UI fixture marker', () => {
  for (const executable of [join(releaseRoot, 'LocalMinutes'),
    join(releaseRoot, 'PlugIns/LocalMinutesLiveActivity.appex/LocalMinutesLiveActivity')]) {
    const bytes = readFileSync(executable);
    assert.ok(bytes.length > 0, 'Actual compiled product is required');
    for (const marker of markers) {
      assert.equal(bytes.includes(Buffer.from(marker, 'utf8')), false,
        `A DEBUG-only UI fixture marker was compiled into Release: ${marker}`);
    }
  }
});

test('actual compiled Debug app contains the linked library and model UI fixture canaries and launch modes', () => {
  const executable = join(debugRoot, 'LocalMinutes');
  const debugDylib = join(debugRoot, 'LocalMinutes.debug.dylib');
  // Xcode's documented unoptimized layout puts app code in this exact dylib
  // and leaves a trampoline executable. Inspect code, never arbitrary resources.
  const codePath = existsSync(debugDylib) ? debugDylib : executable;
  const entry = readFileSync(executable);
  const bytes = readFileSync(codePath);
  const magic = new Set([0xcffaedfe, 0xfeedfacf, 0xcafebabe, 0xbebafeca, 0xcafebabf, 0xbfbafeca]);
  for (const image of [entry, bytes]) {
    assert.ok(image.length >= 4 && magic.has(image.readUInt32BE(0)), 'Actual compiled Mach-O image required');
  }
  console.log(JSON.stringify({ debugFixtureCodeImage: basename(codePath), bytes: bytes.length,
    canary: bytes.includes(Buffer.from(canary, 'utf8')),
    launchMode: bytes.includes(Buffer.from('--ui-test-library-fixture', 'utf8')) }));
  assert.ok(bytes.includes(Buffer.from(canary, 'utf8')), 'A positive Debug control proves the hook was compiled/linked');
  assert.ok(bytes.includes(Buffer.from('--ui-test-library-fixture', 'utf8')));
  assert.ok(bytes.includes(Buffer.from(modelCanary, 'utf8')), 'The model UI fixture must be compiled/linked in Debug');
  assert.ok(bytes.includes(Buffer.from('--ui-test-model-accessibility', 'utf8')));
});
