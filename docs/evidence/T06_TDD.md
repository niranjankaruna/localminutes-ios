# T06 TDD evidence

Task/child ID: T06.1
Requirement IDs: R04,R06
Behavior: app-owned Live Activity resources; RecordingCoordinator retains
recording authority. Actual SDK backend is mandatory after behavioral RED.

Acceptance: disabled/failed/pending/ended/dismissed requests never qualify
initial readiness; duplicate active ID reuses one handle, competing/stale
commands cannot replace it; stale content remains owned; unexpected terminal
loss is emitted once; retired observers cannot affect same-ID replacement;
end settles previously admitted updates and the actual async end before a
single cleanup acknowledgement. End does not assert recording completion.

## Test-first activation — RED pending

Test file: Tests/CoreTests/LiveActivityControllerTests.swift, nine cases.
Minimal no-op interface: Core/LiveActivityController.swift. No controller
behavior or ActivityKit adapter is implemented yet. Expected full count87,
not compiled/executed. Actor-isolated test methods are async, consistent with
the existing native harness. The original uncompiled drafts remain archived.

Required command/platform: swift test --enable-code-coverage, hosted
macos-15-intel/Xcode26.2. Source/CI/assertion result remains unverified until
run5. The test-first commit will be pushed before any behavior is written.
Compiler errors or zero tests will not count as RED.

Only ActivityKit backend/handle calls are doubled. Native SDK request,
observation, update/end and deployment availability must also compile in the
device and simulator app builds during GREEN. Actual OS authorization,
presentation, signing, Action Button and Lock Screen remain device gates.
No model inference is substituted or validated by these tests.

## GREEN — pending

No implementation, run or result yet. Required regressions: all87 XCTest,
59 scripts,53 repeated ownership/runtime/activity cases under Thread Sanitizer,
actual device/simulator app+extension builds and15 native product/package
tests. Counts are expectations, never observed passes.

## Review and continuation

Primary API research: docs/architecture/0003-live-activity-and-intents.md.
Privacy: status-only Lock Screen content, no transcript or meeting data;
no credentials, pushes, cloud inference or uploads. SDK backend implementation
requires prior meaningful RED. T06.2 subsequently composes the app owner,
capture runtime, activity resources and recording start/stop/toggle intents.
No UI, intents, device evidence or full baseline completion is claimed here.
