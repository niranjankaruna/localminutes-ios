# T06.2.2 intent router: test-first draft

Status: pending, outside active build/test paths. These files have not been
compiled, executed, or proven RED. There is no router implementation, native
App Intent, real-model validation, or physical-device evidence here. The owner
slice must reach its own exact-source GREEN before this draft is activated.

## Small proposed contract

`RecordingIntentRouter` is MainActor-owned, retains the existing
`RecordingSessionOwner`, and exposes only `perform(_:) async`. It creates no
coordinator, capture runtime, Activity controller, or duplicate recording state.
The stub always returns `notImplemented`; its initializer only retains the owner.

Actions are `start(UUID)`, `stop(expectedSessionID: UUID?)`, and `toggle(UUID)`.
The UUID on start/toggle is the proposed recording epoch. A duplicate start
reports the existing owner's facts and cannot replace its session or resources.
A nil stop ID is an explicit generic Shortcuts stop. A Lock Screen control must
pass its Activity's session UUID; a mismatching expected ID returns `staleSession`
and cannot touch a replacement epoch.

Outcomes are values, not optimistic success messages:

| Outcome | Required fact |
| --- | --- |
| `starting` | The owner remains preparing; first-buffer readiness may still be absent. |
| `recording` | The real coordinator reports recording after actual audio-session, accepted-buffer, and Activity readiness. |
| `stopped` | This action stopped a recording, cleanup settled, and the matching completed manifest exists without a failure. |
| `idle` | No recording remains, no cleanup is pending, and the action has no failure to report. Cancelling preparation may return idle without a saved recording. |
| `cleanupPending` | The owner still owes resource cleanup. This takes priority over a generic failure/foreground message. |
| `blocked(failure)` | The owner's failure prevents success; model unavailable must use this outcome without attempting microphone/Activity startup. |
| `requiresForeground(failure)` | Microphone denied, Activity unavailable or capture unavailable needs attention in the app. Opening/unlocking does not guarantee a fix. |
| `staleSession` | A scoped stop targets a different epoch; no current resource is affected. |
| `notImplemented` | Test-first stub result only, never a shipping user response. |

Snapshot/failure mapping must remain truthful after the invoked owner operation
settles. `cleanupPending` outranks failure mapping; once cleanup settles, any
latched failure still prevents `stopped`. Microphone denied, Activity unavailable
and capture unavailable map to `requiresForeground`; other owner failures map
to `blocked`. Opening the app is not a promise that activation will succeed.
No router outcome establishes live ASR, a particular requested start UUID being
admitted, or a successful physical microphone session.

## Activation prerequisites and RED

1. Copy the no-op interface to `Recording/RecordingIntentRouter.swift` without
   adding behavior. The active Recording target already discovers that directory.
2. Append the entire test draft to
   `Tests/RecordingTests/RecordingSessionOwnerTests.swift`. Its extension must be
   in the same file to access the existing private harness/helpers. Do not add it
   as an independent test source or weaken the existing owner assertions.
3. Add a minimal no-op `public func stop(sessionID: UUID) async {}` interface
   inside `RecordingSessionOwner` before the hosted RED. No scoped-stop behavior
   belongs in that test-first step. The draft intentionally references this new
   interface; it will not compile before that explicit integration.
4. Extend only the existing test hardware boundary with an `activationFailures`
   counter. Its activateSession should throw OwnerTestError.hardwareFailure
   before setting sessionActive when that counter is positive. This enables the
   proposed unavailable-audio-session test, not a production substitute.
5. Commit/push the tests and minimal interfaces before production behavior;
   obtain meaningful hosted assertion RED and record the exact source/run and
   discovery counts, then implement dispatch,
   checked mapping, and the scoped stop guard. A compile error is not RED.
6. The real scoped-stop implementation must compare the expected UUID with the
   current owner epoch on MainActor and close/latch that exact epoch before any
   suspension. A router snapshot followed by unscoped `stop()` is insufficient.
   Reuse the existing shared cleanup attempt and explicit retry policy.

The draft adds eleven async XCTest methods to `RecordingSessionOwnerTests`. It
reuses the real coordinator, capture runtime, PCM queue/converter, CAF writer,
and Activity controller. Doubles remain at permission, audio hardware,
ActivityKit, and model-preparation boundaries. Generated non-sensitive PCM is
decoded from the actual saved CAF; no recognizer is mocked or claimed present.
The existing one-second bounded helpers and guarded fixture cleanup are reused.
This is a proposed test count, not executed evidence or a promised CI total.

## Duplicate toggle: bounded follow-up proposal

The eleven tests cover one toggle stopping an active recording and a subsequent,
legitimate toggle starting a new epoch. Owner concurrency/cancellation already
has its own regressions. Any debounce window or delivery cache must be bounded
and must prove that later legitimate toggles remain effective. An epoch UUID
alone cannot identify a duplicate delivery.

The current action UUID identifies a proposed epoch, not an OS delivery. Distinct
invocations must follow authoritative owner phase; two distinct concurrent
toggles are two user actions unless the platform supplies evidence otherwise.
Check how native App Intents can redeliver the same invocation and choose an explicit
delivery-identity boundary after checking the real SDK. Before implementing
deduplication, add a bounded regression that holds the first toggle's actual
Activity end, delivers the same identified request concurrently, and proves both
waiters share one stop/flush/end with no replacement capture. Then deliver a new
request identity after completion and prove a new epoch starts. Bound or expire
any delivery cache and test eviction; do not create an unbounded UUID collection.
No extra deduplication API or behavior is invented by this draft.

## Native follow-up and evidence limits

Native start/stop/toggle App Intents must route to one app-held owner/router;
the widget/Live Activity extension must not construct a second capture lifetime.
Use the actual `AudioRecordingIntent` and `LiveActivityIntent` SDK boundaries as
applicable, check their real target/conformance requirements, and test app-process
routing. These names are requirements for later integration, not SDK validation.
Availability-check the actual iOS 18 and iOS 26 foreground continuation/fallback
APIs before using them; an unavailable modern API needs a supported older-system
path. Never assume a background recording entitlement or locked cold-start from
protocol conformance alone.

Current primary declaration research is preserved in
[ADR0003](../../architecture/0003-live-activity-and-intents.md). Native adapters
still need actual SDK compilation and execution evidence after router RED.

The native adapter must surface foreground-required outcomes truthfully and
offer the app fallback. Action Button assignment, Lock Screen invocation,
extension inclusion/free signing, locked cold-start/continuation, two-hour live
transcription, and in-place renewal all remain separate pending device gates.
Production model preparation must continue rejecting `modelUnavailable` until
T09-T11 supply verified installed artifacts and the actual CPU streaming runtime.
Recording-only success does not satisfy local live transcription.
