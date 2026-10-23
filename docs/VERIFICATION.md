# Verification index

Status: T00 repository bootstrap verified; application implementation and device evidence are pending.

Maintain one row per requirement/test gate with: requirement ID, test name or manual procedure, RED evidence reference, GREEN evidence reference, exact source SHA, model/dependency hashes where applicable, environment, result, evidence location, and limitations.

Use PASSED / FAILED / NOT_RUN / BLOCKED / OWNER_WAIVED explicitly. Never treat NOT_RUN or a mock as PASSED. An owner-waived mandatory gate prevents an unqualified baseline-complete claim. Keep raw device evidence local; commit only sanitized summaries.

| Requirement / gate | Check | RED | GREEN / evidence | Source SHA | Environment | Result | Limits |
|---|---|---|---|---|---|---|---|
| R01 / G01 | Owner, private visibility, reviewed initial commit, push and HEAD comparison | N/A: observation | [T00](evidence/T00_BOOTSTRAP.md) | `5767409b9bc8797a53409bc4bd86799019c833b4` | Windows + GitHub | PASSED | Repository bootstrap only |
| R01 / CI cost guard | Included minutes and existing $0 hard Actions budget | N/A: observation | [T01](evidence/T01_ENVIRONMENT.md) | Initial specification SHA above; account observation dated separately | Signed-in account settings | PASSED | Artifact storage headroom unverified; bounded runs only |
| R02 / G02 harness only | XCTest assertion propagation, deterministic clock and evidence parsing | [T02 RED](evidence/T02_TDD.md) / run 39972652907 | [T02 GREEN](evidence/T02_TDD.md) / run 39973529078 | RED `ef311b9`; parser RED `b12ac5c`; GREEN `87dadb4c030a24f5206a7658ea51c49d09579966` | macos-15-intel / Xcode 26.2; Node also Windows | PASSED | 2 XCTest + 8 parser tests; no application behavior coverage |
| R02, R04 / T03 partial | Domain concurrency, readiness, cancellation and failure state | [T03](evidence/T03_TDD.md), runs 39974793184 and 39975336692 | Initial suite passed in run 39975791505 | RED `16995e0`, `bc71753`; initial GREEN `9c39e5f6a44904dc5746fc31c6a1c5e3c9373fc2` | Hosted macOS / Xcode 26.2 | PASSED | 17 domain cases only; review found an additional race, T03 stays IN_PROGRESS; real adapters NOT_RUN |
| R04 / T03.1 domain only | Interruption while activation is in flight must reject late readiness | [Verified RED](evidence/T03_TDD.md#t031-regression-red--verified), run 39976742123 | [Verified GREEN](evidence/T03_TDD.md#t031-green--verified), run 39978171921 | RED `33cd7c6`; GREEN `809f653c8b3cb52c1c04943401eb42d166d7e94b` | Hosted macOS / Xcode 26.2 | PASSED | All 20 XCTest + 8 reporting tests passed; real capture adapter still NOT_RUN |
| R03–R12 / G03–G12 | App, models, automated and device acceptance | NOT_RUN | NOT_RUN | None | Required platforms/device pending | NOT_RUN | No app, artifact, inference or device claim |
