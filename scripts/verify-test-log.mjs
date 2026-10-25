import { appendFileSync, readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

export function summarizeXCTestLog(log, requiredNames = []) {
  const cases = [...log.matchAll(/^Test Case '([^'\r\n]+)' (passed|failed|skipped)\b[^\r\n]*$/gm)];
  if (cases.length === 0) throw new Error('Zero executed XCTest cases');
  if (cases.some(c => c[2] === 'skipped')) throw new Error('Mandatory XCTest case skipped');
  const summaries = [...log.matchAll(/^Test Suite '(?:All|Selected) tests' (passed|failed) at[^\r\n]*\r?\n\s*Executed (\d+) tests?, with (\d+) failures? \(\d+ unexpected\)[^\r\n]*$/gm)];
  if (!summaries.length) throw new Error('Incomplete XCTest aggregate summary');
  let cursor = 0;
  let assertionFailures = 0;
  let lastBundle;
  for (const summary of summaries) {
    const [, status, count, failures] = summary;
    const declared = Number(count);
    const assertions = Number(failures);
    const start = cursor;
    while (cursor < cases.length && cases[cursor].index < summary.index) cursor += 1;
    const batch = cases.slice(start, cursor);
    if (batch.length) {
      if (declared !== batch.length) throw new Error('XCTest case count mismatch');
      const failed = batch.filter(c => c[2] === 'failed').length;
      if ((failed > 0) !== (assertions > 0) ||
          (status === 'failed') !== (failed > 0) || assertions < failed) {
        throw new Error('Contradictory XCTest failure summary');
      }
      assertionFailures += assertions;
      lastBundle = { status, declared, assertions };
    } else {
      // XCTest prints nested Selected/All roots for the same bundle. Check
      // repeated metrics instead of counting that bundle twice. A final outer
      // root may summarize all previously completed bundles.
      if ((status === 'failed') !== (assertions > 0)) {
        throw new Error('Contradictory XCTest failure summary');
      }
      const duplicate = lastBundle && lastBundle.status === status &&
        lastBundle.declared === declared && lastBundle.assertions === assertions;
      const combined = declared === cursor && assertions === assertionFailures &&
        (status === 'failed') === cases.slice(0, cursor).some(c => c[2] === 'failed');
      if (!duplicate && !combined) throw new Error('XCTest case count mismatch');
    }
  }
  if (cursor !== cases.length) throw new Error('Incomplete XCTest case count mismatch');
  for (const name of requiredNames) {
    const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    if (!cases.some(c => new RegExp(`\\b${escaped}\\b`).test(c[1]))) {
      throw new Error(`Missing mandatory test ${name}`);
    }
  }
  const failed = cases.filter(c => c[2] === 'failed').length;
  return { executed: cases.length, passed: cases.length - failed, failed, assertionFailures, skipped: 0 };
}

if (process.argv[1] && pathToFileURL(process.argv[1]).href === import.meta.url) {
  try {
    if (!process.argv[2]) throw new Error('A XCTest log path is required');
    const result = summarizeXCTestLog(readFileSync(process.argv[2], 'utf8'), process.argv.slice(3));
    console.log(JSON.stringify(result));
    if (process.env.GITHUB_STEP_SUMMARY) {
      appendFileSync(process.env.GITHUB_STEP_SUMMARY,
        `Source: ${process.env.GITHUB_SHA}\n\nXCTest: ${JSON.stringify(result)}\n`);
    }
    if (result.failed) process.exitCode = 1;
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
