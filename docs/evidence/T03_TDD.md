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
Pre-activation cancellation remains cancelPreparation. Expanded native RED is
required before implementing this distinction; no production behavior exists yet.

Expanded test-first source: `bc71753f82ad71a55eca3f4f171a3cf661ee3b94`.
Run [39975336692](https://github.com/niranjankaruna/localminutes-ios/actions/runs/39975336692)
completed 23 October 2026, 15:07:17 UTC: **19 XCTest cases executed, 4 passed,
15 failed, 43 assertion failures, 0 skipped**, exit 1. The new test executed
and observed nil rather than stopAndFlush, idle rather than stopping, and a
missing cleanup-pending flag. All code compiled; 8 reporting tests passed.
Both RED commits remain pushed and auditable before behavior implementation.

## GREEN — pending exact-source hosted execution

Implemented the smallest command/event actor after both RED observations:
serialized session ownership, idempotent commands, activation gating, startup
cancellation, acknowledgement-dependent completion, stale-session rejection,
and sanitized explicit interruption/failure outcomes. Adapter work runs outside
the actor. Real AVFoundation, ActivityKit, storage and inference are not integrated
in this slice, and adapter lifetime/cleanup contracts still need T05+ integration.

## Review and continuation

The harness branch history is retained as the parent of this single active task
branch. Main remains the initial documentation checkpoint until the verified
task history can be fast-forwarded. Core tests now run on task pushes only to
avoid a redundant metered run when an already-tested SHA is fast-forwarded to
main. Local merge policy: inspect the exact tested source, preserve RED commits,
fast-forward only after required checks pass; no server-side protection claimed.
The six-run limit remains shared across this invocation (2 used so far).

Tests assert observable state and the only commands a real adapter can execute,
not fake transcripts or model outputs. No native APIs, model or device claim.
Next: inspect actual RED before implementing transitions.
