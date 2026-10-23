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
