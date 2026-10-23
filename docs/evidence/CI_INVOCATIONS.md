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
