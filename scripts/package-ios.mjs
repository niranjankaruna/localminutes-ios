import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { cpSync, existsSync, lstatSync, mkdirSync, mkdtempSync, readdirSync, realpathSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { basename, dirname, isAbsolute, join, relative, resolve, sep } from 'node:path';
import { inspectNativeBundle, sha256File, validateArchiveEntries, validateDeviceBundles } from './ios-artifacts.mjs';

function run(tool, args, options = {}) {
  return execFileSync(tool, args, { encoding: 'utf8', timeout: 30_000, maxBuffer: 8 * 1024 * 1024, ...options });
}

function isInside(parent, path) {
  const child = relative(parent, path);
  return child !== '' && !isAbsolute(child) && child !== '..' && !child.startsWith(`..${sep}`);
}

export function auditInputTree(appPath) {
  const entries = [];
  function visit(path) {
    const info = lstatSync(path);
    assert.ok(!info.isSymbolicLink(), 'Bundle symlinks are forbidden');
    assert.ok(info.isDirectory() || info.isFile(), 'Bundle contains a forbidden special file');
    const name = basename(path);
    assert.ok(name !== '_CodeSignature' && !/\.mobileprovision$/i.test(name), 'Signing or provisioning material is forbidden');
    assert.ok(!/^\.env(?:\.|$)/i.test(name)
      && !['.git', '.agent-local', 'private-data', 'secrets', 'transcripts', 'recordings', 'device-evidence', 'diagnostics-raw'].includes(name.toLowerCase())
      && !/\.(?:onnx|gguf|bin|safetensors|pt|pth|caf|wav|m4a|(?:sqlite(?:3)?|db)(?:-shm|-wal)?|p12|p8|pem|key)$/i.test(name),
    'Private data, model weights or local secrets are forbidden in the IPA');
    const suffix = relative(appPath, path).split(sep).join('/');
    entries.push(`Payload/LocalMinutes.app${suffix ? `/${suffix}` : ''}${info.isDirectory() ? '/' : ''}`);
    if (info.isDirectory()) for (const child of readdirSync(path).sort()) visit(join(path, child));
  }
  visit(appPath);
  validateArchiveEntries(entries);
}

function requireUnsigned(bundlePath) {
  const result = spawnSync('/usr/bin/codesign', ['-d', '--verbose=2', bundlePath], {
    encoding: 'utf8', timeout: 10_000, maxBuffer: 1024 * 1024
  });
  if (result.error) throw result.error;
  assert.ok(result.status === 1 && result.stderr.includes('code object is not signed at all'),
    'Signing state is not verified unsigned');
}

function inspectArchive(file) {
  // Never extract untrusted paths. Validate central-directory types and CRCs.
  return JSON.parse(run('/usr/bin/python3', ['-c', `
import json, stat, sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as archive:
    entries = archive.infolist()
    assert all(stat.S_IFMT(i.external_attr >> 16) in (stat.S_IFREG, stat.S_IFDIR) for i in entries), 'Unsafe ZIP entry type'
    assert all(not (i.flag_bits & 1) for i in entries), 'Encrypted ZIP entry'
    assert archive.testzip() is None, 'ZIP CRC failure'
    print(json.dumps([i.filename for i in entries]))
`, file]));
}

function removeOwnedDirectory(path, workspace) {
  if (!existsSync(path)) return;
  const absolute = resolve(path);
  assert.ok(isInside(workspace, absolute), 'Cleanup target escaped the workspace');
  assert.ok(!lstatSync(absolute).isSymbolicLink(), 'Cleanup target became a symlink');
  assert.ok(isInside(workspace, realpathSync(absolute)), 'Resolved cleanup target escaped the workspace');
  rmSync(absolute, { recursive: true, force: true });
}

// Portable filesystem boundary, exercised on real local files before native tools.
export function validatePackagePaths({ appPath, outputDirectory }) {
  const workspace = realpathSync(process.cwd());
  const input = resolve(appPath);
  const output = resolve(outputDirectory);
  assert.ok(!existsSync(output), 'Output directory already exists');
  assert.ok(isInside(workspace, input) && isInside(workspace, output), 'Input and output must stay inside the workspace');
  assert.ok(!isInside(input, output), 'Output directory must be outside the input bundle');
  assert.ok(!lstatSync(input).isSymbolicLink(), 'Root app bundle must not be a symlink');
  assert.ok(lstatSync(input).isDirectory() && basename(input) === 'LocalMinutes.app', 'Expected the LocalMinutes.app input bundle');
  assert.ok(isInside(workspace, realpathSync(input)), 'Resolved input escaped the workspace');
  const outputParent = realpathSync(dirname(output));
  assert.ok(outputParent === workspace || isInside(workspace, outputParent), 'Resolved output parent escaped the workspace');
  const canonicalInput = realpathSync(input);
  const canonicalOutput = join(outputParent, basename(output));
  assert.ok(canonicalOutput !== canonicalInput && !isInside(canonicalInput, canonicalOutput),
    'Output directory must be outside the resolved input bundle');
  return { workspace, input, output, outputParent };
}

export async function createUnsignedIPA({ appPath, outputDirectory, sourceCommit }) {
  assert.equal(process.platform, 'darwin', 'Native device packaging requires macOS');
  const { workspace, input, output, outputParent } = validatePackagePaths({ appPath, outputDirectory });
  assert.match(sourceCommit, /^[0-9a-f]{40}$/, 'Invalid source commit');
  assert.equal(run('git', ['rev-parse', 'HEAD']).trim(), sourceCommit, 'Source commit does not match the checked-out source');

  auditInputTree(input);
  const extensionPath = join(input, 'PlugIns/LocalMinutesLiveActivity.appex');
  const native = { app: inspectNativeBundle(input), extension: inspectNativeBundle(extensionPath) };
  const bundles = validateDeviceBundles(native);
  for (const bundle of [native.app, native.extension]) {
    assert.equal(bundle.info.LocalMinutesSourceCommit, sourceCommit, 'Bundle source commit stamp does not match');
    assert.equal(bundle.info.CFBundleShortVersionString, native.app.info.CFBundleShortVersionString, 'Bundle app versions must match');
    assert.equal(bundle.info.CFBundleVersion, native.app.info.CFBundleVersion, 'Bundle build versions must match');
  }
  requireUnsigned(input);
  requireUnsigned(extensionPath);
  const appVersion = native.app.info.CFBundleShortVersionString;
  assert.match(appVersion, /^\d+\.\d+(?:\.\d+)?$/, 'Invalid app version for archive name');
  const toolchain = {
    xcode: run('/usr/bin/xcodebuild', ['-version']).trim(),
    iosSDK: run('/usr/bin/xcrun', ['--sdk', 'iphoneos', '--show-sdk-version']).trim(),
    runnerImage: process.env.ImageVersion ?? null
  };

  let stage;
  let outputCreated = false;
  try {
    stage = mkdtempSync(join(outputParent, '.localminutes-package-'));
    const payload = join(stage, 'Payload'); mkdirSync(payload);
    const stagedApp = join(payload, 'LocalMinutes.app');
    cpSync(input, stagedApp, { recursive: true, force: false, errorOnExist: true, dereference: false });
    auditInputTree(stagedApp);
    mkdirSync(output); outputCreated = true;
    const artifact = `LocalMinutes-${appVersion}-${sourceCommit}-unsigned.ipa`;
    const ipaPath = join(output, artifact);
    run('/usr/bin/zip', ['-q', '-r', '-X', ipaPath, 'Payload'], { cwd: stage });
    validateArchiveEntries(inspectArchive(ipaPath));
    const hash = await sha256File(ipaPath);
    const checksumPath = join(output, `${artifact}.sha256`);
    const manifestPath = join(output, 'build-manifest.json');
    const manifest = {
      schemaVersion: 1, sourceCommit, appVersion, buildNumber: native.app.info.CFBundleVersion,
      artifact, sha256: hash, sizeBytes: statSync(ipaPath).size, signing: 'unsigned',
      deviceValidation: 'NOT_RUN', toolchain, bundles,
      createdAt: new Date().toISOString()
    };
    writeFileSync(checksumPath, `${hash}  ${artifact}\n`, { flag: 'wx' });
    writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`, { flag: 'wx' });
    return { ipaPath, checksumPath, manifestPath };
  } catch (error) {
    if (outputCreated) removeOwnedDirectory(output, workspace);
    throw error;
  } finally {
    if (stage) removeOwnedDirectory(stage, workspace);
  }
}
