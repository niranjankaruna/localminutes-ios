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

// The filtered Thread Sanitizer execution in run39994364160 produced a
// Selected tests root. Inner suite summaries are not aggregate substitutes.
function selectedFixture(options = {}) {
  return fixture(options).replace("Test Suite 'All tests'", "Test Suite 'Selected tests'");
}

test('accepts the actual Selected tests root used by filtered XCTest', () => {
  const log = selectedFixture() + 'Test run with 0 tests in 0 suites passed after 0.007 seconds.\n';
  assert.deepEqual(summarizeXCTestLog(log, ['testExample0', 'testExample1']),
    { executed: 2, passed: 2, failed: 0, assertionFailures: 0, skipped: 0 });
});

test('counts failures in a Selected tests root without treating it as success', () => {
  assert.deepEqual(summarizeXCTestLog(selectedFixture({ failed: true }), ['testExample1']),
    { executed: 2, passed: 0, failed: 2, assertionFailures: 3, skipped: 0 });
});

test('selected tests still require matching aggregate and case counts', () => {
  assert.throws(() => summarizeXCTestLog(selectedFixture().replace('Executed 2 tests', 'Executed 3 tests')),
    /count|mismatch/i);
});

test('selected tests still require every mandatory test name', () => {
  assert.throws(() => summarizeXCTestLog(selectedFixture(), ['testMissing']), /missing.*testMissing/i);
});

test('selected tests reject contradictory success and failure status', () => {
  assert.throws(() => summarizeXCTestLog(selectedFixture({ failed: true }).replace('with 3 failures', 'with 0 failures')),
    /failure|contradict/i);
});

test('selected tests reject mandatory skips', () => {
  assert.throws(() => summarizeXCTestLog(selectedFixture({ skipped: true })), /skip/i);
});

test('selected tests do not accept an inner suite in place of a truncated root', () => {
  const innerOnly = selectedFixture().replace("Test Suite 'Selected tests'", "Test Suite 'OwnedPCMQueueTests'");
  assert.throws(() => summarizeXCTestLog(innerOnly), /summary|incomplete/i);
});

test('selected tests reject zero executed cases', () => {
  assert.throws(() => summarizeXCTestLog(selectedFixture({ count: 0 })), /zero|no.*cases/i);
});

// The app-unit and UI bundles in native run 40213241251 each print their own
// Selected/All roots. Count every bundle and preserve an earlier bundle failure.
function uiFixture(options = {}) {
  return selectedFixture(options).replaceAll('HarnessTests.HarnessTests', 'ProductUITests.ModelScreenTests')
    .replaceAll('testExample', 'testProductUI');
}

test('aggregates the independently completed app and UI bundles', () => {
  assert.deepEqual(summarizeXCTestLog(fixture() + uiFixture(), ['testExample1', 'testProductUI1']),
    { executed: 4, passed: 4, failed: 0, assertionFailures: 0, skipped: 0 });
});

test('an earlier failed app bundle cannot be hidden by a passing UI bundle', () => {
  assert.deepEqual(summarizeXCTestLog(fixture({ failed: true }) + uiFixture(), ['testProductUI1']),
    { executed: 4, passed: 2, failed: 2, assertionFailures: 3, skipped: 0 });
});

test('nested Selected and All roots do not double-count either native bundle', () => {
  const duplicate = fixture().slice(fixture().indexOf("Test Suite 'All tests'"));
  const log = selectedFixture() + duplicate + uiFixture() + duplicate;
  assert.deepEqual(summarizeXCTestLog(log, ['testExample1', 'testProductUI1']),
    { executed: 4, passed: 4, failed: 0, assertionFailures: 0, skipped: 0 });
});

test('contradictory duplicate root status remains a verification failure', () => {
  const wrong = fixture().slice(fixture().indexOf("Test Suite 'All tests'"))
    .replace("'All tests' passed", "'All tests' failed");
  assert.throws(() => summarizeXCTestLog(fixture() + wrong + fixture().slice(fixture().indexOf("Test Suite 'All tests'"))),
    /contradict|failure/i);
});

test('a truncated later UI bundle cannot reuse the earlier completed app root', () => {
  const truncated = uiFixture().split("Test Suite 'Selected tests'")[0];
  assert.throws(() => summarizeXCTestLog(fixture() + truncated), /count|mismatch|incomplete/i);
});
