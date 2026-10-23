# CI invocation ledger

## 2026-10-23-initial

Contract maximum: 6 new runs. Actual: **6**, all completed. One active run per
branch; standard macos-15-intel, 10-minute job timeout. No artifact uploads or
cache allocations. Account guard observation is in `T01_ENVIRONMENT.md`.

| Run | Full source commit | Actual result | XCTest evidence |
|---|---|---|---|
| [39972652907](https://github.com/niranjankaruna/localminutes-ios/actions/runs/39972652907) | `ef311b97ed475f9cecec61805f7020ca23a4382f` | RED: intentional harness/clock failure; XML reporter separately failed | 2 executed, 2 failed cases, 3 assertion failures |
| [39973529078](https://github.com/niranjankaruna/localminutes-ios/actions/runs/39973529078) | `87dadb4c030a24f5206a7658ea51c49d09579966` | GREEN | 2 executed, 2 passed; 8 Node regressions passed |
| [39974793184](https://github.com/niranjankaruna/localminutes-ios/actions/runs/39974793184) | `16995e0b34fda8b57e36a95d1ce58c28b63aa735` | RED: domain behavior absent | 18 executed, 14 failed cases, 39 assertion failures |
| [39975336692](https://github.com/niranjankaruna/localminutes-ios/actions/runs/39975336692) | `bc71753f82ad71a55eca3f4f171a3cf661ee3b94` | RED: expanded startup-cancellation coverage | 19 executed, 15 failed cases, 43 assertion failures |
| [39975791505](https://github.com/niranjankaruna/localminutes-ios/actions/runs/39975791505) | `9c39e5f6a44904dc5746fc31c6a1c5e3c9373fc2` | Initial domain GREEN; later review found additional race | 19 executed, 19 passed; 8 Node regressions passed |
| [39976742123](https://github.com/niranjankaruna/localminutes-ios/actions/runs/39976742123) | `33cd7c6a88195998b6a5f15bb62cc9c6c415045a` | RED: interruption during activation | 20 executed, 19 passed, 1 failed case, 6 assertion failures; 8 Node tests passed |

No mandatory XCTest skips occurred. Failures remain visible, with no expected-
failure wrapper, continue-on-error or unconditional-success replacement.
Local parser RED before implementation is separately recorded at `b12ac5c` in
`T02_TDD.md`; the old path filter did not dispatch CI for that scripts-only commit.

This invocation dispatches no seventh run. Subsequent invocations must preserve
this ledger, reread actual branch/CI state and recheck cost controls before new
metered execution. T03.1 GREEN is the next required run after its implementation;
do not confuse the earlier 19-case GREEN with passage of the new 20-case suite.

## 2026-10-23-continuation-01

Previous invocation classified as progress: it changed the repository, code and
authoritative native test evidence. This continuation resumes the same branch
and recorded RED; it does not recreate/bootstrap the repository or repeat RED.
The initial invocation's six runs remain preserved above.

Maximum six new runs in this invocation. New cost observation:
`T01_ENVIRONMENT.md`, 261.3 / 2,000 included minutes used, existing $0 hard stop,
no storage headroom for artifact upload. T03.1 implementation GREEN is next.

| Run | Source | Result |
|---|---|---|
| [39978171921](https://github.com/niranjankaruna/localminutes-ios/actions/runs/39978171921) | `809f653c8b3cb52c1c04943401eb42d166d7e94b` | T03.1 GREEN: 20 XCTest + 8 Node passed, no failures/skips |
| [39979891163](https://github.com/niranjankaruna/localminutes-ios/actions/runs/39979891163) | `4ef9d870253c363106c141ff9b5b96986e8143bf` | T04.1 RED: 20 XCTest passed; Node 33 executed, 8 passed, 25 failed, 0 skipped |
| [39981007435](https://github.com/niranjankaruna/localminutes-ios/actions/runs/39981007435) | `5f962d6d72eab6a35eb378771cda64e473da77b3` | Expanded T04.1 RED: 20 XCTest passed; Node 43 executed, 8 passed, 35 failed, 0 skipped |
| [39981859388](https://github.com/niranjankaruna/localminutes-ios/actions/runs/39981859388) | `2711186a6ed71de089838900ee4c63cbe78397ce` | T04.1 GREEN: 20 XCTest + 43 Node passed. Both native builds succeeded; T04.2 RED: 2 native executed, 1 passed, 1 failed (Live Activities false), 0 skipped |
| [39983105414](https://github.com/niranjankaruna/localminutes-ios/actions/runs/39983105414) | `a3f5849d882dbb4bb1dea43028e12f5ed7e63837` | T04.2 GREEN: both builds + 2 native checks passed; 20 XCTest + 43 Node passed. T04.3 RED: 13 actual packaging tests failed, 0 skipped (stub only) |
| [39985432474](https://github.com/niranjankaruna/localminutes-ios/actions/runs/39985432474) | `bafe949cf3768fc9ae82868e502a8bd48474d388` | Review regression RED: 20 XCTest passed; Node 51 executed, 44 passed, 7 failed, 0 skipped. Native job skipped after core failure; no native result |

Continuation-01 final count: **6 of 6**, all terminal. No seventh run was
launched. Local fix `14a988604c05e2484e9d08bf5d4d11e04d217e73` passes all
51 Windows script tests but is intentionally not pushed until a new invocation
rechecks the cost guard and resumes the exact native packaging GREEN action.
No artifacts/caches were uploaded, and no billing/publication setting changed.

## 2026-10-23-continuation-02

Previous turn classified as progress: completed native build gates, preserved
real RED, saved the locally green regression fix and a reviewed checkpoint.
Verified current private repository, clean task branch ahead by two commits,
remote bafe949 and terminal RED run39985432474. Resume saved work, no bootstrap
or repeated RED. Cost guard rechecked: 457.7 / 2,000 minutes used, $0 billable,
existing account-wide $0 hard stop; storage still full/unverified for uploads.
Maximum six new runs in this invocation; no new run dispatched before this
observation. First action is to push the saved T04.3 fix/checkpoint for native
GREEN, then continue T05 after actual evidence.

| Run | Source | Actual result |
|---|---|---|
| [39987058071](https://github.com/niranjankaruna/localminutes-ios/actions/runs/39987058071) | `ca803757573b5f98ff502494f5526b1db620b7d5` | GREEN: 20 XCTest + 51 Node + 2 native product + 13 real packaging passed; actual ephemeral IPA 42,332 bytes, no upload |
| [39990764814](https://github.com/niranjankaruna/localminutes-ios/actions/runs/39990764814) | `818481cc11d0c92b8a8d361d9441f82590f4ca98` | T05.1/T05.2 RED: 53 XCTest executed, 20 passed, 33 failed, 139 assertions, 0 skipped. Node/native jobs not run after Swift RED |
| [39991627557](https://github.com/niranjankaruna/localminutes-ios/actions/runs/39991627557) | `bc4e1b7dfd3b09a977826462febcc1263e2cfbae` | Expanded T05.2 RED: 54 XCTest executed, 20 passed, 34 failed, 140 assertions, 0 skipped; compiler/discovery succeeded, Node/native not run |
| [39993142381](https://github.com/niranjankaruna/localminutes-ios/actions/runs/39993142381) | `e072a6f6b335313736780a89398391f868f39093` | Compilation failed on SDK Sendable input-block captures; zero XCTest, not RED. No sanitizer/Node/native result. First bounded compile repair follows |
| [39993877448](https://github.com/niranjankaruna/localminutes-ios/actions/runs/39993877448) | `ef6cad857ce22750ec359fb61cee660de303db62` | Regression RED: 56 XCTest, 54 passed, 2 failed, 5 assertions, 0 skipped. All real conversion/writer and queue tests passed; Node/sanitizer/native not run after Swift RED |
| [39994364160](https://github.com/niranjankaruna/localminutes-ios/actions/runs/39994364160) | `c5b45a548afc445306b4eb04ec2af16eb20fd11b` | 56 XCTest +51 Node +22 repeated queue TSAN cases passed. Overall FAILED: reporter rejects valid Selected tests aggregate; native-build skipped, no new IPA |

Continuation-02 has used **6 of 6** runs; all are terminal. No seventh dispatch
or re-run is permitted. Last read-only account check:643.7/2,000 minutes used,
billable$0, existing$0 hard stop, storage100%. A local reporter regression suite
is saved for next invocation; no skip or workflow change hides the failed run.

## 2026-10-23-continuation-03

Previous turn classified as progress: actual audio/unit/sanitizer evidence,
converter regression repair and a saved reporter test-first checkpoint changed
the next action. Verified clean task/t05-capture at c601c9c, two local commits
ahead of private remote c5b45a5 and terminal run39994364160. Current auth/identity
and repository verified. Cost observation:695.3/2,000 minutes used, billable$0,
existing account-wide$0 hard stop, no storage headroom. Resume saved tests;
no bootstrap or production parser change before hosted RED. Six-run cap starts
at zero for this invocation; prior six-run ledger remains intact.

| Run | Source | Actual result |
|---|---|---|
| [39996675578](https://github.com/niranjankaruna/localminutes-ios/actions/runs/39996675578) | `b04e9a4d3db270c4592bddee3566ffbd6f7d56dd` | Reporter RED verified:56 XCTest passed;59 Node,54 passed,5 failed,0 skipped. Sanitizer/native not run after Node RED |
| [39997623318](https://github.com/niranjankaruna/localminutes-ios/actions/runs/39997623318) | 4b639078337bd37e408cd1a4b58f268db35b2987 | GREEN:56 XCTest,59 Node,22 repeated queue TSAN,2 native product and13 packaging checks; device/simulator app+extension compiled; ephemeral IPA84,620 bytes, no upload |
| [39999604752](https://github.com/niranjankaruna/localminutes-ios/actions/runs/39999604752) | f6e2b6d8296b4a0cdbc61616c6e4bc509a619c33 | RED:78 XCTest executed,56 passed,22 failed,89 assertion failures,0 skipped; Node/TSAN/native not run after Swift RED |
| [40001047762](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40001047762) | c12bd9cde402e9529ad4fb5fbcb35624bbf744f1 | GREEN:78 XCTest+59 Node+44 repeated TSAN+15 native checks passed; actual device/simulator builds and ephemeral127,963-byte unsigned IPA verified, no upload |
| [40002877757](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40002877757) | b95de19545db9619b770bdc5fc75aaffb2c28e45 | RED:87 XCTest executed,78 passed,9 failed,47 assertions,0 skipped; Node/TSAN/native not run after Swift RED |
| [40004059233](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40004059233) | e2876e830c8f54c605875e0808dd5d0cb6329e8e | 87 XCTest+59 Node+53 repeated TSAN passed; overall FAILED at iOS ActivityKit update/end isolation compilation.0 native product/package checks and no new IPA. Six-run cap terminal; no seventh dispatch |

Continuation-03 used6of6 new runs, all terminal. Latest full native GREEN remainsc12bd9c/run40001047762. T06.1 checked SDK-operation candidate is saved outside active paths; regression RED and native repair validation follow next invocation; no new run/re-run is permitted here.

## 2026-10-23-continuation-04

Previous goal turn classified as progress: verified core/activity RED and GREEN,
localized a real native SDK isolation failure, and saved an uncompiled repair
candidate with a concrete checked-outcome regression next step. Verified clean
private task/t06-activity at3c3d8ff, authenticated owner/identity and terminal
run40004059233 at e2876e8. Last full native GREEN remainsc12bd9c. No bootstrap
repeated. Read-only account observation:1,026/2,000 included Actions minutes
used,974 displayed remaining, Actions billable$0; account-wide Actions$0/$0
Usage blocked. Storage0.5/0.5GB100%, no uploads. No billing/visibility changes.
Six-run cap starts at0 for this new goal invocation; previous ledgers retained.
| [40007944579](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40007944579) | b873d6b081e949b80499217771c705d4445a5a67 | RED:91XCTest87pass4fail20assertions0skip; old87pass; Node/TSAN/native not run after Swift RED |
| [40008712625](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40008712625) | b6f4bdf0231d72d279ae690c5ce20936b8225459 | GREEN:91XCTest+59Node+57TSAN+15native passed; actual device/simulator app+extension builds, ephemeral156,390-byte IPA, no upload |

Continuation-04 current2/6 new runs, both terminal. First native compile repair
succeeded. Regression RED sourceb873d6b:91executed87pass4fail20assertions0skip.
| [40010164221](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40010164221) | fdfab8905e479c7e1343f394c85ceecc9b52b1e0 | Owner RED:101XCTest91pass10newfail38assertions0skip; old91pass; Node/TSAN/native not run |
| [40012128846](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40012128846) | beca15403316f4265245820b0693da6299b39592 | Review RED:103XCTest101pass2newfail10assertions0skip; original10owner+old91pass. One transient-state test observation corrected before re-RED; no production repair yet |
| [40012791771](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40012791771) | 8ab36fb36f0064efaf72ee430ff62eda0459f946 | Refined RED:103XCTest101pass2fail9assertions0skip; valid safety failures persist with production unchanged. Five runs terminal |
| [40013807701](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40013807701) | 9eeaa25c53ba7e22b32ae4c1f3f65034edcbc48f | GREEN:103XCTest+59Node+69TSAN+15native passed0skip; actual device/simulator app+extension builds and ephemeral179,956-byte IPA, no upload |

Continuation-04 final **6/6**, all terminal. No seventh run/re-run. Owner resource
component exact-source full GREEN9eeaa25; overall baselineIN_PROGRESS. T06.2.2
router tests/notes are uncompiled drafts outside active paths, ready for next
invocation's cost/Git check and test-first activation. No code/CI completion
is inferred for native intents, models, UI or physical gates.

## 2026-10-23-continuation-05

Previous goal turn classified as progress: exact-source owner/native GREEN and
reviewed test-first drafts were checkpointed and fast-forwarded to private main.
Verified clean main/task refs at0b85984, authenticated intended owner/Git identity,
and terminal successful run40013807701 at9eeaa25. No bootstrap repeated.
Read-only cost check:1,274/2,000 included Actions minutes used,726 displayed
remaining,$0 billable; existing account-wide Actions$0/$0 Usage blocked.
Storage0.5/0.5GB100%; no uploads, deletions, billing or visibility changes.
New invocation starts at0of6 runs. Activate eleven saved router tests and no-op
router/scoped-stop interfaces only; meaningful hosted RED is required before
behavior. Actual native intents, real models and every phone gate are unfinished.
| [40016043242](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40016043242) | b561558052a1909c4899cb5cab3891e6f72bde0f | RED:114XCTest103pass11newfail61assertions0skip; old103pass; Node/TSAN/native not run |

| [40017195075](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40017195075) | 01531f590c5de43c912c865f3ec8d3584f2d9421 | Regression RED:115XCTest114pass1newfail2assertions0skip; original114pass; Node/TSAN/native not run |

| [40017962923](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40017962923) | 40100fdb9a8349acdbf2d22c63eb25ce959e9388 | GREEN:115XCTest+59Node+81repeatedTSAN+15native passed0skip; actual device/simulator app+extension and ephemeral188232-byte IPA, no upload |

Pre-native-RED cost check:1,387.7/2,000 included minutes used,612.3 displayed remaining,Actionsbillable$0; existing account-wide Actions$0/$0 Usageblocked rechecked. Storage100%; no uploads/billing/visibility changes. Native job remains15min, core10min, standardmacos-15-intel; no larger/paid runner.

| [40020680067](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40020680067) | 81960fd669614313a61c499704663178b5800234 | Native app/content RED:37executed24pass13newfail82assertions0skip, result bundle agrees. Core115+59Node+81TSAN pass, products/test targets compile. Job15min timeout during result processing; UI not run,0package checks/no IPA |

Four of six runs terminal. The37-case native RED is meaningful and recorded
before implementation. Three UI contracts and hidden Stop SDK mode probe still
need execution before their corresponding behavior. Native next job is bounded
25minutes (configuration maximum45), core10minutes, standard runner only; no
upload. Failure diagnostic collection disabled using Apple's documented option,
with all assertions, exit failures, result summaries and strict discovery intact.

Pre-run5 read-only cost observation21:07UTC:1,604.7/2,000 used,395.3 displayed
remaining, Actionsbillable$0; account-wide Actions$0/$0 Usageblocked confirmed.
Storage100%, no uploads. One bounded standard-runner run next; reverify actual
allowance before any sixth dispatch. No settings or publication changed.

| [40024451125](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40024451125) | 7c1ae7c6edda4a4ee23b47299e45f22a6fcef409 | Native38GREEN, UI3RED (3fail3assertions0skip), core115+59Node+81TSAN pass; product/test targets compile. Overall failure from real UI assertions, no timeout; package0/no new IPA |

Pre-final-run read-only allowance1,780.3/2,000 used,219.7 displayed remaining,
billable$0, Actions$0/$0 Usageblocked confirmed; storage100%. Core6min/native15min
bound final run to21runner minutes (210 included macOS minutes); prior actual
durations3m42s/12m22s fit. All tests and failure checks stay mandatory. Shared
allowance is not reserved. No upload/payment/visibility/budget setting changed.

| [40027966192](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40027966192) | 6b5fd0c074672c467f0d26c5797683b706ec8263 | Terminal cancelled at15m bound after native39 executed38pass1fail9assertions0skip (new Toggle regression RED); core115+59Node+81TSAN pass, actual products/test targets compile. UI2started/1completed-pass/second interrupted in teardown/third not started; no aggregate/package/new IPA |

Six-run dispatch cap reached. Follow this exact live run only; no seventh push
trigger, manual dispatch or re-run this invocation. Documentation-only checkpoint
pushes do not trigger the workflow. New behavioral repair must retain its RED
history and await later exact-source full GREEN; preserve known-good main.

Final run annotation confirms maximum15m0s. No UI aggregate is accepted; the strict
reporter rejects the incomplete suite. All6/6 runs terminal; no seventh dispatch.
Covered local repair695b99b and public-build configuration4dfacf6 are unpushed.
The owner explicitly approved public visibility; authenticated and unauthenticated
GitHub API checks confirm PUBLIC. Standard macos-15-intel is officially free for
public repositories; native time bound restored to25min for the next invocation.
See T01_PUBLIC_REPOSITORY.md. No billing settings or spending guard changed.
