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
| [40007944579](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40007944579) | b873d6b081e949b80499217771c705d4445a5a67 | Test-first regression in progress; outcome pending |
