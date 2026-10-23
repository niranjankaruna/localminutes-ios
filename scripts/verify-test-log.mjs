// Minimal interface stub for T02 reporting regression tests. Not implemented yet.
export function summarizeXCTestLog(log, requiredNames = []) {
  return { executed: 0, passed: 0, failed: 0, assertionFailures: 0, skipped: 0 };
}
