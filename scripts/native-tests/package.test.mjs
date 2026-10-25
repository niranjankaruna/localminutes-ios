import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, statSync, symlinkSync, writeFileSync } from 'node:fs';
import { resolve, join, dirname, basename } from 'node:path';
import { createUnsignedIPA } from '../package-ios.mjs';
import { inspectNativeBundle, sha256File, validateArchiveEntries, verifyFileSHA256 } from '../ios-artifacts.mjs';

const builtApp = resolve('build/device/Build/Products/Release-iphoneos/LocalMinutes.app');
const simulatorApp = resolve('build/simulator/Build/Products/Debug-iphonesimulator/LocalMinutes.app');
const sourceCommit = execFileSync('git', ['rev-parse', 'HEAD'], { encoding: 'utf8' }).trim();
const root = resolve('.agent-local');

async function withWorkspace(body) {
  mkdirSync(root, { recursive: true });
  const folder = mkdtempSync(join(root, 'package-test-'));
  try {
    await body(folder);
  } finally {
    if (dirname(folder) !== root || !basename(folder).startsWith('package-test-')) throw new Error('Unsafe fixture cleanup');
    rmSync(folder, { recursive: true, force: true });
  }
}

function options(folder, appPath = builtApp) {
  return { appPath, outputDirectory: join(folder, 'output'), sourceCommit };
}

function inspectZIP(file) {
  // Independent standard-library reader: no extraction or fixture metadata.
  return JSON.parse(execFileSync('/usr/bin/python3', ['-c', `
import hashlib, json, plistlib, stat, sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as archive:
    app = 'Payload/LocalMinutes.app/'
    extension = app + 'PlugIns/LocalMinutesLiveActivity.appex/'
    print(json.dumps({
        'entries': [{'name': i.filename, 'mode': stat.S_IFMT(i.external_attr >> 16)} for i in archive.infolist()],
        'crcFailure': archive.testzip(),
        'appInfo': plistlib.loads(archive.read(app + 'Info.plist')),
        'extensionInfo': plistlib.loads(archive.read(extension + 'Info.plist')),
        'appInfoSHA256': hashlib.sha256(archive.read(app + 'Info.plist')).hexdigest(),
        'extensionInfoSHA256': hashlib.sha256(archive.read(extension + 'Info.plist')).hexdigest(),
        'appExecutableSHA256': hashlib.sha256(archive.read(app + 'LocalMinutes')).hexdigest(),
        'extensionExecutableSHA256': hashlib.sha256(archive.read(extension + 'LocalMinutesLiveActivity')).hexdigest()
    }))
`, file], { encoding: 'utf8', timeout: 15_000, maxBuffer: 4 * 1024 * 1024 }));
}

test('packages actual device binaries into an unsigned IPA with verified checksum and source manifest', async () => {
  await withWorkspace(async folder => {
    assert.match(sourceCommit, /^[0-9a-f]{40}$/);
    const value = options(folder);
    const result = await createUnsignedIPA(value);
    for (const file of [result.ipaPath, result.checksumPath, result.manifestPath]) {
      assert.equal(dirname(file), value.outputDirectory, 'Outputs must stay inside the requested fresh directory');
    }
    const builtInfo = inspectNativeBundle(builtApp).info;
    const expectedName = `LocalMinutes-${builtInfo.CFBundleShortVersionString}-${sourceCommit}-unsigned.ipa`;
    assert.equal(basename(result.ipaPath), expectedName);
    assert.ok(existsSync(result.ipaPath), 'A real IPA file must be written');
    const hash = await sha256File(result.ipaPath);
    assert.equal(readFileSync(result.checksumPath, 'utf8'), `${hash}  ${expectedName}\n`);
    assert.equal(await verifyFileSHA256(result.ipaPath, hash), true);
    const manifest = JSON.parse(readFileSync(result.manifestPath, 'utf8'));
    assert.equal(manifest.schemaVersion, 1);
    assert.equal(manifest.sourceCommit, sourceCommit);
    assert.equal(manifest.appVersion, builtInfo.CFBundleShortVersionString);
    assert.equal(manifest.buildNumber, builtInfo.CFBundleVersion);
    assert.equal(manifest.artifact, expectedName);
    assert.equal(manifest.sha256, hash);
    assert.equal(manifest.sizeBytes, statSync(result.ipaPath).size);
    assert.ok(manifest.sizeBytes > 0);
    assert.equal(manifest.signing, 'unsigned');
    assert.equal(manifest.deviceValidation, 'NOT_RUN');
    assert.match(manifest.toolchain.xcode, /Xcode 26\.2/);
    assert.equal(manifest.toolchain.iosSDK, '26.2');
    assert.equal(manifest.toolchain.runnerImage, process.env.ImageVersion ?? null);
    assert.equal(manifest.bundles.extensionBundleIdentifier, 'com.niranjankaruna.localminutes.LiveActivity');
    const archive = inspectZIP(result.ipaPath);
    assert.equal(archive.crcFailure, null);
    validateArchiveEntries(archive.entries.map(entry => entry.name));
    assert.ok(archive.entries.every(entry => [0o100000, 0o040000].includes(entry.mode)), 'ZIP must contain only regular files/directories');
    assert.equal(archive.appInfo.NSSupportsLiveActivities, true);
    assert.equal(archive.appInfo.LocalMinutesSourceCommit, sourceCommit);
    assert.equal(archive.extensionInfo.LocalMinutesSourceCommit, sourceCommit);
    assert.equal(archive.appInfoSHA256, await sha256File(join(builtApp, 'Info.plist')));
    assert.equal(archive.extensionInfoSHA256, await sha256File(join(builtApp, 'PlugIns/LocalMinutesLiveActivity.appex/Info.plist')));
    assert.equal(archive.extensionInfo.CFBundleIdentifier, 'com.niranjankaruna.localminutes.LiveActivity');
    assert.equal(archive.appExecutableSHA256, await sha256File(join(builtApp, 'LocalMinutes')));
    assert.equal(archive.extensionExecutableSHA256, await sha256File(join(builtApp, 'PlugIns/LocalMinutesLiveActivity.appex/LocalMinutesLiveActivity')));
    const tampered = join(folder, 'tampered.ipa');
    cpSync(result.ipaPath, tampered);
    writeFileSync(tampered, 'changed bytes');
    await assert.rejects(() => verifyFileSHA256(tampered, hash), /checksum|hash/i);
  });
});

test('rejects an actual simulator app before creating any output', async () => {
  await withWorkspace(async folder => {
    const value = options(folder, simulatorApp);
    await assert.rejects(() => createUnsignedIPA(value), /device|architecture|platform/i);
    assert.equal(existsSync(value.outputDirectory), false);
  });
});

test('rejects an unverified source commit before creating output', async () => {
  await withWorkspace(async folder => {
    const value = { ...options(folder), sourceCommit: '0'.repeat(40) };
    await assert.rejects(() => createUnsignedIPA(value), /source|commit/i);
    assert.equal(existsSync(value.outputDirectory), false);
  });
});

test('rejects actual bundle metadata stamped with a different source commit', async () => {
  for (const target of ['', 'PlugIns/LocalMinutesLiveActivity.appex']) {
    await withWorkspace(async folder => {
      const appPath = join(folder, 'LocalMinutes.app'); cpSync(builtApp, appPath, { recursive: true });
      execFileSync('/usr/bin/python3', ['-c', `
import plistlib, sys
with open(sys.argv[1], 'rb') as file: info = plistlib.load(file)
info['LocalMinutesSourceCommit'] = '0' * 40
with open(sys.argv[1], 'wb') as file: plistlib.dump(info, file)
`, join(appPath, target, 'Info.plist')], { timeout: 10_000 });
      const value = options(folder, appPath);
      await assert.rejects(() => createUnsignedIPA(value), /source|commit/i);
      assert.equal(existsSync(value.outputDirectory), false);
    });
  }
});

for (const kind of ['internal', 'relative-external', 'absolute-external']) {
  test(`rejects ${kind} symlinks inside the actual app`, async () => {
    await withWorkspace(async folder => {
      const appPath = join(folder, 'LocalMinutes.app');
      cpSync(builtApp, appPath, { recursive: true });
      const outside = join(folder, 'outside.txt'); writeFileSync(outside, 'non-sensitive fixture');
      const target = kind === 'internal' ? 'LocalMinutes' : kind === 'relative-external' ? '../outside.txt' : outside;
      symlinkSync(target, join(appPath, 'unexpected-link'));
      const value = options(folder, appPath);
      await assert.rejects(() => createUnsignedIPA(value), /link/i);
      assert.equal(existsSync(value.outputDirectory), false);
    });
  });
}

test('rejects a symlink used as the root app bundle', async () => {
  await withWorkspace(async folder => {
    const linked = join(folder, 'LocalMinutes.app'); symlinkSync(builtApp, linked);
    const value = options(folder, linked);
    await assert.rejects(() => createUnsignedIPA(value), /link/i);
    assert.equal(existsSync(value.outputDirectory), false);
  });
});

test('rejects symlinks nested inside extension resources', async () => {
  await withWorkspace(async folder => {
    const appPath = join(folder, 'LocalMinutes.app'); cpSync(builtApp, appPath, { recursive: true });
    const resources = join(appPath, 'PlugIns/LocalMinutesLiveActivity.appex/Resources'); mkdirSync(resources);
    const outside = join(folder, 'outside.txt'); writeFileSync(outside, 'synthetic fixture');
    symlinkSync(outside, join(resources, 'unexpected-link'));
    const value = options(folder, appPath);
    await assert.rejects(() => createUnsignedIPA(value), /link/i);
    assert.equal(existsSync(value.outputDirectory), false);
  });
});

test('rejects signing material in either app or extension', async () => {
  for (const target of ['', 'PlugIns/LocalMinutesLiveActivity.appex']) {
    for (const name of ['embedded.mobileprovision', '_CodeSignature/CodeResources']) {
      await withWorkspace(async folder => {
        const appPath = join(folder, 'LocalMinutes.app'); cpSync(builtApp, appPath, { recursive: true });
        const file = join(appPath, target, name); mkdirSync(dirname(file), { recursive: true });
        writeFileSync(file, 'synthetic fixture, no signing data');
        const value = options(folder, appPath);
        await assert.rejects(() => createUnsignedIPA(value), /sign|provision/i);
        assert.equal(existsSync(value.outputDirectory), false);
      });
    }
  }
});

test('rejects model weights, recordings, databases and local secrets in the app', async () => {
  for (const name of ['weights.gguf', 'meeting.caf', 'meeting.wav', 'meeting.sqlite', '.env', 'PlugIns/LocalMinutesLiveActivity.appex/Resources/meeting.caf']) {
    await withWorkspace(async folder => {
      const appPath = join(folder, 'LocalMinutes.app'); cpSync(builtApp, appPath, { recursive: true });
      const file = join(appPath, name); mkdirSync(dirname(file), { recursive: true });
      writeFileSync(file, 'synthetic non-sensitive fixture');
      const value = options(folder, appPath);
      await assert.rejects(() => createUnsignedIPA(value), /private|model|forbidden|secret/i);
      assert.equal(existsSync(value.outputDirectory), false);
    });
  }
});

test('preserves an existing output directory instead of overwriting it', async () => {
  await withWorkspace(async folder => {
    const value = options(folder); mkdirSync(value.outputDirectory);
    const marker = join(value.outputDirectory, 'keep.txt'); writeFileSync(marker, 'preserve me');
    await assert.rejects(() => createUnsignedIPA(value), /exist|output/i);
    assert.equal(readFileSync(marker, 'utf8'), 'preserve me');
    assert.deepEqual(readdirSync(value.outputDirectory), ['keep.txt']);
  });
});

test('rejects output placed inside its input app before writing anything', async () => {
  await withWorkspace(async folder => {
    const appPath = join(folder, 'LocalMinutes.app'); cpSync(builtApp, appPath, { recursive: true });
    const value = { ...options(folder, appPath), outputDirectory: join(appPath, 'package-output') };
    await assert.rejects(() => createUnsignedIPA(value), /output|inside|input|bundle/i);
    assert.equal(existsSync(value.outputDirectory), false);
  });
});
