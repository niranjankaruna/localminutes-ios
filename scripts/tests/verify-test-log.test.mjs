import test from 'node:test';
import assert from 'node:assert/strict';
import { summarizeXCTestLog } from '../verify-test-log.mjs';

// Non-sensitive synthetic fixtures follow the XCTest format observed in run 39972652907.
function fixture({ failed = false, skipped = false, count = 2 } = {}) {
  const status = failed ? 'failed' : 'passed';
  const cases = Array.from({ length: count }, (_, i) =>
    `Test Case '-[HarnessTests.HarnessTests testExample${i}]' ${skipped && i === 0 ? 'skipped' : status} (0.001 seconds).`
  ).join('\n');
  return `${cases}\nTest Suite 'All tests' ${status} at 2026-10-23 14:49:16.370.\n\t Executed ${count} tests, with ${failed ? 3 : 0} failures (0 unexpected) in 0.002 (0.003) seconds\n`;
}

test('counts real XCTest cases and aggregate assertion failures', () => {
  assert.deepEqual(summarizeXCTestLog(fixture({ failed: true }), ['testExample0', 'testExample1']),
    { executed: 2, passed: 0, failed: 2, assertionFailures: 3, skipped: 0 });
});

test('accepts successful XCTest output and ignores the separate zero Swift Testing suite', () => {
  const log = fixture() + 'Test run with 0 tests in 0 suites passed after 0.001 seconds.\n';
  assert.deepEqual(summarizeXCTestLog(log, ['testExample1']),
    { executed: 2, passed: 2, failed: 0, assertionFailures: 0, skipped: 0 });
});

test('rejects zero executed XCTest cases', () => {
  assert.throws(() => summarizeXCTestLog(fixture({ count: 0 })), /zero|no.*cases/i);
});

test('rejects a missing mandatory named test', () => {
  assert.throws(() => summarizeXCTestLog(fixture(), ['testMissing']), /missing.*testMissing/i);
});

test('rejects skipped mandatory cases', () => {
  assert.throws(() => summarizeXCTestLog(fixture({ skipped: true })), /skip/i);
});

test('rejects a truncated run without the aggregate summary', () => {
  assert.throws(() => summarizeXCTestLog(fixture().split("Test Suite 'All tests'")[0]), /summary|incomplete/i);
});

test('rejects mismatched case and aggregate counts', () => {
  assert.throws(() => summarizeXCTestLog(fixture().replace('Executed 2 tests', 'Executed 3 tests')), /count|mismatch/i);
});

test('rejects contradictory success and failure counts', () => {
  assert.throws(() => summarizeXCTestLog(fixture({ failed: true }).replace('with 3 failures', 'with 0 failures')), /failure|contradict/i);
});
