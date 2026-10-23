// Minimal T04.1 interfaces. Production validation follows recorded RED.
export function validateDeviceBundles(bundleSet) { throw new Error('T04.1 not implemented'); }
export function validateArchiveEntries(entries) { throw new Error('T04.1 not implemented'); }
export function inspectNativeBundle(bundlePath, run) { throw new Error('T04.1 not implemented'); }
export async function sha256File(filePath) { return ''; }
export async function verifyFileSHA256(filePath, expected) { return false; }
