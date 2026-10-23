# T03 recording domain TDD evidence

Task: T03. Requirements: R02, R04. Acceptance: one authoritative session,
single preparation/activation/flush commands under concurrency, cancellation,
stale-event rejection, truthful readiness, explicit interruption/failure states.

## RED — initial and expanded sets observed

File: `Tests/CoreTests/RecordingCoordinatorTests.swift`, initially 16 named XCTest cases.
Minimal interface: domain types and `RecordingCoordinator` returning idle/no
commands, with no production transition behavior. Preparation, audio activation,
first-buffer and Live Activity events are explicit adapter boundaries; this
slice does not yet execute those adapters or capture microphone audio.

Command: `swift test --enable-code-coverage` on hosted macos-15-intel / Xcode 26.2.
Expected: start remains idle/no preparation; concurrent starts emit 0 rather
than 1; ready state never enters recording; stopping and failures remain idle.
Initial source: `16995e0b34fda8b57e36a95d1ce58c28b63aa735`, pushed before behavior.
Run [39974793184](https://github.com/niranjankaruna/localminutes-ios/actions/runs/39974793184)
completed 23 October 2026, 15:04:12 UTC: compiled successfully; **18 XCTest cases
executed, 4 passed, 14 failed, 39 assertion failures, 0 skipped**, exit 1.
The domain suite executed 16 cases; prior harness cases passed. Concurrent-start
assertion observed 0 preparation commands rather than 1; state remained idle.
Reporting regressions also passed 8/8. Both XCTest and result verification
propagated the failure; this is genuine RED, not a compile/tool failure.

Independent review identified an activation-in-flight cancellation case missing
from that source. Added `testStopDuringActivationFlushesOnceAndRejectsLateReadiness`
before implementation: after activation is emitted, stop must emit exactly one
stopAndFlush, ignore late callbacks, and block a replacement until cleanup.
Pre-activation cancellation remains cancelPreparation. Expanded native RED
was required before implementing this distinction; no transition behavior existed at that RED revision.

Expanded test-first source: `bc71753f82ad71a55eca3f4f171a3cf661ee3b94`.
Run [39975336692](https://github.com/niranjankaruna/localminutes-ios/actions/runs/39975336692)
completed 23 October 2026, 15:07:17 UTC: **19 XCTest cases executed, 4 passed,
15 failed, 43 assertion failures, 0 skipped**, exit 1. The new test executed
and observed nil rather than stopAndFlush, idle rather than stopping, and a
missing cleanup-pending flag. All code compiled; 8 reporting tests passed.
Both RED commits remain pushed and auditable before behavior implementation.

## GREEN — initial domain set passed; review regression pending

Implemented the smallest command/event actor after both RED observations:
serialized session ownership, idempotent commands, activation gating, startup
cancellation, acknowledgement-dependent completion, stale-session rejection,
and sanitized explicit interruption/failure outcomes. Adapter work runs outside
the actor. Real AVFoundation, ActivityKit, storage and inference are not integrated
in this slice, and adapter lifetime/cleanup contracts still need T05+ integration.

Implementation source: `9c39e5f6a44904dc5746fc31c6a1c5e3c9373fc2`.
Run [39975791505](https://github.com/niranjankaruna/localminutes-ios/actions/runs/39975791505)
completed 23 October 2026, 15:10:31 UTC, **success**. XCTest: 19 executed
(17 domain + 2 harness), 19 passed, 0 failures/skips; Node reporting tests: 8/8
passed. Command: `swift test --enable-code-coverage`; strict log verification
also passed on the exact source. This does not close T03 because review found
the additional interruption race below.

Review of the actual implementation found a separate interruption race during
activation: interrupt is ignored while phase is preparing, allowing a later
readiness event to publish recording. Added
`testInterruptionDuringActivationRejectsLateRecordingSuccess` before fixing it.
This regression requires a separate native RED; it prevents closing T03 even
if the existing 19-case implementation run passes. The fix is not implemented.

## T03.1 regression RED — verified

Test-first source: `33cd7c6a88195998b6a5f15bb62cc9c6c415045a`, committed and
pushed before any interruption fix. Run
[39976742123](https://github.com/niranjankaruna/localminutes-ios/actions/runs/39976742123)
completed 23 October 2026, 15:16:59 UTC, **failure**. XCTest executed 20 cases:
**19 passed, 1 failed, 6 assertion failures, 0 skipped**. The domain suite ran
18 cases; harness/reporting regressions remained green (2 XCTest and 8 Node).
Compilation and discovery succeeded; both test execution and verification exited 1.

`testInterruptionDuringActivationRejectsLateRecordingSuccess` observed:

- nil rather than stopAndFlush for the interrupted activation;
- recording rather than interrupted after late readiness;
- cleanupPending false and firstBufferAccepted true;
- recording still present after cleanup acknowledgement;
- replacement preparation missing because the interrupted capture still owns state.

This proves the actual missing behavior, rather than a toolchain failure. No
fix, GREEN or successful native adapter result is claimed for T03.1. The failing
CI result is intentionally retained. All six permitted invocation runs are used;
the next invocation must start with this fix and exact-source GREEN.

## Review and continuation

The harness branch history is retained as the parent of this single active task
branch. Main remains the initial documentation checkpoint until the verified
task history can be fast-forwarded. Core tests now run on task pushes only to
avoid a redundant metered run when an already-tested SHA is fast-forwarded to
main. Local merge policy: inspect the exact tested source, preserve RED commits,
fast-forward only after required checks pass; no server-side protection claimed.
The six-run limit is shared across this invocation; all six runs are now used.

Tests assert observable state and the only commands a real adapter can execute,
not fake transcripts or model outputs. No native APIs, model or device claim.
Next invocation: fix T03.1 using its recorded interruption-during-activation RED,
verify all 20 XCTest and 8 reporting tests GREEN at the exact new source SHA,
review, then close T03 and proceed to T04.

## T03.1 continuation implementation — hosted GREEN pending

23 October 2026 continuation: reread the contract and actual worktree; verified
the prior RED run remains completed/failing at its recorded source and no code
changed between that test-first source and the documentation checkpoint.
The previous goal turn is classified as progress (repository, code and real
CI evidence changed), not a repeated blocker or an unverified wait.

After recorded RED, changed only the interruption eligibility guard: a matching
session with activation issued may enter interrupted before all readiness
acknowledgements arrive. It shares the existing single cleanup command and
stale-event rejection path. No test was removed, skipped or weakened.
Actual new-source GREEN is pending, not inferred from inspection.
