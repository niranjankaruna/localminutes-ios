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
