import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { createReadStream } from 'node:fs';
import { join } from 'node:path';

const appID = 'com.niranjankaruna.localminutes';
const appRoot = 'Payload/LocalMinutes.app';
const extensionRoot = `${appRoot}/PlugIns/LocalMinutesLiveActivity.appex`;

export function validateDeviceBundles(bundleSet) {
  for (const [target, identifier, executable, packageType] of [
    ['app', appID, 'LocalMinutes', 'APPL'],
    ['extension', `${appID}.LiveActivity`, 'LocalMinutesLiveActivity', 'XPC!']
  ]) {
    const bundle = bundleSet?.[target];
    assert.ok(bundle?.info, `Missing ${target} metadata`);
    const info = bundle.info;
    assert.equal(info.CFBundleIdentifier, identifier, `${target} bundle identifier changed`);
    assert.equal(info.CFBundleExecutable, executable, `${target} executable is unexpected`);
    assert.equal(info.CFBundlePackageType, packageType, `${target} package type is unexpected`);
    assert.deepEqual(bundle.architectures, ['arm64'], `${target} requires the arm64 device architecture`);
    assert.ok(Array.isArray(bundle.platforms) && bundle.platforms.length > 0
      && bundle.platforms.every(platform => platform === 'IOS'), `${target} requires only IOS device platforms`);
    assert.deepEqual(info.CFBundleSupportedPlatforms, ['iPhoneOS'], `${target} supported platform must be iPhoneOS`);
    assert.equal(info.MinimumOSVersion, '18.0', `${target} deployment version must be 18.0`);
  }
  const info = bundleSet.app.info;
  assert.ok(typeof info.NSMicrophoneUsageDescription === 'string'
    && info.NSMicrophoneUsageDescription.trim().length > 0, 'A microphone purpose is required');
  assert.deepEqual(info.UIBackgroundModes, ['audio'], 'Only the audio background mode is allowed');
  assert.equal(info.NSSupportsLiveActivities, true, 'Live Activity support is required');
  assert.equal(bundleSet.extension.info.NSExtension?.NSExtensionPointIdentifier,
    'com.apple.widgetkit-extension', 'The extension must use WidgetKit');
  return {
    appBundleIdentifier: appID, extensionBundleIdentifier: `${appID}.LiveActivity`,
    minimumOSVersion: '18.0', architecture: 'arm64', platform: 'IOS'
  };
}

// Names only: real packaging separately rejects links and checks the created ZIP.
export function validateArchiveEntries(entries) {
  assert.ok(Array.isArray(entries) && entries.length > 0, 'Archive entries are missing');
  const seen = new Set();
  for (const entry of entries) {
    assert.ok(typeof entry === 'string' && entry.length > 0 && !/[\\\x00-\x1f\x7f:]/.test(entry), 'Unsafe archive path');
    const path = entry.endsWith('/') ? entry.slice(0, -1) : entry;
    const components = path.split('/');
    assert.ok(components.every(component => component !== '' && component !== '.' && component !== '..'), 'Noncanonical archive path');
    assert.ok(!seen.has(path), 'Duplicate archive entry');
    seen.add(path);
    assert.ok(path === 'Payload' || path === appRoot || path.startsWith(`${appRoot}/`), 'Unexpected Payload archive root');
    for (const [index, component] of components.entries()) {
      if (component.endsWith('.app')) assert.equal(index, 1, 'Unexpected application in archive');
      if (component.endsWith('.appex')) {
        assert.equal(components.slice(0, index + 1).join('/'), extensionRoot, 'Unexpected archive extension');
      }
    }
  }
  for (const required of [`${appRoot}/Info.plist`, `${appRoot}/LocalMinutes`,
    `${extensionRoot}/Info.plist`, `${extensionRoot}/LocalMinutesLiveActivity`]) {
    assert.ok(seen.has(required), `Missing archive product: ${required}`);
  }
}

function nativeTool(tool, args) {
  return execFileSync(tool, args, { encoding: 'utf8', timeout: 10_000, maxBuffer: 4 * 1024 * 1024 });
}

export function inspectNativeBundle(bundlePath, run = nativeTool) {
  const info = JSON.parse(run('/usr/bin/plutil', ['-convert', 'json', '-o', '-', join(bundlePath, 'Info.plist')]));
  const name = info.CFBundleExecutable;
  assert.ok(typeof name === 'string' && /^[A-Za-z0-9_.-]+$/.test(name) && name !== '.' && name !== '..', 'Unsafe bundle executable path');
  const executable = join(bundlePath, name);
  const architectures = run('/usr/bin/lipo', ['-archs', executable]).trim().split(/\s+/).filter(Boolean);
  const buildInfo = run('/usr/bin/xcrun', ['vtool', '-show-build', executable]);
  const platforms = [...buildInfo.matchAll(/^\s*platform\s+(\S+)\s*$/gm)].map(match => match[1]);
  return { info, architectures, platforms };
}

export async function sha256File(filePath) {
  const hash = createHash('sha256');
  for await (const chunk of createReadStream(filePath)) hash.update(chunk);
  return hash.digest('hex');
}

export async function verifyFileSHA256(filePath, expected) {
  assert.match(expected, /^[a-fA-F0-9]{64}$/, 'Invalid SHA-256 checksum');
  assert.equal(await sha256File(filePath), expected.toLowerCase(), 'SHA-256 checksum mismatch');
  return true;
}
