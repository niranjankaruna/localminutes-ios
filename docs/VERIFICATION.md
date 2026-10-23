# Verification index

Status: T00 repository bootstrap verified; application implementation and device evidence are pending.

Maintain one row per requirement/test gate with: requirement ID, test name or manual procedure, RED evidence reference, GREEN evidence reference, exact source SHA, model/dependency hashes where applicable, environment, result, evidence location, and limitations.

Use PASSED / FAILED / NOT_RUN / BLOCKED / OWNER_WAIVED explicitly. Never treat NOT_RUN or a mock as PASSED. An owner-waived mandatory gate prevents an unqualified baseline-complete claim. Keep raw device evidence local; commit only sanitized summaries.

| Requirement / gate | Check | RED | GREEN / evidence | Source SHA | Environment | Result | Limits |
|---|---|---|---|---|---|---|---|
| R01 / G01 | Owner, private visibility, reviewed initial commit, push and HEAD comparison | N/A: observation | [T00](evidence/T00_BOOTSTRAP.md) | `5767409b9bc8797a53409bc4bd86799019c833b4` | Windows + GitHub | PASSED | Repository bootstrap only |
| R01 / CI cost guard | Included minutes and existing $0 hard Actions budget | N/A: observation | [T01](evidence/T01_ENVIRONMENT.md) | Initial specification SHA above; account observation dated separately | Signed-in account settings | PASSED | Artifact storage headroom unverified; bounded runs only |
| R02 / G02 harness only | XCTest assertion propagation, deterministic clock and evidence parsing | [T02 RED](evidence/T02_TDD.md) / run 39972652907 | [T02 GREEN](evidence/T02_TDD.md) / run 39973529078 | RED `ef311b9`; parser RED `b12ac5c`; GREEN `87dadb4c030a24f5206a7658ea51c49d09579966` | macos-15-intel / Xcode 26.2; Node also Windows | PASSED | 2 XCTest + 8 parser tests; no application behavior coverage |
| R03–R12 / G03–G12 | App, models, automated and device acceptance | NOT_RUN | NOT_RUN | None | Required platforms/device pending | NOT_RUN | No app, artifact, inference or device claim |
