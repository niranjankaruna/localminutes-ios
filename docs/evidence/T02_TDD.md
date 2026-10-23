# T02 harness TDD evidence

Task: T02. Requirements: R02. Initial harness bootstrap exception only.
Acceptance: hosted macOS discovers and executes the named XCTest assertions,
propagates failure, then passes after the deliberate demonstration is corrected
and the deterministic test clock is implemented. This is not app/ASR coverage.

## RED — pending hosted execution

Files: `Package.swift`, `Tests/HarnessTests/HarnessTests.swift`,
`.github/workflows/core-tests.yml`.
Tests: `HarnessTests.testHarnessExecutesAnAssertion`,
`HarnessTests.testControlledClockAdvancesWithoutSleeping`.
Command: `swift test --enable-code-coverage --xunit-output .build/test-results.xml`.
Platform: selected macos-15-intel / Xcode 26.2; actual execution not yet observed.
Minimal stub: test-only `ControlledClock.advance` does nothing.
Expected: deliberate assertion fails; clock remains 0 instead of 150 and 200.
Source SHA, run URL, executed count and actual assertion: pending, not RED yet.

## GREEN — NOT_RUN

No implementation or successful test execution is claimed. No app exists.
The workflow uses logs/summary only, no artifact upload or cache allocation.

## Review and continuation

Checkout is pinned, credentials persistence disabled, contents read-only,
branch concurrency bounded, timeout 10 minutes. No secrets, models or meeting
data are used. Every physical-device gate remains NOT_RUN.
Next: inspect the exact RED SHA/run before changing the clock or demonstration.
