import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { resolve, join, dirname } from 'node:path';
import { validateDeviceBundles, validateArchiveEntries, inspectNativeBundle, sha256File, verifyFileSHA256 } from '../ios-artifacts.mjs';

// Original non-sensitive boundary fixtures. No fixture represents a native build.
const appID = 'com.niranjankaruna.localminutes';
function bundles() {
  return {
    app: {
      info: {
        CFBundleIdentifier: appID, CFBundleExecutable: 'LocalMinutes', CFBundlePackageType: 'APPL',
        CFBundleSupportedPlatforms: ['iPhoneOS'], MinimumOSVersion: '18.0',
        NSMicrophoneUsageDescription: 'Record meetings you explicitly start.',
        UIBackgroundModes: ['audio', 'processing'], NSSupportsLiveActivities: true,
        BGTaskSchedulerPermittedIdentifiers: [`${appID}.intelligence.*`]
      }, architectures: ['arm64'], platforms: ['IOS']
    },
    extension: {
      info: {
        CFBundleIdentifier: `${appID}.LiveActivity`, CFBundleExecutable: 'LocalMinutesLiveActivity',
        CFBundlePackageType: 'XPC!', CFBundleSupportedPlatforms: ['iPhoneOS'], MinimumOSVersion: '18.0',
        NSExtension: { NSExtensionPointIdentifier: 'com.apple.widgetkit-extension' }
      }, architectures: ['arm64'], platforms: ['IOS']
    }
  };
}

const archiveEntries = [
  'Payload/', 'Payload/LocalMinutes.app/',
  'Payload/LocalMinutes.app/Info.plist', 'Payload/LocalMinutes.app/LocalMinutes',
  'Payload/LocalMinutes.app/PlugIns/LocalMinutesLiveActivity.appex/Info.plist',
  'Payload/LocalMinutes.app/PlugIns/LocalMinutesLiveActivity.appex/LocalMinutesLiveActivity'
];

test('accepts the intended device app and extension metadata', () => {
  assert.deepEqual(validateDeviceBundles(bundles()), {
    appBundleIdentifier: appID, extensionBundleIdentifier: `${appID}.LiveActivity`,
    minimumOSVersion: '18.0', architecture: 'arm64', platform: 'IOS'
  });
});

for (const target of ['app', 'extension']) {
  test(`rejects an arm64 simulator ${target}`, () => {
    const value = bundles(); value[target].platforms = ['IOSSIMULATOR'];
    assert.throws(() => validateDeviceBundles(value), /device|platform/i);
  });
  test(`rejects missing arm64 ${target}`, () => {
    const value = bundles(); value[target].architectures = ['x86_64'];
    assert.throws(() => validateDeviceBundles(value), /arm64|architecture/i);
  });
  test(`rejects an unknown Mach-O platform for ${target}`, () => {
    const value = bundles(); value[target].platforms = [];
    assert.throws(() => validateDeviceBundles(value), /platform/i);
  });
  for (const platforms of [['IOS', 'IOSSIMULATOR'], ['IOS', 'MACOS'], ['MACOS']]) {
    test(`rejects mixed or non-iOS Mach-O platforms ${platforms.join(',')} for ${target}`, () => {
      const value = bundles(); value[target].platforms = platforms;
      assert.throws(() => validateDeviceBundles(value), /device|platform/i);
    });
  }
  test(`requires the correct package type and executable for ${target}`, () => {
    const type = bundles(); type[target].info.CFBundlePackageType = 'BNDL';
    assert.throws(() => validateDeviceBundles(type), /package|type/i);
    for (const executable of ['', '../outside', '/absolute', 'bad\\path', 'OtherExecutable']) {
      const value = bundles(); value[target].info.CFBundleExecutable = executable;
      assert.throws(() => validateDeviceBundles(value), /executable/i);
    }
  });
}

test('rejects changed app or extension identifiers', () => {
  for (const target of ['app', 'extension']) {
    const value = bundles(); value[target].info.CFBundleIdentifier = 'com.unrelated.app';
    assert.throws(() => validateDeviceBundles(value), /identifier/i);
  }
});

test('rejects a missing embedded extension', () => {
  const value = bundles(); delete value.extension;
  assert.throws(() => validateDeviceBundles(value), /extension/i);
});

test('requires truthful microphone, audio and Live Activity configuration', () => {
  for (const [key, wrong] of [['NSMicrophoneUsageDescription', '  '], ['UIBackgroundModes', []], ['NSSupportsLiveActivities', false]]) {
    const value = bundles(); value.app.info[key] = wrong;
    assert.throws(() => validateDeviceBundles(value), /microphone|audio|activity/i);
  }
});

test('rejects unexpected background modes and wrong extension configuration', () => {
  const background = bundles(); background.app.info.UIBackgroundModes.push('voip');
  assert.throws(() => validateDeviceBundles(background), /background|audio/i);
  const extension = bundles(); extension.extension.info.NSExtension.NSExtensionPointIdentifier = 'wrong';
  assert.throws(() => validateDeviceBundles(extension), /extension/i);
});

test('requires the exact background summary task identifier and processing mode', () => {
  for (const identifiers of [undefined, [], ['com.unrelated.app.*'], [`${appID}.intelligence`]]) {
    const value = bundles(); value.app.info.BGTaskSchedulerPermittedIdentifiers = identifiers;
    assert.throws(() => validateDeviceBundles(value), /background intelligence/i);
  }
  const value = bundles(); value.app.info.UIBackgroundModes = ['audio'];
  assert.throws(() => validateDeviceBundles(value), /processing/i);
});

test('requires the pinned deployment target and device supported-platform metadata', () => {
  for (const target of ['app', 'extension']) {
    const version = bundles(); version[target].info.MinimumOSVersion = '26.2';
    assert.throws(() => validateDeviceBundles(version), /deployment|version/i);
    const platform = bundles(); platform[target].info.CFBundleSupportedPlatforms = ['iPhoneSimulator'];
    assert.throws(() => validateDeviceBundles(platform), /platform/i);
  }
});

test('rejects executable traversal before running native tools', () => {
  let calls = 0;
  const run = () => { calls++; return JSON.stringify({ CFBundleExecutable: '../outside' }); };
  assert.throws(() => inspectNativeBundle('/owned/LocalMinutes.app', run), /executable|path/i);
  assert.equal(calls, 1);
});

test('collects actual-tool boundary output without confusing simulator and device', () => {
  const calls = [];
  const bundlePath = join(resolve('.agent-local'), 'Local Minutes & $unexpanded.app');
  const info = bundles().app.info;
  const run = (tool, args) => {
    calls.push([tool, args]);
    if (tool.endsWith('plutil')) return JSON.stringify(info);
    if (tool.endsWith('lipo')) return 'arm64\n';
    if (tool.endsWith('xcrun')) return 'Load command 10\n cmd LC_BUILD_VERSION\n platform IOS\n minos 18.0\n';
    throw new Error('Unexpected native tool');
  };
  assert.deepEqual(inspectNativeBundle(bundlePath, run), {
    info, architectures: ['arm64'], platforms: ['IOS']
  });
  assert.deepEqual(calls, [
    ['/usr/bin/plutil', ['-convert', 'json', '-o', '-', join(bundlePath, 'Info.plist')]],
    ['/usr/bin/lipo', ['-archs', join(bundlePath, 'LocalMinutes')]],
    ['/usr/bin/xcrun', ['vtool', '-show-build', join(bundlePath, 'LocalMinutes')]]
  ]);
});

test('accepts only the intended Payload archive structure', () => {
  assert.doesNotThrow(() => validateArchiveEntries(archiveEntries));
});

for (const bad of ['../outside', '/absolute', 'C:/absolute', 'Payload/../outside', 'Payload/LocalMinutes.app/../../outside', 'Payload\\outside', 'Payload/LocalMinutes.app/bad\nname', 'Payload/LocalMinutes.app/./Info.plist', 'Payload//LocalMinutes.app/Info.plist']) {
  test(`rejects unsafe archive path ${JSON.stringify(bad)}`, () => {
    assert.throws(() => validateArchiveEntries([...archiveEntries, bad]), /path|archive|payload/i);
  });
}

test('rejects extra root products, extra extensions and duplicate entries', () => {
  for (const entry of ['Other.app/Info.plist', 'Payload/Other.app/Info.plist', 'Payload/LocalMinutes.app/PlugIns/Other.appex/Info.plist', archiveEntries[2]]) {
    assert.throws(() => validateArchiveEntries([...archiveEntries, entry]), /archive|payload|duplicate|extension/i);
  }
});

test('rejects an archive missing the extension executable', () => {
  assert.throws(() => validateArchiveEntries(archiveEntries.slice(0, -1)), /missing|extension/i);
});

test('hashes a real local file and rejects a checksum mismatch', async () => {
  const root = resolve('.agent-local'); mkdirSync(root, { recursive: true });
  const folder = mkdtempSync(join(root, 'artifact-test-'));
  try {
    const file = join(folder, 'fixture.bin'); writeFileSync(file, 'abc');
    const hash = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';
    assert.equal(await sha256File(file), hash);
    assert.equal(await verifyFileSHA256(file, hash), true);
    await assert.rejects(() => verifyFileSHA256(file, '0'.repeat(64)), /checksum|hash/i);
    await assert.rejects(() => verifyFileSHA256(file, 'invalid'), /checksum|hash/i);
  } finally {
    if (dirname(folder) !== root || !folder.startsWith(join(root, 'artifact-test-'))) throw new Error('Unsafe fixture cleanup');
    rmSync(folder, { recursive: true, force: true });
  }
});
