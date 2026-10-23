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
