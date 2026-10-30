import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { inspectNativeBundle, validateDeviceBundles } from '../ios-artifacts.mjs';

// These tests run only after actual Xcode builds. No fixtures or platform skips.
function builtBundles(configuration) {
  const appPath = resolve(`build/${configuration}/Build/Products/${configuration === 'device' ? 'Release-iphoneos' : 'Debug-iphonesimulator'}/LocalMinutes.app`);
  const plugins = join(appPath, 'PlugIns');
  assert.deepEqual(readdirSync(plugins).sort(), ['LocalMinutesLiveActivity.appex']);
  return {
    app: inspectNativeBundle(appPath),
    extension: inspectNativeBundle(join(plugins, 'LocalMinutesLiveActivity.appex'))
  };
}

function requireMatchingVersions(bundles) {
  const version = bundles.app.info.CFBundleShortVersionString;
  const build = bundles.app.info.CFBundleVersion;
  assert.match(version, /^\d+\.\d+(?:\.\d+)?$/);
  assert.match(build, /^\d+$/);
  for (const [bundle, identifier, executable, packageType] of [
    [bundles.app, 'com.niranjankaruna.localminutes', 'LocalMinutes', 'APPL'],
    [bundles.extension, 'com.niranjankaruna.localminutes.LiveActivity', 'LocalMinutesLiveActivity', 'XPC!']
  ]) {
    assert.equal(bundle.info.CFBundleShortVersionString, version);
    assert.equal(bundle.info.CFBundleVersion, build);
    assert.equal(bundle.info.CFBundleIdentifier, identifier);
    assert.equal(bundle.info.CFBundleExecutable, executable);
    assert.equal(bundle.info.CFBundlePackageType, packageType);
    assert.equal(bundle.info.MinimumOSVersion, '18.0');
  }
}

test('actual device app and embedded Live Activity satisfy the unsigned build contract', () => {
  const bundles = builtBundles('device');
  requireMatchingVersions(bundles);
  assert.equal(bundles.app.info.NSSupportsLiveActivities, true,
    'Compiled app must enable Live Activities before this native gate can pass');
  assert.deepEqual(validateDeviceBundles(bundles), {
    appBundleIdentifier: 'com.niranjankaruna.localminutes',
    extensionBundleIdentifier: 'com.niranjankaruna.localminutes.LiveActivity',
    minimumOSVersion: '18.0', architecture: 'arm64', platform: 'IOS'
  });
  console.log(JSON.stringify({ nativeDeviceProducts: bundles }));
});

test('actual simulator app and extension cannot be packaged as a device product', () => {
  const bundles = builtBundles('simulator');
  requireMatchingVersions(bundles);
  for (const bundle of [bundles.app, bundles.extension]) {
    assert.ok(bundle.architectures.length > 0, 'Simulator must contain executable slices');
    assert.ok(bundle.platforms.length > 0 && bundle.platforms.every(value => value === 'IOSSIMULATOR'));
    assert.deepEqual(bundle.info.CFBundleSupportedPlatforms, ['iPhoneSimulator']);
  }
  assert.throws(() => validateDeviceBundles(bundles), /device|architecture|platform/i);
  console.log(JSON.stringify({ nativeSimulatorProducts: bundles }));
});
