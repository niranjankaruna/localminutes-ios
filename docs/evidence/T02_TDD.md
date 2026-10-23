# T02 harness TDD evidence

Task: T02. Requirements: R02. Initial harness bootstrap exception only.
Acceptance: hosted macOS discovers and executes the named XCTest assertions,
propagates failure, then passes after the deliberate demonstration is corrected
and the deterministic test clock is implemented. This is not app/ASR coverage.

## RED — observed 23 October 2026, 14:49 UTC

Files: `Package.swift`, `Tests/HarnessTests/HarnessTests.swift`,
`.github/workflows/core-tests.yml`.
Tests: `HarnessTests.testHarnessExecutesAnAssertion`,
`HarnessTests.testControlledClockAdvancesWithoutSleeping`.
Command: `swift test --enable-code-coverage --xunit-output .build/test-results.xml`.
Platform: actual macos-15-intel, macOS 15.7.9 / image 20260824.0482.1,
Xcode 26.2 / 17C52, Swift 6.2.3, x86_64, iOS/device-simulator SDK 26.2.
Minimal stub: test-only `ControlledClock.advance` does nothing.
Expected: deliberate assertion fails; clock remains 0 instead of 150 and 200.
Source SHA: `ef311b97ed475f9cecec61805f7020ca23a4382f` (pushed before implementation).
Run: [39972652907](https://github.com/niranjankaruna/localminutes-ios/actions/runs/39972652907).
XCTest executed **2 tests, 3 assertion failures, 0 unexpected failures**, exit 1.
Observed clock assertions: `0` differs from `150` and `200`; deliberate
`XCTAssertTrue` assertion failed. Both named cases actually executed after a
successful compile. The separate Swift Testing runner reported zero tests and
is not counted as evidence.

Reporting defect found in the same run: `.build/test-results.xml` did not exist
despite XCTest execution, so the independent discovery-report step also failed.
This secondary failure is not itself RED. Replace that check using a tested
parser of the actual XCTest log; preserve the original failing run.

Child T02.1: local reporting regression tests precede parser implementation.
`node --test scripts/tests/verify-test-log.test.mjs` must reject zero, skipped,
missing, truncated, inconsistent and contradictory results; minimal parser
stub exists only to obtain meaningful assertion failures.

## GREEN — NOT_RUN

No implementation or successful test execution is claimed. No app exists.
The workflow uses logs/summary only, no artifact upload or cache allocation.

## Review and continuation

Checkout is pinned, credentials persistence disabled, contents read-only,
branch concurrency bounded, timeout 10 minutes. No secrets, models or meeting
data are used. Every physical-device gate remains NOT_RUN.
Next: inspect the exact RED SHA/run before changing the clock or demonstration.
