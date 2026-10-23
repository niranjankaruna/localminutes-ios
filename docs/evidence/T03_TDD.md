# T03 recording domain TDD evidence

Task: T03. Requirements: R02, R04. Acceptance: one authoritative session,
single preparation/activation/flush commands under concurrency, cancellation,
stale-event rejection, truthful readiness, explicit interruption/failure states.

## RED — awaiting hosted execution

File: `Tests/CoreTests/RecordingCoordinatorTests.swift`, 16 named XCTest cases.
Minimal interface: domain types and `RecordingCoordinator` returning idle/no
commands, with no production transition behavior. Preparation, audio activation,
first-buffer and Live Activity events are explicit adapter boundaries; this
slice does not yet execute those adapters or capture microphone audio.

Command: `swift test --enable-code-coverage` on hosted macos-15-intel / Xcode 26.2.
Expected: start remains idle/no preparation; concurrent starts emit 0 rather
than 1; ready state never enters recording; stopping and failures remain idle.
Actual source SHA, executed counts and assertion results: pending.

## GREEN — NOT_RUN

No transition behavior has been implemented before native RED.

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
