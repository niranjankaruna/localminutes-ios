import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { basename, dirname, join, resolve } from 'node:path';
import { auditInputTree } from '../package-ios.mjs';

// Real filesystem boundaries with synthetic bytes, never a native-build claim.
function withWhisperBundle(body) {
  const root = resolve('.agent-local');
  mkdirSync(root, { recursive: true });
  const folder = mkdtempSync(join(root, 'whisper-package-policy-'));
  const app = join(folder, 'LocalMinutes.app');
  try {
    for (const name of ['Info.plist', 'LocalMinutes',
      'PlugIns/LocalMinutesLiveActivity.appex/Info.plist',
      'PlugIns/LocalMinutesLiveActivity.appex/LocalMinutesLiveActivity',
      'Frameworks/whisper.framework/Info.plist', 'Frameworks/whisper.framework/whisper']) {
      const file = join(app, name);
      mkdirSync(dirname(file), { recursive: true });
      writeFileSync(file, 'synthetic packaging-boundary fixture');
    }
    body(app);
  } finally {
    if (dirname(folder) !== root || !basename(folder).startsWith('whisper-package-policy-')) {
      throw new Error('Unsafe Whisper packaging fixture cleanup');
    }
    rmSync(folder, { recursive: true, force: true });
  }
}

test('filesystem audit permits the embedded Whisper framework without bundled weights', () => {
  withWhisperBundle(app => assert.doesNotThrow(() => auditInputTree(app)));
});

test('filesystem audit rejects a Whisper GGML model weight in app resources', () => {
  withWhisperBundle(app => {
    const model = join(app, 'Resources', 'ggml-tiny.en.bin');
    mkdirSync(dirname(model), { recursive: true });
    writeFileSync(model, 'synthetic model-weight boundary fixture');
    assert.throws(() => auditInputTree(app), /private|forbidden|model|weight/i);
  });
});

test('filesystem audit rejects raw PyTorch and safetensors model weights', () => {
  const accepted = [];
  for (const name of ['model.safetensors', 'pytorch_model.bin', 'encoder.pt', 'encoder.pth']) {
    withWhisperBundle(app => {
      const model = join(app, 'Resources', name);
      mkdirSync(dirname(model), { recursive: true });
      writeFileSync(model, 'synthetic model-weight boundary fixture');
      try { auditInputTree(app); accepted.push(name); }
      catch (error) { assert.match(error.message, /private|forbidden|model|weight/i); }
    });
  }
  assert.deepEqual(accepted, [], 'Model weights must stay outside the packaged app');
});
