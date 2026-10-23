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

Implementation is present after the recorded RED; no implementation GREEN yet. Required regressions: all87 XCTest,
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

Test-first source b95de19545db9619b770bdc5fc75aaffb2c28e45 pushed on task/t06-activity. Run40002877757 is active; no controller/SDK behavior exists and no RED result is claimed yet.


## T06.1 RED — verified before behavior

Source **b95de19545db9619b770bdc5fc75aaffb2c28e45**, [run40002877757](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40002877757), completed23 October2026 about18:26 UTC. Command swift test --enable-code-coverage, hosted macos-15-intel/Xcode26.2. **87 executed,78 passed,9 failed,47 assertion failures,0 skipped**. Every new activity case fails; all prior cases pass. No backend request or readiness/unavailable event occurs; duplicate start incorrectly returns unavailable, no observer exists, admitted updates/end never run, and end acknowledgement is absent. Compile/discovery and assertions worked. Test-first commit was pushed before run. This is meaningful RED, not a tool or zero-test failure. Node/TSAN/native were not run after Swift RED. No controller/backend behavior was written before this evidence.

T06.1 implementation after recorded RED: MainActor controller owns actual backend handles, checks real active state after observer installation, serializes admitted updates and async end, coalesces duplicate end requests, and ignores retired ownership identities. The iOS-only backend forwards actual ActivityAuthorizationInfo/request/update/end and observes activityStateUpdates in a cancellable Task. No framework concurrency suppression, push server, private content, model substitution, UI or intent behavior is introduced. All nine tests remain unchanged. Native SDK compilation and actual OS/phone effects are pending.

Independent read-only review of controller and actual backend found no blocking contract, ownership, callback-retirement or update/end-order defect. No tests changed. Native Swift6 compilation remains authoritative for ActivityKit isolation and observation-task deinit. Final invocation run6 follows; no seventh run permitted.


## Unit/sanitizer GREEN; exact-source native build FAILED

Implementation **e2876e830c8f54c605875e0808dd5d0cb6329e8e**, [run40004059233](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40004059233), completed23 October2026 at18:37 UTC. Actual **87 XCTest,59 Node and53 repeated XCTest under Thread Sanitizer passed,0 failures/skips**. All nine RED contracts are unchanged. Overall CI FAILED during device Release compilation: App/IOSLiveActivityBackend.swift67 and71 send MainActor-stored self.activity to nonisolated SDK async update/end. Swift6 reports data-race risk. Device/simulator/native product/package GREEN is not established;0 native checks and no new IPA at this SHA. This compiler error is not behavioral RED. Last full native GREEN remainsc12bd9c/run40001047762.

No @preconcurrency, unchecked Sendable conformance, disabled concurrency check, skipped test or retry is used to hide the error. Primary Apple Activity metadata lists Identifiable and no Sendable conformance. A safe first compile repair is being diagnosed for local save only. Six of six invocation runs are terminal; no seventh dispatch. T06.1 stays IN_PROGRESS, and T06.2 follows only after exact-source full native GREEN.


## T06.1.1 repair preparation — not applied or compiled

Concrete candidate docs/drafts/T06.1/ActivityKitOperations.swift.pending uses only immutable ID/status arguments, exact SDK lookup and local content/SDK receiver across await. It explicitly returns notFound without claiming an SDK end. The current Void handle API cannot discard that outcome safely; docs/drafts/T06.1/NATIVE_REPAIR.md defines the next regression RED before integration. No active source was changed after run6, no native repair attempt was validated and no new result is inferred. T06.1 remains IN_PROGRESS. Final checkpoint holds all87+59+53 passing execution evidence and the exact iOS compiler failure; last full native GREEN is c12bd9c.

## T06.1.1 checked-outcome regression — RED pending

Requirements R02,R04,R06. Four new tests in LiveActivityControllerTests cover
missing exact SDK lookup returning notFound: no cleanup acknowledgement,
observable failure and matching-ID retry; duplicate failed ends coalesce once;
missing update revokes readiness/loss once; already-queued content cannot
reuse the missing resource. Existing nine contracts keep their assertions.
Only the ActivityKit boundary is doubled. Protocol outcome/event declarations
and conforming return values are interface-only; controller explicitly ignores
the result as before, so no new policy/SDK isolation repair is implemented.

Command swift test --enable-code-coverage, hostedmacos-15-intel/Xcode26.2.
Expected91 discovered XCTest; no result or native GREEN claimed before run.
Source/CI/assertions will be recorded after actual RED. The prior compile
failure remains visible and is not behavioral RED. Candidate SDK ID-only
helper stays outside active sources until new regression RED is proven.
Test-first source b873d6b081e949b80499217771c705d4445a5a67 pushed and remote verified. Run40007944579 in progress; no RED result yet. Bounded read-only reviewer confirmed old9assertions unchanged and new Core interface logically compileable; overlapping retry finalizer identity must be reviewed, since new retry tests join old callers first. Actual SDK lookup semantics remain a native/device boundary, not established by doubled outcomes.

## T06.1.1 RED — verified before repair

Test-first source **b873d6b081e949b80499217771c705d4445a5a67**,
[run40007944579](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40007944579),
23October2026 at19:02:38UTC. Hostedmacos-15-intel/Xcode26.2 command
swift test --enable-code-coverage. **91 executed,87 passed,4 failed,
20 assertion failures,0 skipped**. All four new cases fail; old87 pass.
Missing end wrongly clears ownership/emits ended, failure event is absent,
retry cannot reach original handle; missing update leaves readiness true and
queued update reuses it. Compiler/discovery and assertions worked. Node,
TSAN and native job did not run after Swift RED. Full ignored log archived
locally at.agent-local/T06.1.1-red.log. No policy/SDK isolation behavior was
implemented before this result; test-first commit and remote HEAD verified.

Repair approach: single finalizer inside the shared async end task, so duplicate
waiters never mutate a later retry; sticky end request closes start/update
admission across failure; explicit notFound preserves ownership/observer and
emits failure. Missing update revokes resource readiness and reports loss once,
which requires app-owned recording cleanup. SDK helper receives only checked
Sendable immutable ID/status, obtains exact matching SDK reference locally,
awaits real update/end and returns explicit outcome. Native compilation and
actual phone semantics remain pending. First compile-repair attempt follows.
Pre-GREEN independent read-only review passed the real diff: state revoked before external callback; end finalizes only inside its coalesced task, duplicate waiters cannot clear retry; sticky cleanup and exact-ID SDK lookup preserved. Tests unchanged since RED. Swift6 native compilation remains authoritative.

## T06.1.1 GREEN — exact-source native repair

Implementation **b6f4bdf0231d72d279ae690c5ce20936b8225459**,
[run40008712625](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40008712625),
23October2026 about19:13UTC, overall success. Actual **91XCTest,59Node,
57 repeatedXCTest under ThreadSanitizer,2nativeproduct+13packaging checks**
passed,0failures/skips/races. Existing87 and four new RED tests unchanged.
Command swift test --enable-code-coverage; swift test --sanitize=thread with
queue/admission/runtime/activity filter; node --test scripts/tests/*.test.mjs;
actual xcodebuild Release generic iOS and Debug generic iOSSimulator; native
product/package tests. Hostedmacos-15-intel/Xcode26.2. First native repair
attempt succeeded without unsafe isolation conformance or disabled checking.

Actual app+extension compile with the real ActivityKit SDK backend, stable IDs,
arm64device and x86_64/arm64simulator products. Ephemeral unsigned IPA156,390bytes,
SHA256e8bb24694328c04a8ba5d2bfa89eebdf592ca729f12431bfa562ab8c40df644c,
created19:12:55.896UTC. Not uploaded, retained, signed, installed or delivered;
candidateArtifact remains null. Full ignored log.agent-local/T06.1.1-b6f4-validation.log.

Review passed the real diff and unchanged RED tests. Only SDK calls are doubled
in lifecycle tests; actual ActivityKit calls compile but OS presentation/lookup
semantics are not exercised on a phone. T06.1/T06.1.1CODE_COMPLETE_PENDING_DEVICE
within resource/repair scope. App composition/intents, models, UI and all physical
gates remain unfinished. No inference, LockScreen, ActionButton/endurance or
renewal claim. NextT06.2.1 real app-owned command/event composition RED.

## T06.2.1 owner composition — RED pending

RequirementsR02,R04,R06,R07. Ten new RecordingSessionOwnerTests exercise concrete
coordinator/capture/activity composition, actual owned PCM/converter/16-bitCAF
and manifest. Only permission/hardware/ActivityKit/model-preparation boundaries
are doubled. No inference result is supplied by a ready preparation double.
Tests cover missing-model rejection, late preparation after stop, duplicate
commands, all-three readiness, disabled/inactive Activity, denied microphone,
audio-flush-before-heldActivityend, failed deactivation/end retry, authoritative
toggle and retired callback isolation. Minimal RecordingSessionOwner interface
has no behavior and delegates snapshot to an unmodified real coordinator.

Direct Core test dependency and mandatory discovery names added; TSAN now also
selects owner tests. Expected101XCTest and67sanitizer repeats after GREEN, not
actual results yet. Command swift test --enable-code-coverage on hostedmacOS.
No owner behavior before meaningful RED. Production live start remains gated
until real installed CPU ASR is wired; no recording-only/inference substitution.

## T06.2.1 RED — verified before owner behavior

Test-first **fdfab8905e479c7e1343f394c85ceecc9b52b1e0**,
[run40010164221](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40010164221),
23October2026 at19:19:25UTC. Hostedmacos-15-intel/Xcode26.2,
swift test --enable-code-coverage. **101executed,91passed,10failed,
38assertion failures,0skipped**. All ten new owner cases fail; old91pass.
Observed no preflight/resource ownership, idle instead of failed/preparing,
missing real tap and media, cancellation not entering stopping, missing cleanup
barrier/retry. Compilation/discovery/assertions succeeded; meaningful RED.
Node/TSAN/native not run after Swift RED. Full ignored local log
.agent-local/T06.2.1-red.log. Test-first pushed and remote SHA verified.
No owner production behavior was written before this evidence.
Owner implementation after RED composes the concrete coordinator, capture runtime and activity controller. Epoch reservation precedes awaits; cancellation closes admission immediately; failures latch before async reconciliation; cleanup awaits preflight, actual audio stopped/deactivated fact, then actual activity ended fact before domain acknowledgement. Only the shared cleanup task finalizes, and late callbacks cannot auto-retry a failed attempt. No tests changed; full native GREEN pending.

## T06.2.1 review regressions — RED pending

Independent review found two concrete races in the first owner implementation,
before any GREEN claim: toggle may read domain idle while a start reservation
already exists and silently no-op; cancelling the caller during permission may
leave the Activity/domain owner retained after capture cancellation. Added
regression tests BEFORE repairing either path. A package-internal deterministic
reservation scheduling hook delays the real coordinator call; public production
construction always supplies nil. Permission is held at its existing OS boundary.
Both tests still use actual coordinator/capture/activity policy. Original ten
assertion bodies remain; only harness boundary scheduling support is extended.
Expected103discovered tests, with new failures and prior behavior measured by CI.
No regression fix/meaningful RED claimed until actual results. Next run4 is the
expanded regression RED; the first owner implementation remains unverified.

## T06.2.1 review RED — actual failures, then test scheduling correction

Source **beca15403316f4265245820b0693da6299b39592**,
[run40012128846](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40012128846),
23October2026 at19:33:41UTC: **103executed,101passed,2failed,
10assertion failures,0skip**. Original ten owner tests and previous91pass.
Real converter/CAF/readiness/flush/retry behavior therefore executed. New toggle
returns early, later activates unwanted mic/activity and leaves preparing;
caller cancellation leaves domain preparing and Activity active. Both are
meaningful behavioral RED. Node/TSAN/native did not run after Swift RED.

Reviewer also found one over-specified assertion: requiring observation of a
transient stopping state after releasing a gate can reject correct cancellation
that reaches idle before preflight begins. Corrected only that observation to
accept stopping-with-cleanup OR settled-idle with no session/cleanup, added
nil final failure. All safety/no-resource/final-idle and early-return assertions
remain. This is a requirement/scheduling correction, not an accepted behavior
relaxation. Production bugs remain unchanged. Push/run refined tests for RED
again BEFORE repairing either bug; expected both still fail on actual valid
assertions. Full ignored log.agent-local/T06.2.1-review-red.log preserved.
Refined test-only diff independently reviewed: transient scheduling condition corrected, valid early-return/noOS/final-state assertions preserved, nilfailure strengthened. No production diff since beca154. Re-RED is next, before production repairs.
Refined test-only source8ab36fb36f0064efaf72ee430ff62eda0459f946 pushed/remote verified; run40012791771 active. No production repair before its valid RED. Current invocation5/6dispatched; run6 reserved for checked full GREEN, no seventh run.

## T06.2.1 refined regression RED — verified before repairs

Test-only **8ab36fb36f0064efaf72ee430ff62eda0459f946**,
[run40012791771](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40012791771),
23October2026 at19:38:58UTC: **103executed,101passed,2failed,
9assertion failures,0skip**. Valid early-return, unwantedOS-start/final-state
and cancellation Activity-leak assertions all failed. The transient-state
correction did not hide either bug. Original ten owner cases and old91 still
pass. Swift compiler/discovery/assertions worked; Node/TSAN/native not run.
Full local ignored log.agent-local/T06.2.1-refined-red.log. Refined test-only
commit pushed and remote verified before either repair. Five invocation runs
terminal; run6 is final full GREEN attempt, no seventh dispatch/re-run.
After refined RED only: toggle sends an existing admitted reservation through stop when the domain has not entered preparing; capture cancellation enters/awaits the same combined cleanup barrier. Explicit-retry policy after a settled failed cleanup remains unchanged. Tests have no diff since refined RED. Full GREEN and native compile pending final run6.
Final independent review of the real owner repair diff found no concrete blocker: reserved toggle closes epoch before reservation wait; cancellation joins shared cleanup, with no self-await cycle and no automatic retry after failed cleanup. Tests unchanged since refined RED. Native compilation and complete regressions remain required.

## T06.2.1 GREEN — actual owner and native regressions

Implementation **9eeaa25c53ba7e22b32ae4c1f3f65034edcbc48f**,
[run40013807701](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40013807701),
23October2026 about19:49UTC, overall success. **103XCTest,59Node,
69 repeatedXCTest under ThreadSanitizer,2nativeproduct+13packaging checks**
passed,0failures/skips/races. Test source unchanged since refined8ab36fb RED.
Command swift test --enable-code-coverage; swift test --sanitize=thread with
queue/admission/runtime/activity/owner filter; node --test scripts/tests/*.test.mjs;
actual Release generic iOS+Debug generic iOSSimulator builds; native product and
real package tests. Hostedmacos-15-intel/Xcode26.2.

The concrete owner uses the real coordinator, bounded owned PCM, native converter,
CAF writer/manifest and Activity resource policy. Only permission/hardware/SDK/
model-preparation boundaries are doubled. Actual converted 16-bit16kmonoCAF is
decoded/compared after source mutation; actual drain/deactivate precedes Activity
end and domain completion. Duplicate/coalesced stop, cancellation/preflight/
reservation races, readiness, failure/loss, retired epoch callbacks and retry
all pass. No failed cleanup is declared completed, no auto-retry loop, and no
unchecked concurrency suppression. Independent real-diff review passed.

Actual device arm64 and simulator x86_64/arm64 app+extension compiled. Ephemeral
unsigned IPA179,956bytes, SHA256c91343d090a052226b831550e7f8a04dcb2db98c71321ce802b4713ddcdf4b76,
created19:49:20.875UTC. Not uploaded/retained/delivered/signed/installed. Full
ignored local log.agent-local/T06.2.1-9eeaa-validation.log. candidateArtifact null.

T06.2.1CODE_COMPLETE_PENDING_DEVICE within tested owner-component scope. The
native app entry is STILL unwired; no native recording intents, full UI or
real ASR preparation provider exists. Ready preparation in tests is only a
boundary double, never inference evidence. All realmodel/signing/LockScreen/
ActionButton/two-hour/renewal gates remain NOT_RUN. Overall IN_PROGRESS.

NextT06.2.2:11 uncompiled router tests/minimal interface are saved outside all
active paths in docs/drafts/T06.2.2. Recheck cost/Git in next invocation, activate
only tests/stubs plus scoped-stop interface and activation-failure OS fixture,
prove/push RED before behavior, then actual native app/intent/foreground fallback.
Six of six current runs terminal; no seventh dispatch/re-run or active-source
push after this GREEN. Documentation-only final checkpoint follows.
