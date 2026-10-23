# Progress log

## Initial state — 23 October 2026
Specification package prepared. No repository, app code, build, installation, or device verification has been performed. Next task: T00.

## Append an entry after each work slice
Include date/time, task/requirement IDs, actual changes, RED test/commit/run, GREEN test/commit/run, regressions, artifact if any, limitations, blockers, and next task. Never replace actual results with planned results. Keep sensitive data out.

## 23 October 2026, 15:42–15:45 Europe/Dublin — T00 and T01 complete

Created and verified private `niranjankaruna/localminutes-ios`. Initial specification
commit `5767409b9bc8797a53409bc4bd86799019c833b4` is pushed on main; remote HEAD
matched local HEAD. The initial 19 files passed staged whitespace and sensitive
content review, including an independent read-only bootstrap review. Evidence:
`docs/evidence/T00_BOOTSTRAP.md`.

T01 account observations verified included Actions minutes and an existing $0
account-wide Actions hard budget through signed-in browser settings. No billing
change or CI dispatch occurred. Artifact storage displays its included limit;
test logs can proceed without artifact uploads. Selected documented standard
`macos-15-intel` with Xcode 26.2 / 17C52 and pinned checkout v7.0.1 commit;
actual hosted environment remains to be logged by T02.
Evidence: `docs/evidence/T01_ENVIRONMENT.md`.

RED/GREEN/product tests: NOT_RUN (documentation/account-only work). No IPA or
device evidence exists; every device gate remains NOT_RUN. Next: run genuine
T02 harness RED/GREEN on hosted macOS. New CI runs so far: 0 of 6.

## 23 October 2026, 15:57 Europe/Dublin — T02 complete

Hosted RED: `ef311b97ed475f9cecec61805f7020ca23a4382f`, run 39972652907:
2 executed XCTest cases, 3 assertion failures, exit 1. Compiled successfully.
The XML report was missing separately; added 8 reporting regression tests,
proved local RED and pushed `b12ac5cab52bdb7797948e3554556d7ce8ac4da3` before
implementing the parser. Local GREEN: all 8 passed; actual native log classified
correctly. Hosted GREEN: `87dadb4c030a24f5206a7658ea51c49d09579966`, run
39973529078: 2 XCTest cases and 8 reporting cases passed, no failures/skips.
Actual environment: macOS 15.7.9, image 20260824.0482.1, Xcode 26.2 / 17C52,
Swift 6.2.3, x86_64. Independent review found no actionable issues.

Evidence: `docs/evidence/T02_TDD.md`; runs: 2 of 6. No IPA/app/model/device
result exists. Next: T03 recording domain tests, prove RED before behavior.

## 23 October 2026, 16:12 Europe/Dublin — T03 partial GREEN; review regression

T03 test-first commit `16995e0b34fda8b57e36a95d1ce58c28b63aa735`, run
39974793184: 18 total XCTest, 39 assertion failures. Review added activation
cancellation before implementation; commit `bc71753f82ad71a55eca3f4f171a3cf661ee3b94`,
run 39975336692: 19 XCTest, 43 assertion failures. Both compiled and executed.
Implemented the command/event recording actor at
`9c39e5f6a44904dc5746fc31c6a1c5e3c9373fc2`; run 39975791505 passed all
19 XCTest and 8 reporting tests, no skips. This is domain state only.

Independent review found a separate interruption-during-activation race. Added
its regression before fixing; T03 remains IN_PROGRESS. The sixth/final run
will prove its native RED, then the invocation checkpoints. Next invocation:
fix T03.1 after RED, verify exact-SHA GREEN and regressions, review, then T04.
No app/IPA, microphone, real model or device evidence exists. Main is preserved
at the bootstrap documentation checkpoint; task history is not merged while
the review issue remains. T04 upstream research was saved without installing
dependencies or implementing a scaffold.

## 23 October 2026, 16:18 Europe/Dublin — invocation checkpoint

Completed task IDs: T00, T01, T02 (including T02.1). T03/T03.1 remain IN_PROGRESS.
Final test-first source `33cd7c6a88195998b6a5f15bb62cc9c6c415045a`, run
39976742123, proved the startup-interruption regression RED: **20 XCTest,
19 passed, 1 failed, 6 assertion failures, 0 skipped**. All 8 reporting tests
passed. No fix has been implemented before recording this RED.

Latest prior GREEN is `9c39e5f6a44904dc5746fc31c6a1c5e3c9373fc2` / run
39975791505 (19 XCTest + 8 reporting tests passed), with the newly exposed
race explicitly unresolved. Full run ledger: `docs/evidence/CI_INVOCATIONS.md`.
Six of six new CI runs completed; no seventh run or background/recursive session
was launched. Current branch: `task/t03-recording-coordinator`; main preserves
the bootstrap documentation checkpoint. The failed RED remains visible.

Artifact blocker: included Actions storage headroom is unverified (display 100%);
no upload/deletion/billing change attempted. No candidate IPA exists. All physical
device gates, real-model inference, microphone capture, Action Button, locked
transcription, two endurance runs and signing/renewal remain NOT_RUN.

Exact next task: T03.1, update `RecordingCoordinator.interrupt(for:)` to handle
activation-in-flight, emit one cleanup command, reject late readiness and retain
interrupted status; require all 20 XCTest and 8 reporting tests GREEN at the new
source SHA, review, then finish T03 and proceed to T04. Project stays IN_PROGRESS.

Final independent checkpoint audit confirmed state, backlog, run ledger and
verification consistency; corrected stale continuation wording. No CI was
dispatched for this documentation-only correction.

## 23 October 2026, 16:30 Europe/Dublin — T03 complete, T04 starting

Resumed from clean checkpoint and confirmed prior regression RED is unchanged.
Classified the prior turn as progress. Reverified included Actions allowance and
existing $0 hard budget; no billing change. Fixed only the interruption guard
after recorded RED, source `809f653c8b3cb52c1c04943401eb42d166d7e94b`.
Run 39978171921: **20 XCTest + 8 reporting tests passed, 0 failures/skips**.
Independent review found no actionable issue. Fast-forwarded main to that exact
GREEN source, pushed and verified remote HEAD. T03/T03.1 completed as domain work.

Continuation runs: 1 of 6. Next: T04 artifact-validator tests, then real native
app/extension configuration RED/GREEN and unsigned packaging. Artifact delivery
remains blocked by unverified included-storage headroom; build/tests without
uploads continue. No iOS app/IPA, microphone/model or device success is claimed.

## 23 October 2026, 17:19 Europe/Dublin — continuation-01 checkpoint

Completed in this invocation: **T03/T03.1, T04.1 and T04.2**. Parent T04 stays
IN_PROGRESS: T04.3 native archive GREEN is pending and T04.4 artifact retention
is blocked by unverified included-storage headroom. Full application remains
IN_PROGRESS; these are domain/build milestones, not baseline completion.

Actual evidence: T03 source `809f653` / run 39978171921 passed 20 XCTest + 8 Node. T04.1
source `2711186` / run 39981859388 passed 20 XCTest + 43 Node. T04.2 source `a3f5849` /
run 39983105414 compiled the real device+simulator app/extension and passed 2
compiled-product checks, while the 13 new packaging tests honestly failed against
the stub. Review then found sidecar/private-directory and path-alias gaps.
Regression test-first commit **bafe949cf3768fc9ae82868e502a8bd48474d388**,
run **39985432474**, proved 7 missing-exception assertions on hosted macOS:
20 XCTest passed; Node 51 executed, 44 passed, 7 failed, 0 skipped. Native job was
skipped after core RED and provides no packaging result.

Fix **14a988604c05e2484e9d08bf5d4d11e04d217e73** is committed locally,
reviewed and passes **all 51 Windows script tests**, including a real temporary
junction. Initial sandbox junction denial was not counted as RED; authorized
workspace-contained testing proved both RED and GREEN. No native packaging
GREEN, IPA, device result or offline inference is claimed. Windows installation
and renewal guidance is drafted from official sources and remains unexecuted.

Six of six CI runs are complete, no active run or seventh dispatch remains.
Task branch `task/t04-ios-build` has local fix/checkpoint work ahead of remote
bafe949. No force push, artifact upload/deletion, billing change, credentials or
private meeting/model data were involved. Main retains the completed T03 history.
All signing/extension installation, Action Button warm/locked cold-start,
locked live transcription, two 125-minute runs, real-model and in-place renewal
gates remain NOT_RUN. Candidate artifact remains null.

Exact next action: in a new invocation, recheck actual branch/remote/latest CI and
included allowance/$0 guard, then push the saved fix/checkpoint. Require GREEN
at the exact pushed commit for 20 XCTest, 51 Node, 2 compiled-product tests,
13 native packaging tests and actual unsigned IPA creation. Preserve the RED
history. If GREEN, complete T04.3 and begin T05 capture tests; separate T04.4
retention does not block capture development, and its acceptance is unchanged.

Final independent checkpoint audit reconciled task status, counts, Git refs,
CI cap and pending gates. Clarified that T04.3 needs native packaging GREEN;
candidateArtifact additionally needs T04.4 retention/delivery. No acceptance
criterion or failed test was removed. The final documentation checkpoint is
saved locally alongside the fix; pushing waits for the next invocation.

## 23 October 2026 — T04.3 verified; T05 starting

Continuation-02 classified the previous turn as progress and resumed its exact
saved fix after verifying Git, private remote, CI and the existing $0 hard stop.
Run 39987058071 at source `ca80375` passed 20 XCTest, 51 Node, 2 native product and 13 real
packaging tests (0 failures/skips). Both device and simulator targets compiled.
Actual unsigned IPA, 42,332 bytes, with checksum/manifest was created only on the
runner; SHA `0c8a531e68d0e9b32b04a2a1b3a70687715d88ac07de135f54f0c41a7d637905`.
No upload/retention, signed extension, microphone, model or device result is
claimed. T04.3 is complete; T04.4 storage blocker and overall IN_PROGRESS remain.
Main was fast-forwarded to tested `ca80375` and pushed/verified. Full TDD evidence
and invocation ledger are updated. New runs 1 of 6. Next task T05.1: write PCM
handoff tests first, then native RED/GREEN; retain T05's real capture/writer scope.

T05.1/T05.2 preparation on `task/t05-capture`: 22 owned-queue, 5 real conversion
and 6 real CAF writer tests plus minimal no-behavior interfaces are reviewed for
hosted RED. Expected total 53 XCTest; actual compilation/discovery/assertions
remain unverified. No production queue/resampler/writer behavior was written.
Next dispatch is current invocation run 2 of 6, before any implementation.

Actual T05 native RED at `818481c`, run39990764814: 53 XCTest executed,
20 passed, 33 failed, 139 assertions, 0 skipped; compile and discovery succeeded.
The empty queue rejected valid PCM, and conversion/writing remained unimplemented.
Node/native-build did not run after Swift RED. Review strengthened cross-append
PCM checks and added a before-finish durable checkpoint case (54 tests expected).
Push that test-only follow-up next, then implement after native RED is preserved.

Expanded writer source `bc4e1b7` / run39991627557 compiled and ran 54 XCTest:
20 passed, 34 failed, 140 assertions, 0 skipped. Closed-segment checkpoint case
failed against the stub as intended. After preserving both RED results, queue,
real conversion and CAF writer implementations are prepared for GREEN run 4 of 6.
Queue regression will also run under Thread Sanitizer. No native GREEN or real
microphone/device result is claimed from static review.

Independent review found converter finish can hide an earlier native drain error.
Implementation commit `55423fa` remains unverified; two SDK-boundary fault tests
are added before fixing the failure state. Existing signal tests still exercise
real conversion. Next push proves this regression RED (56 XCTest expected),
current invocation run 4 of 6, then the minimal fix and full native GREEN follow.

Run39993142381 at `e072a6f` failed compilation on actual SDK Sendable captures;
zero XCTest ran, so it is not regression RED. First bounded repair provides a
lock-protected, callback-owned input cursor on the conversion worker only.
The real-time queue remains lock-free. Terminal failure behavior is intentionally
unchanged until actual assertions execute. Next is run5; two run slots remain.

Verified regression RED at `ef6cad8` / run39993877448: 56 XCTest,54 passed,
2 failed,5 assertions,0 skips. All real converter/writer and queue tests pass;
only the new native-error state tests fail. Minimal fix now latches native
conversion failure and marks finish successful only after drain succeeds.
Final run6 will require all56 +51 script tests,22 queue sanitizer executions,
device/simulator builds,15 native product/package tests and actual ephemeral IPA.
The existing $0 budget and 1,356.3 displayed included minutes remain verified;
storage upload remains blocked. No seventh run is allowed this invocation.

## 23 October 2026, 17:29 UTC — continuation-02 checkpoint

Completed task this invocation: **T04.3**, verified native packaging at ca80375/
run39987058071. T00–T03 and T04.1/2 were already complete. Parent T04 still needs
retained artifact delivery. T05.1/T05.2 implementations now pass actual native
unit execution but remain IN_PROGRESS pending full CI/native regression.

Final run39994364160/source `c5b45a548afc445306b4eb04ec2af16eb20fd11b`:
**56 XCTest +51 Node passed**, plus **22 repeated queue tests under Thread
Sanitizer passed**, no failures/skips/reported race. Overall CI **FAILED** solely
at evidence parsing of the valid filtered `Selected tests` root. The native-build
job was skipped. No new native app/archive/IPA or microphone/model/device success
is claimed at this source. Earlier ca80375's 42,332-byte IPA was ephemeral and
unretained; candidateArtifact remains null.

Saved reporter test-first commit `35074aaf5009de2897ba7bf8d7fd3a48ceab624e`
locally, not pushed. At that exact source Windows11/Node24.21.0 portable suite:
**59 executed,54 passed,5 failed,0 skipped**, exit1. Eight new cases preserve
strict counts, names, failures, skips and complete aggregate checks. The parser
production file is unchanged. No failing CI was hidden or acceptance removed.

Six of six new CI runs are terminal; no active job/seventh dispatch remains.
Last account observation643.7/2,000 included minutes used, billable$0, existing
account-wide$0 hard stop; storage100%/headroom unverified. No artifact upload,
unrelated deletion, billing change, public publication or Apple credential action.
All physical signing/extension, Action Button warm/locked cold-start, locked live
transcription, real-model, two125-minute runs and renewal gates remain NOT_RUN.

Exact next action **T05.2.1**: new invocation rechecks private Git/CI and cost
guard, pushes saved test-first/checkpoint for hosted RED, then fixes strict
selected-root reporting and requires exact-SHA full regression, sanitizer and
device/simulator/packaging GREEN. T05.3 real microphone follows. Callback gate
tests/interfaces are preserved as uncompiled drafts outside active Core/Tests;
do not activate them before reporter RED or they would mask that failure.
Project stays IN_PROGRESS. No user action is needed for current code.

Final independent audit examined actual diffs, CI/local test logs, Git refs,
state/backlog/evidence and the pending drafts; no inconsistency found. Production
parser remains unchanged and the active native source remains c5b45a5. Save the
checkpoint locally after test-first35074aa; pushing waits for the next invocation.

Continuation-03 resumed the exact saved reporter tests/checkpoint, classified
the prior turn as progress, and reverified private Git identity/authentication,
terminal CI and the existing$0 hard stop with1,304.7 displayed included minutes
remaining. New runs0of6; storage delivery still blocked. Push test-first RED next,
then minimal parser fix and full exact-source native GREEN; no feature scaffold.

Reporter hosted RED verified at b04e9a4/run39996675578:56 XCTest passed;
59 Node,54 passed,5 failed,0 skipped. Only then changed the strict aggregate
root alternative; all59 Windows script tests pass and the actual archived
22-case sanitizer log parses correctly. Next: run2 exact-source full native GREEN.


## 23 October 2026,17:51 UTC — continuation-03 GREEN checkpoint

Completed **T05.1,T05.2,T05.2.1** at 4b639078337bd37e408cd1a4b58f268db35b2987/run39997623318:56 XCTest,59 Node,22 repeated queue TSAN and15 native product/packaging tests passed,0 failures/skips; device/simulator app and extension compile. Ephemeral84,620-byte IPA verified on runner only, not retained; artifact storage blocker unchanged. Real microphone/ASR, free signing/extension, Action Button, locked capture, both125-minute runs and renewal remain NOT_RUN. Two of six new CI runs used, both terminal. Next:T05.3 activate reviewed callback and runtime contract tests for run3 meaningful native RED before implementation. Overall IN_PROGRESS; no current code action needs user input.

T05.3 next test-first change activates22 tests and no-op interfaces only; expected78 XCTest uncompiled. Run3 must demonstrate behavioral RED. Pre-dispatch guard809/2,000 minutes used,$0 billable and existing$0 hard stop, storage100%. No runtime/gate production behavior or phone evidence yet.

T05.3 RED verified before behavior atf6e2b6d/run39999604752:78 XCTest,56 passed,22 failed,89 assertion failures,0 skipped. All22 new cases fail; prior56 pass. Implement gate/real pipeline now, then run4 exact-source GREEN. Three of six runs used and terminal.


## 23 October2026,18:17 UTC — T05.3 hosted GREEN

T05 capture component is CODE_COMPLETE_PENDING_DEVICE at c12bd9cde402e9529ad4fb5fbcb35624bbf744f1/run40001047762:78 XCTest+59 Node+44 repeated TSAN+15 native checks passed,0 failures/skips; device/simulator app+extension compile. Actual127,963-byte unsigned IPA ephemeral only. No usable capture screen yet; T06.2 owns composition/intents. Real microphone, class-C/crash recovery, ASR, signing/extension, Action Button, locked capture, two125-minute passes and renewal remain pending. Four of six runs terminal. Next:T06.1 nine activity resource tests with no-op interface for run5 RED, then actual SDK adapter/run6 GREEN. Overall IN_PROGRESS; storage delivery still separately blocked.

T06.1 nine resource contracts and no-op interface activated on task/t06-activity;
expected87 total XCTest uncompiled. No controller/SDK behavior before RED.
Pre-run5 account check933/2,000 included minutes used,1,067 remaining,$0 billable,
existing Actions$0/$0 Usage blocked, storage100%. Last two invocation slots
are run5 RED and run6 GREEN, bounded standard runners only.

T06.1 RED atb95de19/run40002877757:87 XCTest,78 pass,9 fail,47 assertions,0 skipped; all prior78 pass. Implement controller/actual SDK backend now; one final run6 slot remains, no seventh run.

Final run6/40004059233 at e2876e8 is active after strict87-case RED; no implementation GREEN yet. Six of six invocation slots used; no additional run/re-run permitted. Observe same run and checkpoint exact verdict.


## Continuation-03 final checkpoint

Completed **T05.1,T05.2,T05.2.1**; T05/T05.3 are **CODE_COMPLETE_PENDING_DEVICE** within microphone-component scope. Actual full native GREEN atc12bd9c/run40001047762:78 XCTest+59 Node+44 repeated TSAN+15 native checks,0 failures/skips; device/simulator app+extension compile. Its127,963-byte unsigned IPA was ephemeral and not retained/delivered. Main is held at documentation checkpointa1f8a4a atop that verified implementation.

T06.1 stays **IN_PROGRESS**. Test-firstb95de19/run40002877757 proved87 executed,78 pass,9 fail,47 assertions,0 skipped before behavior. Productione2876e8/run40004059233 passed87 XCTest+59 Node+53 repeated TSAN,0 failures/skips, but FAILED iOS device compilation at stored ActivityKit receiver async update/end isolation. Simulator/native product/package checks did not complete;0 native checks and no new IPA at e2876e8. The failed CI is preserved.

Diagnosis and concrete ID-only SDK operation candidate are saved in docs/drafts/T06.1/NATIVE_REPAIR.md and ActivityKitOperations.swift.pending, outside active paths. No production fix is applied and no repair was compiled. Missing lookup remains an explicit outcome; its cleanup/failure contract needs regression RED before integration. Exact next task **T06.1.1**: new invocation rechecks Git/cost guard, writes/proves/pushes that regression RED, integrates the checked native boundary, and requires full exact-source native GREEN before T06.2 app composition/intents. No owner action is needed for this code issue.

Six of six CI runs are terminal; no seventh run/re-run. Final displayed1,026/2,000 included minutes used,974 remaining,$0 Actions billable; existing$0 hard stop last checked before final dispatches. Storage100% still blocks retained artifact delivery. No paid resource, publication, billing change, Apple credential or artifact upload occurred. Overall **IN_PROGRESS**, verifiedComplete=false. Usable recording screens, real ASR/summaries/product features and all physical signing/extension, Action Button warm/locked-cold, locked live transcription, both125-minute runs and in-place renewal remain pending/NOT_RUN.

Final independent checkpoint audit checked actual Git refs/status, six terminal runs, state/backlog/verification and the two draft files. No contradictory completion, native-package or device claim found; active sources remain e2876e8, unmerged to main. Save/push only this documentation checkpoint.

## Continuation-04 — T06.1.1 meaningful RED and implementation pending GREEN

Resumed private task/t06-activity, verified auth/refs/latest failed CI and free
cost guard; previous invocation made code/evidence progress. First new run
40007944579 atb873d6b:91XCTest,87pass4fail20assertions0skip. Tests show missing
SDK cleanup cannot be acknowledged and retry/update loss must be observable.
After RED, added checked operation handling and actual ID-only SDK boundary;
no native repair/GREEN claimed before CI. Old9contracts preserved. Exact next:
verify focused/regression/sanitizer and native app+extension/package at new SHA.
Device/signing/ASR/endurance/renewal remain NOT_RUN; artifact uploads blocked
by full/unverified storage. Six-run cap current1/6, all prior ledgers preserved.

T06.1.1 GREEN b6f4bdf/run40008712625:91Swift+59Node+57repeatedTSAN+15native
checks allpassed0skip, actual device/simulator app+extension builds. First native
repair succeeded. Ephemeral156,390-byte unsigned IPA verified, not retained or
delivered. T06.1/T06.1.1codecompletependingdevice; overallIN_PROGRESS. App-owned
integration tests/minimal interface are being prepared forT06.2.1; no owner
behavior before their hosted RED. Current2/6runs terminal. All phone/model/
endurance/renewal gates remain NOT_RUN; upload headroom still blocked.
