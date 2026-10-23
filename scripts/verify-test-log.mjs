import { appendFileSync, readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

export function summarizeXCTestLog(log, requiredNames = []) {
  const cases = [...log.matchAll(/^Test Case '([^'\r\n]+)' (passed|failed|skipped)\b[^\r\n]*$/gm)];
  if (cases.length === 0) throw new Error('Zero executed XCTest cases');
  if (cases.some(c => c[2] === 'skipped')) throw new Error('Mandatory XCTest case skipped');
  const summaries = [...log.matchAll(/^Test Suite 'All tests' (passed|failed) at[^\r\n]*\r?\n\s*Executed (\d+) tests?, with (\d+) failures? \(\d+ unexpected\)[^\r\n]*$/gm)];
  if (!summaries.length) throw new Error('Incomplete XCTest aggregate summary');
  const [, status, count, failures] = summaries.at(-1);
  if (Number(count) !== cases.length) throw new Error('XCTest case count mismatch');
  for (const name of requiredNames) {
    const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    if (!cases.some(c => new RegExp(`\\b${escaped}\\b`).test(c[1]))) {
      throw new Error(`Missing mandatory test ${name}`);
    }
  }
  const failed = cases.filter(c => c[2] === 'failed').length;
  const assertionFailures = Number(failures);
  if ((failed > 0) !== (assertionFailures > 0) ||
      (status === 'failed') !== (failed > 0) || assertionFailures < failed) {
    throw new Error('Contradictory XCTest failure summary');
  }
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
