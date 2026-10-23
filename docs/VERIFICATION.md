# Verification index

Status: T00–T03,T04.1–T04.3,T05.1,T05.2 and T05.2.1 verified within their scopes. Artifact retention, capture, models, product features and every physical-device gate remain pending.

Maintain one row per requirement/test gate with: requirement ID, test name or manual procedure, RED evidence reference, GREEN evidence reference, exact source SHA, model/dependency hashes where applicable, environment, result, evidence location, and limitations.

Use PASSED / FAILED / NOT_RUN / BLOCKED / OWNER_WAIVED explicitly. Never treat NOT_RUN or a mock as PASSED. An owner-waived mandatory gate prevents an unqualified baseline-complete claim. Keep raw device evidence local; commit only sanitized summaries.

| Requirement / gate | Check | RED | GREEN / evidence | Source SHA | Environment | Result | Limits |
|---|---|---|---|---|---|---|---|
| R01 / G01 | Owner, private visibility, reviewed initial commit, push and HEAD comparison | N/A: observation | [T00](evidence/T00_BOOTSTRAP.md) | `5767409b9bc8797a53409bc4bd86799019c833b4` | Windows + GitHub | PASSED | Repository bootstrap only |
| R01 / CI cost guard | Included minutes and existing $0 hard Actions budget | N/A: observation | [T01](evidence/T01_ENVIRONMENT.md) | Initial specification SHA above; account observation dated separately | Signed-in account settings | PASSED | Artifact storage headroom unverified; bounded runs only |
| R02 / G02 harness only | XCTest assertion propagation, deterministic clock and evidence parsing | [T02 RED](evidence/T02_TDD.md) / run 39972652907 | [T02 GREEN](evidence/T02_TDD.md) / run 39973529078 | RED `ef311b9`; parser RED `b12ac5c`; GREEN `87dadb4c030a24f5206a7658ea51c49d09579966` | macos-15-intel / Xcode 26.2; Node also Windows | PASSED | 2 XCTest + 8 parser tests; no application behavior coverage |
| R02, R04 / T03 historical initial suite | Domain concurrency, readiness, cancellation and failure state | [T03](evidence/T03_TDD.md), runs 39974793184 and 39975336692 | Initial suite passed in run 39975791505; later regression fixed in row below | RED `16995e0`, `bc71753`; initial GREEN `9c39e5f6a44904dc5746fc31c6a1c5e3c9373fc2` | Hosted macOS / Xcode 26.2 | PASSED | Historical 17 domain cases; final 18 domain + 2 harness tests pass below; real adapters NOT_RUN |
| R04 / T03.1 domain only | Interruption while activation is in flight must reject late readiness | [Verified RED](evidence/T03_TDD.md#t031-regression-red--verified), run 39976742123 | [Verified GREEN](evidence/T03_TDD.md#t031-green--verified), run 39978171921 | RED `33cd7c6`; GREEN `809f653c8b3cb52c1c04943401eb42d166d7e94b` | Hosted macOS / Xcode 26.2 | PASSED | All 20 XCTest + 8 reporting tests passed; real capture adapter still NOT_RUN |
| R03 / T04.1 | Metadata, native-tool boundary, archive names and real file hash checks | [T04 RED](evidence/T04_TDD.md), runs 39979891163 / 39981007435 | Run 39981859388: 35 validator + 8 reporting tests passed | `2711186a6ed71de089838900ee4c63cbe78397ce` | Windows + hosted macOS | PASSED | Names/metadata boundary only; fixtures are not native products |
| R03 / T04.2 | Actual device and simulator app+extension compilation, plists and Mach-O identity | [T04 native RED](evidence/T04_TDD.md), run 39981859388 | Run 39983105414: both builds + 2 compiled-product tests passed | `a3f5849d882dbb4bb1dea43028e12f5ed7e63837` | macos-15-intel / Xcode26.2 / SDK26.2 / XcodeGen2.46.0 | PASSED | Minimal interfaces only; no simulator execution, installed extension, recording or signing proof |
| R03 / T04.3 filesystem regression | Reject DB sidecars, private directories and canonical output recursion | [T04 regression RED](evidence/T04_TDD.md), run 39985432474: 7 real assertion failures | [Verified GREEN](evidence/T04_TDD.md#t043-green--verified), run 39987058071: all 51 script tests passed | `ca803757573b5f98ff502494f5526b1db620b7d5` | Windows11 / Node24.21.0 and hosted macOS | PASSED | Filesystem boundary only; not a complete release privacy audit |
| R03 / T04.3 actual unsigned IPA | Real ZIP, source stamps, input/privacy validation, checksums and manifest | [Native packaging RED](evidence/T04_TDD.md), run 39983105414: 13 failed | [Verified GREEN](evidence/T04_TDD.md#t043-green--verified), run 39987058071: 13 actual packaging tests passed and ephemeral IPA created | `ca803757573b5f98ff502494f5526b1db620b7d5` | Hosted macOS / Xcode26.2 / SDK26.2 | PASSED | 42,332-byte unsigned IPA verified on runner only; not retained, delivered, installed or phone-tested |
| R03 / T04.4 retained artifact | Deliver verified checksummed candidate | N/A: account observation | [Storage blocker](BLOCKERS.md#artifact_storage_headroom_unverified--external-artifact-delivery-only) | None | Signed-in billing observation | BLOCKED | Included storage headroom unverified; no upload attempted |
| R04, R08 / T05.1–T05.2 historical stub RED | Owned PCM, real resampling and CAF/manifest tests | [Verified RED](evidence/T05_TDD.md#red--verified-native-execution-23-october-2026-1659-utc), run39990764814: 53 executed, 33 failed | Later unit execution below | `818481cc11d0c92b8a8d361d9441f82590f4ca98` | Hosted macOS / Xcode26.2 | FAILED | Historical missing behavior; current passing unit execution is separately scoped below |
| R04, R08 / T05.1–T05.2 actual unit execution | All queue, real conversion/CAF, native error and prior tests | [T05 RED](evidence/T05_TDD.md), runs39990764814/39991627557/39993877448 | Run39994364160:56 XCTest +51 Node passed | `c5b45a548afc445306b4eb04ec2af16eb20fd11b` | Hosted macOS / Xcode26.2 | PASSED | Unit execution only; overall CI failed reporter; no exact-source iOS build/archive or microphone/device result |
| R04, R08 / T05.1 sanitizer execution | 22 queue tests including parallel stress | Same T05 queue RED | Run39994364160:22 repeated XCTest passed with no reported race | `c5b45a548afc445306b4eb04ec2af16eb20fd11b` | Hosted macOS / Thread Sanitizer | PASSED | Reporter rejected valid Selected tests root after tests; not physical real-time/latency evidence |
| R02 / T05.2.1 selected-suite reporting | Strict filtered aggregate/name/count/failure checks | Run39996675578:59 Node,5 failed | [Full GREEN](evidence/T05_TDD.md#t051--t052--t0521-full-green--verified), run39997623318:59 Node and actual22-case TSAN report passed | 4b639078337bd37e408cd1a4b58f268db35b2987 | Hosted macOS/Xcode26.2; Windows Node24.21.0 | PASSED | Historical failure preserved; no relaxed checks |
| R04,R08 / T05.3 callback and runtime | Admission publication, cancellation, actual synthetic conversion/CAF, safe stop | Run39999604752:78 executed,22 failed,89 assertions | [T05.3 GREEN](evidence/T05_TDD.md#t053-green--verified-hosted-capture-component), run40001047762:78 XCTest+59 Node+44 repeated TSAN+15 native checks passed | c12bd9cde402e9529ad4fb5fbcb35624bbf744f1 | Hosted macOS/Xcode26.2/SDK26.2 | PASSED | Component only; iOS adapter compiled, physical microphone and all phone gates NOT_RUN; app composition pending |
| R04–R12 / G04–G12 | Capture, models, product screens, intents and physical-device acceptance | NOT_RUN | NOT_RUN | None | Required platforms/device pending | NOT_RUN | Minimal native interfaces compile; no retained IPA, microphone/model, Lock Screen, Action Button, endurance or renewal proof |
| R04,R08 / T05.1–T05.2 full regression | Owned PCM, real resampling/CAF, fault handling and native products | T05 original and converter regression RED | [Full GREEN](evidence/T05_TDD.md#t051--t052--t0521-full-green--verified), run39997623318:56 XCTest+59 Node+22 repeated TSAN+15 native checks | 4b639078337bd37e408cd1a4b58f268db35b2987 | Hosted macOS/Xcode26.2/SDK26.2 | PASSED | Real microphone, locked capture, recovery, ASR and all phone gates pending; ephemeral IPA not retained |
| R06 / T06.1 resource unit/sanitizer | Readiness, handle identities and update/end ordering | Run40002877757:87 executed,9 failed,47 assertions | [T06 partial GREEN](evidence/T06_TDD.md#unitsanitizer-green-exact-source-native-build-failed), run40004059233:87 XCTest+59 Node+53 repeated TSAN passed | e2876e830c8f54c605875e0808dd5d0cb6329e8e | Hosted macOS/Xcode26.2 | PASSED | Core behavior only; actual iOS SDK backend fails compilation; no new native package/device proof |
| R06 / T06.1 iOS SDK adapter compilation | Actual ActivityKit update/end and state observation | Not RED: compiler rejected non-Sendable actor reference | Run40004059233 native job failed; first repair pending | e2876e830c8f54c605875e0808dd5d0cb6329e8e | iOS SDK26.2/Swift6 | FAILED |0 native product/package checks and no new IPA; no seventh run this invocation |

T06.1.1 regression RED: b873d6b081e949b80499217771c705d4445a5a67,
[run40007944579](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40007944579),
91XCTest=87pass4fail20assertions0skip. Actual macOS assertion failures, not
compiler/zero-test failure. No Node/TSAN/native result after Swift RED. Checked
SDK operation behavior/first native repair now implemented after RED, GREEN
pending. Details docs/evidence/T06_TDD.md. No phone/model/artifact-retention pass.

T06.1.1 exact-source native GREEN: b6f4bdf0231d72d279ae690c5ce20936b8225459,
[run40008712625](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40008712625).
91XCTest,59Node,57TSAN,15native checks passed0skip; actual device+simulator
app/extension compiled. Ephemeral unsigned IPA156,390bytes,
SHA256e8bb24694328c04a8ba5d2bfa89eebdf592ca729f12431bfa562ab8c40df644c,
not retained/delivered/signed/installed. No actual ActivityKit OS behavior,
inference, physical LockScreen/ActionButton/endurance or renewal evidence.

T06.2.1 owner/repair exact-source GREEN:
[run40013807701](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40013807701),
source9eeaa25c53ba7e22b32ae4c1f3f65034edcbc48f.103XCTest,59Node,
69repeatedTSAN,15native checks passed0failures/skips/races. Actual device/simulator
app+extension compiled; real PCM/conversion/CAF/manifest/barrier regressions pass.
Refined regression RED8ab36fb/run40012791771=103executed101pass2fail9assertions0skip,
before unchanged tests went GREEN. Full protocol/source chain:T06_TDD.md.
Unsigned ephemeral IPA179,956bytes,
SHA256c91343d090a052226b831550e7f8a04dcb2db98c71321ce802b4713ddcdf4b76,
not retained/delivered/signed/installed. Native app entry still unwired; AppIntents,
UI tests and actual models are NOT_RUN/unfinished, not covered by native compile.
All phone/signing/locking/ActionButton/endurance/renewal gates remainNOT_RUN.
OverallIN_PROGRESS.11future intent-router tests saved as uncompiled drafts only;
next invocation must prove RED before behavior. Six-run cap terminal, no seventh.
