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

T06.2.2.1 router exact-source full GREEN40100fd/run40017962923:
115XCTest,59Node,81repeatedTSAN,15native checks passed0failure/skip/races.
Tests-first and replacement-attribution RED/GREEN details:T06_TDD.md. Actual
OS adapter products compiled; native AppIntent perform/Simulator UI tests have
not yet run. Ephemeral IPA188,232bytes,hash433e98bd9eb28185cce7958dffdc723cb4516b420ef0e7b8054e4dbf4fa5b9a1,
not retained/delivered/signed/installed. All physical and inference gates pending.

T06.2.2.2 native app/content RED verified at81960fd/run40020680067:
37 actual app-hosted XCTest,24 previous passed,13 new failed82assertions,
0skipped; xcresult summary agrees. Actual iPhone17Pro/iOS26.2/x86_64 Simulator,
Xcode26.2/macOS15.7.9. Core115+59Node+81TSAN passed. Product/test-target
compilation passed; Xcode65 after behavioral failures, later15min job cancellation
during result processing. UI0executed, package0executed, no new IPA. Covered
native behavior implemented only after RED; exact-source GREEN pending. Additional
SDK mode probe and3UI contracts await execution. All realmodel/device gates NOT_RUN.

T06.2.2.2 component GREEN/UI RED at7c1ae7c/run40024451125:
38native app-hosted XCTest+115Swift+59Node+81TSAN passed0skip. Actual hidden
Stop SDK default background observed on iOS26.2. Actual UI3cases failed3assertions
on missing controls,0skip, with .xcresult confirmation; apps launch successfully.
Actual product/test-target compile passes; package0/no IPA. Next UI implementation
and unexecuted preparing-toggle regression remain unverified, not full CI GREEN.
All physical/realmodel gates NOT_RUN; no candidate delivered.

Continuation-05 terminal evidence at6b5fd0c/run40027966192: core115Swift,
59Node and81TSAN passed; native products compiled; native39 executed38pass,
one new preparing-toggle regression failed9assertions, zero skipped. Its local
repair695b99b awaits compilation/GREEN. Actual shared Activity Stop UI case
passed, terminal timer interrupted in teardown, Start case not run. The suite
has no aggregate/result-bundle verification, so full UI GREEN is NOT_RUN.
GitHub confirms15m maximum timeout. No packaging/new IPA. Details:T06_TDD.md.

R01 public visibility/cost change: explicit owner approval, historical path/blob
and document review, then live authenticated+unauthenticated API verification
of PUBLIC on23October2026 at21:59UTC. PASSED within that account-operation scope;
see evidence/T01_PUBLIC_REPOSITORY.md. Standard hosted macos-15-intel is free;
the remaining six-run/job/zero-spend limits are retained.

T09/T10/T08 are now prioritized parallel test-first work. Actual model-file hash
verification has been reported by the ASR agent; native app inference is NOT_RUN
and Windows recognition has not yet been reported. Do not infer feature completion.
Manual125minute iPhone endurance is assigned to the owner. Both required runs
remain NOT_RUN pending owner reports. No acceptance criterion has been waived.

Later parallel report: actual Windows sherpa-onnx/core1.13.8 CPU streaming
recognition executed on8.395seconds of original synthetic speech.21 evolving
partials, reference error2/21words, endpoint/reset/replacement checks passed.
This is desktop candidate feasibility, not native iPhone integration or quality/
endurance evidence. Ignored actual-result.json is available locally; sanitized
T10_CANDIDATE.md is being prepared by the agent. No production-ASR gate passes.

T08/T09 actual behavioral RED verified at9cb7639/run40032742242:153XCTest,116passed,37failed,77assertion failures,0skipped. Production implementations7ea1d71 await GREEN. T10native10-case test-first4c520bd/run40033589101 is pending; desktop speech evidence is candidate feasibility only. All device gates remain NOT_RUN.

T10actualRED4c520bd/run40033589101:10ASRcases11assertions0skip afteractualfixture/nativecompile. Full163cases148pass15fail18assertions. T08.1realSQLite15/15pass. T09installer18/23pass; coherentreplacementfixturecorrection preservesassertions. T11/T15/T16/T09.2/T17new39test-firstcases notyetRED; nofeature-completeclaim.

T11/T15/T16/T09.2/T17 RED b0cdd8b/run40034410554:202actualtests,153pass49fail104assert0skip; fixtureandnativeframeworksetupsuccess. All23modelinstaller casesGREEN. Threeagents/rootimplementedonlyafterpersistedRED; GREENpending. Addedlarge-converted-bufferregressionbeforefix; actualnewREDpending.

Actual2eaa5d6/run40035569538 verifies10/10nativeCPUASR,2/2positiveASR/SQLitecompositions andnotes/library/transport/export/CAFmapping. Combinedcore199/198pass/1fail/13assert/0skip;newlarge-bufferREDpreservedbeforelocalfix. Actualb5046Qwen4/2pass/2fail/4assert/0skip, semanticqualityFAILED. NativeUI/device/signing/endurance remainNOT_RUN.


7659a19/run40036438183 core SUCCESS:199XCTest+59scripts+85repeatedTSAN,0failures/skips/reported races. Actual large-buffer regression GREEN after2eaa5d6 RED;10CPUrecognizer and4live-session cases pass. Separate actualQwen4cases2pass2fail4assert0skip: semanticqualityFAILED. Nativejob120699362489 active; no current iPhone/UI/privacy/device pass inferred. Seven privacy cases are test-first, no policy implementation yet. P1 integration findings unexecuted: docs/drafts/T16Deletion/INTEGRATION_REVIEW.md. All physical/signing/renewal and both owner125minute gatesNOT_RUN. No retained artifact.


Terminal7659a19/run40036438183:199core+59scripts+85TSAN GREEN; actualQwen2/4pass (semanticFAIL). Both device/simulator app+extension compile. Newprivacyfixturetestbundles failtwoargumentlabels;0native/UI, NOTRED, no policy implementation. Correct labels now saved. Next test-first source224core/56native; fullbaseline/devices/retainedartifact stillpending.


Ownerpause 2026-10-23T23:14:31.300Z: no new validation pass. Test-firstcdf4a06/run40038154279 was live atpause; requireactualterminalsource-matched results onresume. Allagents/localwatch stopped; existinghostedbuildmayfinish. Lastknown199core/59scripts/85TSAN GREEN; realQwen2/4pass; no completednewnativecases/IPA/deviceevidence. Exactresumenextaction persistedinSTATE/BACKLOG.


Resumeactualcdf4a06/run40038154279:224core199pass25fail57assert0skip;56native41pass15fail40assert0skip;recordingUI3/3passandxcresultverified;realQwen2/4pass4assert0skip. New25core+8playback+privacyareactualREDbeforeimplementation. SimulatorindependentlycannotreportsourceCompleteclass;physicalprotectionremainsunverified. NoIPA/phonepass.


PhysicaloraclepreservedbyteexactSHA3abdf26b1175adc6919065931e9ed13193d5d9e2d45f01bbe73919e43bd37105 inPhysicalDeviceTests;7devicecases NOT_RUN (compilepending),5newSimulator-supportedrealFScasesunexecuted. ProductpolicyimplementationawaitsCI. Originalstrongclassassertionsnotweakened; nofakeattribute/class/lockpass. WindowsNode59/59passedunchangedafterinitialsandboxEPERM.


D699native54/53pass/1fixtureassert/0skip,8playbackGREEN;UI3/3GREEN;7physicalcompile-onlyNOT_RUN. Core228/222pass/6fail/8assert/0skip;25recovery/deletion/note/rename/formattercasespass. RawQwen4/1pass/3fail/6assert0skip. Nextlocalpath-hint+reservationrepairsfollowactualRED;newboundary/journal/playbackregressionsnotyetexecuted.


## 24 October 2026 — continuation08 run2 terminal evidence

Exact917844b016664251c545fb70106c50cfceb62694/run40071855360 FAILED after genuine behavioral RED: core241exe228pass13fail77assert(1unexpected)0skip; actualQwen4exe1pass3explicit-schema-notImplemented failures0skip; native57exe54pass3newplaybackfail24assert0skip with xcresult confirmation; recordingUI3/3pass and strict reporter/xcresult agree. Physical7 compiled for actual iPhoneOS, executed0/NOT_RUN. No package/retainedIPA. All10actualCPUrecognizer+4livecompositions+1actualHTTPS install/import/reopen/lease/recognition cases passed. Old8recovery and8playback pass; new3recovery/3filesystem/6schema and note timestamp equality are actualRED.

Only after reading/persisting RED: three bounded agents/root repaired journal rederivation/fullCAFdecode/captured-vs-timeline semantics; pending/global/scopedplayback; typed caller-schema actualmodel generation; hardlink guard; CAF parent preflight; exact SQLite-file privacy scope; canonical reservation timestamp. Existing assertions remain unchanged. GREEN remains pending. Next test-first work is automatic startup/deletion recovery and shared owner admission, plus actual-tokenizer chunk planning; no working new behavior precedes RED. Full summary/QA/interruptions/diagnostics/UI/artifact and physical/signing/renewal/endurance gates remain unfinished; project IN_PROGRESS.


## Source4 preparation after actual39d9eaa RED

Implemented startup/pagination6, sharedowner4 andchunkplanner6 only after their actual16 RED cases (74assertions) at39d9eaa/run40073883889. Actual canonical native tokenizer implementation follows five0-vs-real136/139/156/156/3700 assertions. The same source passes ALL4 original actualQwen semantic/model-size/cancellation cases unchanged; full5-case modeljobFAILED fromnewcounter/capacitycase. Positive unconstrained-string capacity generation failure remains archived/unexplained. Requirement-based capacity isolation uses either of two short caller enum labels, retains every count/budget/JSONString/cancel/unload and all4semantic assertions; no productionanswerliteral/prompt/modelchange. Evidence:T18_CAPACITY_FIXTURE_ISOLATION.md.

SQLite repair now preserves parent metadata entirely and protects onlyexactDB/sidecars; dedicated nativeWALfixture explicitly applies its owned-root policy with every strict assertion retained. HealthyCAF observer now decodes only declared boundedremainingframes, retaining all stricttruncation/readback/report assertions. No fixture acceptance was waived. New test-first source4 adds6extractivegrounding+6actualSQLiteFTS+2nativeAppstartup cases with no-op interfaces only. Expected269core/59native/5actualmodel/3UI;physical7unchangedcompileonlyNOT_RUN. Fullmapreduce/QA/persistenceUI/replay/pressure/diagnostics/signing/phone/endurance/renewal/artifact stillpending.


Terminal39d9eaa/run40073883889: ALL57native cases passed (includingall11playback), UI3/3pass, strictreportersandxcresultagree, physical7compiled/0executedNOT_RUN. Existing4realQwenqualitycasespass. FullworkflowFAILED fromnewcore16/counter/capacity andtwooldscope/fixtureassertions. Nativeproductinspection devicecasepasses; simulatorcasefailsbecausewithin-workflowDebugreuseallowsXCTesttoembedLocalMinutesAppTests.xctestbesidetheappex beforelateinspection. PreserveexactPlugInsallowlist andmovecompiledproductinspectionbeforeunitinstrumentation; doNOTignore/deleteunexpectedbundles. Actualnativejobtook~25.5min, sonextnativejobbounded35min(<45spec), samefreestandardpublicrunner/noextra infrastructure. NoIPApackage/retention/devicepass.


## Actual native app RED, 24 October 2026

Exacttest-first1f03e5259ead091c616eb4ce3c49f80d1af79018/run[40075611744](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40075611744), completednativejob120818174077:59app-hosted cases57pass2newfail15assertions0unexpected/skip; strictreporterandxcresultagree. StartleftstartupnotStarted/originalCAFmetadataunrecovered/nodurablereport. ClosedDBStartincorrectlyreachedmissing-modelpreflightandfailedownerinsteadofremainingidle/cleanupPending. Theseactualnativebehaviorfailuresauthorizeminimalservicesinitialize/start-togglegate/sharedregistryownerwiring. Bothdevice/simulatorbundlechecks2/2passafterstrictinspectionreorder. UI3/3passandxcresultagrees. Physical7compileonly/0executedNOT_RUN. Packagingnotrunafternewnativefailures;nocandidate. Noautomaticviewlaunch/replay/phonepassinferred.


## Source5 implementation ready after exact RED

Groundeddecoder/merge6, selected-meetingactualFTS6andnativeAppstartup2implementedonlyafter1f03e52actualassertions. Rootreviewedactualdiffs: preparedSQLbindings/UUIDscope/migrationstriggersbackfill, byte-exactquote/range/attributionvalidation+deterministicprovenanceunion/conflictlimits, sharedstart/togglegatewithStopbypass. Current-schema test expectationadvances2->3with documentedmigrationreason; oldv1/v2fixtures/data/equality/literalsearch remainstrict. No newactive tests source5: expected269core/59native/5actualmodel/3UI, plus59Node/TSAN/nativearchive onceGREEN. Windowsguide updatedfromcurrentofficial Apple/installer docs; no deliveredIPA/signing/phone/renewalpass. InactiveT12Signals3drafts uncompiled/NOT_RUN; onlyactivateafterfullsource5GREEN, sixthrunreservedfirstforneededrepairs. Fullmapreduce/QA/UI/ASRreplay/pressure/diagnostics/accessibility/artifact/physical gatesremainunfinished.


## Exact-source component GREEN at8b653cb

Source8b653cb8c33b7abd2d83e747b7bc404d1900f5f5/run40077503748 completedcorejob120823956509 SUCCESS:269XCTest+59Node+85ThreadSanitizer casespassed,0failures/skips/reportedraces; strictnamedreportersagree. All6groundeddecoder/merge and6actualSQLiteFTS3cases nowGREEN, includinglegacyv1/v2data preservation, selectedmeeting/operator isolation/rank/deletion postings, sourcequotes/ranges/nullableattribute/conflict/provenance validation. This is component evidence; actualfullLLMmapreduce/groundedQAandUIstillunfinished. Independentactualmodeljob120823956336SUCCESS5/5,0fail/skip,includingall4oldsemanticoraclesandrealcanonicaltokenizer/capacity/cancel/unload. NativeiOS/59cases/UI/package remainlive, so nofullworkflowGREEN/retainedartifact/deviceclaim.


Terminal8b653cb/run40077503748:269core+59Node+85TSAN+5actualQwen+59native+3UIand2nativebundlecasesallPASS,0skips/reportedraces; native/UIxcresultagreementsconfirmed. FullworkflowFAILEDonly13-casearchivegate:12pass,1negativeSimulatorfixturewrongerrorbecauseXCTestad-hocsigned/instrumentedthereusedDebugapp. Inputauditcorrectlyrejects_CodeSignaturebeforeplatformchecks; no guardshouldberelaxed. ActualdevicepositiveIPA/archiveCRC/hash/sourcecasepassesbuttemporaryoutputiscleanedandnocandidateisretained. FixharnessorderingbyrunningALL13archivecasesagainstpristinecompiledproductsbeforeXCTest; leavefinalephemeralpackagecreationafteralltests. Thisis2ndscopedorderingrepairforthesamewithin-runreusecause,withactualassertionRED,notpermission/toolfailure. Sixth/finalCIreservedforthisrepair;T12draftsstayinactive/noT12REDorbehaviorclaim.


## 24 October 2026 — continuation 08 terminal checkpoint

**IN_PROGRESS.** Exact source `db1b8d51c5ff72bf1d8abfd13f99a1da06a11e04` / [run 40079629180](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40079629180) completed **SUCCESS** at09:07:57UTC. Actual results:269core XCTest,59Node,85ThreadSanitizer,5actualQwen,59native iOS,3UI,2pristine-product and13archive cases all passed,0failures/skips/reported races. Native/UI strict reporters agree with xcresult. Physical protection:7compiled,0executed/NOT_RUN.

Bounded child components T17.2/T17.3/T18.1/T18.2/T19.1 are verified within their documented scope; T08.4/T08.5 are code complete pending device validation. Recovery/deletion/note/playback/privacy regressions now pass, but broad parent features and full summaries/Q&A/UI remain unfinished. See [the authoritative source/count/scope checkpoint](evidence/CONTINUATION_08_CHECKPOINT.md).

An unsigned12,632,611-byte IPA was verified on the ephemeral runner (SHA256 `e3eba563ccbd549987a43ed29c5da591fbf3a41cfa5357fc96e99372b0f721c0`), **not retained or delivered**. candidateArtifact remains null; ARTIFACT_STORAGE_HEADROOM_UNVERIFIED affects delivery only. All signing/extension/ActionButton/locked/offline-phone/renewal/protection and owner2x125-minute gates remain NOT_RUN.

Six of six runs are terminal. No seventh dispatch/re-run/code-triggering push this invocation. Reviewed T12Signals3/T13Metrics5/T18Pipeline5/T19QA4 drafts remain inactive, uncompiled and NOT_RUN. **Next:** Next bounded invocation: read required documents and verify Git/remote, terminal run40079629180 at db1b8d5, and zero-spend cost guard. Activate T12.2 three interruption/signal tests with minimal stubs and strict reporting, commit/push test-first, and prove hosted assertion RED before implementation. T13Metrics/T18Pipeline/T19QA drafts are inactive NOT_RUN and may be delegated within one branch and six runs. Current invocation is at six of six terminal runs: no run7, rerun or code-triggering push.


## Continuation09 test-first activation

Previous turn: progress, exact db1b8d5 full GREEN reverified. Activated17 new cases:13core+2native+2actualQwen, expected282core/61native/7actualmodel/3UI. Only minimal empty/no-op/throwing interfaces added; no new behavior before compatible assertions. Source push/RED pending. See [TDD evidence](evidence/T12_T13_T18_T19_TDD.md). Current bounded budget0/6 new runs; public standard compute guard reverified, no uploads or paid infrastructure. All physical gates remain NOT_RUN.


## Continuation09 implementation and next test-first source

Initial cc5049f/run40082088572 has actual17-case RED:282core269pass13fail90assert,61native59pass2fail20assert,7actual-model5pass2fail7assert,0unexpected/skip; UI3/3 and2product+13archive pass. All old regressions pass. Only after these assertions: implemented exact-epoch interruption/disposition and SDK monitor, bounded measured private diagnostics, nested grammar/grounded map-validate-merge pipeline, selected-meeting exact-quote QA. Actual semantic GREEN remains pending; no test/pin was weakened.

Independent review found early model-preparation interruption can strand coordinator and recorder state carries across meetings; both get new tests before repair. Added test-first generated storage4, heavy admission4, app observation3 and these2 regressions (one shared SPM/native). Expected next292core/65native/7actualmodel/3UI/86TSAN. Storage schema remains3, gate is a no-op, app signalCenter unused/flush no-op, both regressions unfixed until actual new RED. No app/model/privacy/device completion inferred. Budget1/6 used, first run terminal; no cancellation.


## Continuation09 third-source preparation

After actual source2 RED, implemented schema4 exact-BLOB generated storage/CAS, retained heavy-model cleanup gate, early preparation interruption, fresh metrics epochs and application-retained exact-epoch SDK observation. Original/new tests stay strict; only three current-schema expectations advance3→4 while historical1/2/3fixtures remain unchanged. QA receives one generic unknown-eligibility prompt repair; summary unknown unsupportedClaim gets only fixed synthetic bounded failure diagnostics, no guessed weakening.

New test-first slices: app-owned intelligence4core+1mandatoryactualQwen; app diagnostics3native; library3UI with DEBUG-only no-op isolated-root fixture hook plus two compiled Release/Debug boundary checks. New sources/targets only expose empty/no-op/throwing APIs until actual RED. The Release path has no fixture/environment override; normal shared services creation is delayed away from the DEBUG fixture branch. Source3 expected296core/68native/8actualQwen/6UI/86TSAN, plus59scripts and unchanged13archive checks. The actual-model case checks >=2.5GB real temporary headroom before owned imports; no downloads, skips or fake inference are substituted.

Important: no-op fixture failure is harness RED only. Seed real synthetic SQLite/CAF after that proof, then require actually reached Summary/Ask assertions before product UI code. App scenePhase control tests do not establish SwiftUI binding/periodic checkpoints/phone locking. No device or baseline completion claim. Budget2/6used, run2terminal. Next: push source3 and inspect exact compatible evidence.


## Correction from actual synthetic model output

Prior source2 positive-pipeline PASS / unknown-summary failure was incorrectly inferred from a catch-clause line number. It was not established. Source3c972600/run40086780531 actualjob120851237575 captures ONLY the first positive map: decision text omits its speaker prefix while quote includes it; task is rewritten/case-changed; due is invented2023-01-15 while source states onlyThursday. The decoder correctly rejects unsupportedClaim before the positive pipeline completes; the unknown-summary fixture is not reached. All five earlier flat/runtime/capacity tests and budget QA positive pass. Full nested summary quality remains FAILED/unproven; no field normalization or validator weakening is authorized. QA unknown attempt1 still produces raw supported_quote/undecided source (fiveassertions).

Actual model suite8executed5passed3failed7assertions(1unexpected)0skip. The new actual service test verifies/imports the pinned model but fails missing decisions array from the empty service stub; this is missing integration RED, not a native-loader pass. It now authorizes the real default off-MainActor loader with unchanged pinned identity/bytes and actual generation before durable output. Source3alljobs terminal; native tests were blocked by canary reader before execution.


## Continuation09 fourth-source preparation

Actual service orchestration/default CPU loader implemented only after source3 four-core + one actual composite missing-behavior RED. Loader validates reviewed manifest/size/SHA/runtime, hashes real bytes and constructs the actual runtime off MainActor; cancellation joins load/unload. No actual service GREEN yet. QA unknown handling: distinct generic classification examples attempt2, no forced status/rewritten output. Nested summary: first diagnosed repair puts evidence before claims and requires exact text/task case plus literal weekday dates; no answers seeded in grammar, no weaker validation or test change.

Compiled Debug canary reader now handles the exact documented NAME.debug.dylib code image when present (otherwise main executable), requires actual Mach-O headers and positive canary/launch mode, and prints bounded image metadata. Release app+extension exclusion remains unchanged and strict. SDK app metrics/fixture seeding remain no-op until their native/UI assertions execute.

Source3 actual model execution617.9seconds plus preparation/compilation nearly filled15minute job while the default service was still a stub. Real service adds two actual generations; bound that job at20minutes (<45spec), same free standard public runner, no uploads/payment changes. Other15/35minute bounds, six-run cap and one active run/branch unchanged. Current3/6runs terminal; source4 expected296core/68native/8actualmodel/6UI.


## Source4 portable GREEN; native harness still prevents assertion execution

Exact `18f162169a716f0bede99f9240f71cccd6568815` / [run40089155104](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40089155104), terminal corejob120858086927:296executed296passed0fail/skip,59Nodepassed,86ThreadSanitizerpassed0reportedraces. All four app-owned intelligence orchestration cases are GREEN. Actual default-loader/model semantic quality is still running and is not inferred from these boundary cases.

Nativejob120858087063: Release product/build, original product2, compiled fixture-boundary2 (strict Release exclusion and actual Debug positive) and archive13 stages pass. Both app-unit and UI xcodebuild test steps fail compilation at the unchanged original owner identity assertion, RecordingSessionOwnerTests.swift:1242, because LocalMinutesApp deferred shared composition removed application. Zero native/UI cases execute: no metrics or fixture RED, no repair to their no-op APIs. Minimal harness compatibility repair restores application as a lazy computed shared accessor and uses it only in existing non-fixture branches. No default Services is evaluated from the isolated fixture branch. Physical7 compile-only/0executed remain NOT_RUN.

Review adds one test-first actual SQLite blocked-commit cancellation regression; production save cancellation is unchanged pending its actual RED. Three app shared-heavy-admission composition cases are being activated with nil/pass-through seams only. Four of six CI runs used; source4 actual-model job must terminate before next push.


## Source4 incomplete actual-model suite and terminal run

Exact18f162169a716f0bede99f9240f71cccd6568815/run40089155104 completed FAILED at11:35:50UTC. ActualQwenjob120858087150 conclusion cancelled at configured20minute boundary; no agent cancellation or superseding push. Only three cases complete: tokenizerPASS413.220s; default real serviceFAILgenerationFailed344.789s (catch54 does not prove which generation/cause); QAFAIL114.161s with5positive-budget assertions plus its two actual outputs. QA attempt2 over-refuses the known42000budget: raw insufficient_evidence/none/empty. The unknown-owner raw refusal assertions pass this run, but the overall semantic contract fails. Do not normalize/force answers or mark QA complete.

Actual nested pipeline starts11:33:07 but no completed map/case is available before cancellation11:35:07. Four old runtime cases never start. There is NO complete XCTest aggregate or8-case result; do not count interrupted/unstarted cases as passes, failures or skips. Partial observations:3completed/1pass/2fail/6assertions(1unexpected),1interrupted/4notstarted. No new pipeline semantic repair is justified by this incomplete case.

Retain every mandatory model/quality oracle; actual job bound increases20→30minutes (<45spec) based measured344.8+413.2+114.2seconds before the remaining5cases. Same standard public macos-15-intel, no uploads/cache/cost. QA final third bounded semantic repair is under review; original status domains, all source IDs, unconstrained quote and raw actual-model assertions remain fixed. Current4of6runs terminal; two remain.


## Fifth-source test-first preparation

Added test-first T17.5: two portable actual owner/CAF/usage/HeavyModelAdmission composition cases and one native default-services identity case. Production bridge is pass-through, Services heavy/intelligence fields nil, and owner does not invoke the new async finish seam. Existing owner assertions unchanged; static independent review corrected only the new harness later-start directory so actual CAF does not collide with its own RED cleanup. Core/native/TSAN strict reporters require the exact new names.

Added one actual blocked-SQLite-writer cancellation regression to T18.5; production commit cancellation remains unfixed. A real second BEGIN IMMEDIATE holds the save, explicit cancellation/draining is observed before rollback releases the writer within1000ms timeout, then unchanged acceptance requires no saved row/visible result, cancelled status, original notes/transcripts/model preserved and resources released. No mocked persistence or delete-after-save workaround. Original four cases unchanged.

Source5 expected299core/71native/88TSAN/8actualmodel/6UI, plus59Node/2product/2compiled-fixture-boundary/13archive. New source5 RED is pending; tests in source4 native/UI never ran and remain no-op. Lazy LocalMinutesApp.application accessor compatibility preserves the original ownership assertion and avoids default storage access from the isolated fixture branch.

After source4 actual QA over-refusal, final bounded attempt3 replaces long examples with balanced generic requested-fact policy. Both statuses/full source IDs/unconstrained quotes and raw actual inference assertions unchanged. No fourth blind QA repair is authorized. Summary pipeline itself is unchanged; DEBUG runtime failure-only diagnostics record literal stage and numeric counts, never text/path/token IDs or retained partial output. Actual default-service fixed-synthetic test labels only summary/question-answer/persistence stage in catch, retaining the real default loader and every oracle. All static diff/JSON checks pass; hosted compile/results are pending.


Fifth exact test-first source `0181b311abedb3c32745b015be64d6e7c777032b` pushed/remoteverified; [run40091141417](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40091141417) live, ordinal5/6. New cancellation/shared-app gate behavior remains absent. Native metrics/fixture remain no-op until reached behavioral assertions. Full real-model suite and final QA attempt3 pending; no extra source push while live.


## Source5 actual regression RED and owner delivery priority

Exact0181b311abedb3c32745b015be64d6e7c777032b/run40091141417 corejob120863889214 terminal:299executed296passed3failed30assertions0unexpected/skip. All296prior cases pass. New blocked real SQLite commit cancellation fails4assertions: saves after pre-commit cancellation, returns completed/published row, row survives reopen. New actual-owner shared-heavy-gate cases2 fail26assertions: no ASR gate reservation and held summary/QA still admits recording/OS/preparation/meeting claim. These are genuine compatible behavioral RED, authorizing only their bounded repairs; native default wiring/metrics/fixture RED still pending.

Owner raised elapsed runtime/cost and explicitly superseded per-small-change testing cadence: prioritize a downloadable MVP, batch meaningful fixes and split model-quality jobs. Baseline acceptance/device gates are unchanged; MVP delivery must honestly mark summary/QA incomplete. A30–60minute conditional first-package estimate was given; a firm time-cap/pause preference is pending. No further full test/repair loops should be launched after the bounded delivery checkpoint. Five of six runs used, sixth reserved for one batched build/package.


## Owner-directed MVP delivery and testing stop

Owner explicitly selected up to60moreminutes for an MVP package then pause, and instructed: “Do not spend more time on Testing, I need MVP.” Further test work stopped. Run40091141417 was cancelled at owner request (terminal12:00:19UTC); its already completed299core/296pass/3fail/30assertions remain recorded. Native/model remainder has no completion claim. User instruction supersedes per-change test cadence for this bounded delivery only; no oracle or baseline/device gate is weakened or deleted.

Preserved unverified WIP after actual core RED: concrete per-request SQLite commit admission in3files and portable owner/heavy admission in2files. No GREEN was run; default App gate/metrics/fixture remain nil/no-op. These WIP changes are excluded from the delivered app.

MVP app source is last fully passing db1b8d51c5ff72bf1d8abfd13f99a1da06a11e04/run40079629180. Build-only mode compiles its real iPhone Release app+embedded extension, packages/checksums via existing audited packager, and uploads only to an owner-only UNPUBLISHED draft release. Official GitHub release storage/bandwidth documentation checked24October (https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases): avoids metered Actions artifact storage; no paid infrastructure or publication. Current auth repo/workflow scopes verified without exposing credentials. Full validation jobs remain saved/manual; no tests execute in MVP mode.

Owner time cap recorded conservatively from11:52:42UTC: hardstop12:52:42UTC. Target35–45minutes from agenda, allow queue margin, pause after package/handoff or at cap with precise blocker. Scope: record/live local ASR/history/notes/playback/search/text-Markdown export. Full summaries/Q&A, onboarding/accessibility/privacy/security/recovery completeness and all physical gates remain unfinished.


## MVP build-only run dispatched

Workflow/WIP source3e25aae6117b9cad9d0251bded2f345b3155bdcf pushed and remoteverified. Sixth/final [run40092475736](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40092475736) compiles/package ONLY reviewed APP source db1b8d51c5ff72bf1d8abfd13f99a1da06a11e04. Source distinction is explicit in job guard and bundle stamp. All three validation jobs excluded by owner-selected mvp mode; no XCTest/Swift test/model suite executes. Run already reached actual iPhone Release app+extension compilation. No new test-cycle dispatch is authorized.

Unpublished draft release422706783/tagmvp-preview-db1b8d51c5ff targets exactlydb1b8d5; owner access/draft flag verified. Windows guide uploaded successfully. Package step uses existing native packager to exclude secrets, models, user media/data and signing material; upload verifies exact draft/source before writing assets. Same free standard public runner,25minute bound, no Actions artifact upload, paid storage, Apple credentials or public release publication.


## MVP delivered; owner-requested pause

Actual build-only run40092475736 SUCCESS at12:07:42UTC. Workflow3e25aae checks out reviewed appdb1b8d5; no new tests execute and all validation jobs are explicitly excluded. Real iPhone arm64/iOS18+ app plus embedded Live Activity extension compiled with Xcode26.2/SDK26.2. Unsigned IPA 12632630bytes, SHA256 `65d90c31a1109ee8291d1870b096dddb7cde1330962dd9e9ad8d557a5f96a70d`, retained as unpublished draft release422706783 and downloaded locally; local bytes/checksum/manifest/GitHub digest MATCH. See [delivery evidence](evidence/MVP_DELIVERY_2026_10_24.md) and [Windows guide](MVP_INSTALL_WINDOWS.md).

Local directory: `build/delivery/MVP-40092475736`. Includes IPA, checksum, manifest, guide and build notes. No model/user/signing data. MVP source already implements recording/localASR/history/notes/playback/search/text-Markdown export; summaries/QA and full baseline unfinished. Full candidateArtifact remainsnull, separate mvpArtifact retained. No physical signing/extension/ActionButton/locked/offline/125minute/renewal/protection pass.

Owner explicitly requested pause after MVP within60minutes; delivery finished before conservative12:52:42UTC cap. Work is checkpointed and no further tests, CI, feature edits or automatic continuation are authorized before explicit resume. Preserved branch WIP remains unverified/excluded from delivered IPA. Project remains IN_PROGRESS.


## Paused for workstation restart —24October2026

Owner explicitly requested pause, then confirmation. All3subagents were interrupted. Resumed batch made no CI/test dispatch and no new IPA; last MVP run40092475736 remains SUCCESS. Five source files contain uncompiled WIP: IOSRecordingSignalMonitor, IOSCaptureHardware, RecordingSessionOwner, LocalSummaryRuntime, LiveTranscriptionSession. Low-space/route/thermal/fresh-engine/native logging edits have no compile or physical evidence. Summary/Q&A UI/default-services work was still in inspection and has not been implemented in this resumed batch.

State/backlog saved with exact next action. No background build/test/agent work continues. Resume only on owner request after reboot; finish missing app functionality and integrate/review this WIP before one batched build.


## Summary/Q&A functional batch resumed24October2026

Owner explicitly resumed8f6fc1f and requested finishing summaries/Q&A without polishing or repeated test runs. Required files, clean saved Git state/auth/PUBLIC-ADMIN/HTTPS remote and terminal previousMVP build were rechecked. ExistingMVP stays unchanged. No new scaffold, schema/model/pin/test-oracle replacement or paid resource.

ActualAppServicesnowretainsoneHeavyModelAdmission, recording bridge and realdefaultpinnedIntelligenceSession; owner bindsbridge and exact monitorstorageDirectory. Added selected-meeting Summary/Ask controller/view: separately persisted generated originals, serializedrevision-CAS editable summary, actualGenerate/Ask, selectedsavedQA, strict original-sourcequotes/timedplayback, provenance/export, scopedcancel, truthfulmissing-model/busy/errors. Automaticlibrary startup and backgroundcancel wired. Newcaptureaction drainsLLM beforeASR; navigationplaybackcleanup usesexistingrequest-scopedownership.

Summary output defensivebudgeting keepsactualcanonicaltokenizer andallmaps/validation/merge, capsdefaultmap2sources andcategoryitems≤sourcecount,1citation/item. Priorfailurecause remainsUNKNOWN; this is not a measuredtoken-exhaustionrepair. Existing128map/128item andlongsegmentlimits remain materialforlongmeetings; no silenttruncation or full2hsummaryqualityclaim. Notes remaincontextonly. FinalQAattempt3 unchanged, no fourthblindpromptedit. All original tests/oracles/modelpins remain unchanged.

Oneend-of-batch features workflow will compile/packageactualnewiPhone source and observe3actualmodel flowsonseparatestandardpublicmacOSjobs (service,summary,questions). No per-change/fullregressionloop. Outputsremaininunpublishedownerdraft; no Actions artifact storage or public release. Implementation exists; compile/model/nativeUI/physical resultsarepending.


## First functional-batch actual result

Exact1eeb403f864d5532b8046bf4e8c270f5614399bb/run40098679075: iPhone app+extension build/packageSUCCESS; unsigned12929041byteIPA retainedunpublished, SHA256acd9ff543dfcd264023e0712c8c6ca4d46b3bc20512db13a31b2aab1a74c2fcc. Actualsummaryjob120886163092:1caseFAILunsupportedClaim/1assertion0skip88.333s. Actualservicejob120886163115:1caseFAILunsupportedClaim atsummary/1assertion0skip123.126s. No semantic GREEN claim.

CapturedfirstpositiveJSON has exactsource summary/decisiontext, and action task equals the entire quote“Leo: I will write the guide by Thursday.” withcorrectownerLeo/dueThursday. Existingvalidator strips labelthen searches the fullquotedtask inside the body, rejecting a supported complete quoted commitment. Narrowvalidationrepairmayacceptthisshapeonlywithexactlabel,explicitIwill,ONESENTENCEboundandsametaskdeadline; no outputrewriting,answerinjection,wrongowner/dateguardweakeningortestoraclechange. Unknownsummaryfixturehasnotbeenreached. Questionsjobpending.


## Q&A observation and bounded functional repair

1eeb403/run40098679075 terminalFAILED at13:39:02UTC. Questionsjob120886162871:1caseFAIL5assertions0skip130.030s; knownbudgetrawinsufficient_evidence/none/empty, unknown-ownerrefusalassertionspass. Thisconfirms3rdpromptattemptfailed;blindpromptretriesstop. AppbuildSUCCESSisnotmodelqualitysuccess.

SummaryvalidationrepairacceptsexactwholequotedSINGLEfirstpersoncommitmentonlywithmatchingownerlabelandIwillbody;duedate/source/range/provenance/one-sentencechecksremain. Neitherrawoutputnornegativeoraclesarechanged. QAindependentretrievalprecisionrepairusesboundedownershipwordfamilies,meaningful-termcoverageandtop1sourcefortheone-quoteAPI. Original3fieldstatus/ID/freestringschema,prompt,modelandalltestsremainunchanged. Contextpollutionisahypothesis,notaprovenrefusalcause.

Oneboundedrepairbuild+failed-flowverificationwillobservebothchangesinparallel;nofullsuite/per-change/4thpromptloop. Exactfunctional/model/longmeetinglimitsremainpendinguntilactualevidence.


## Bounded repair actual result; model-quality blocker

Exact588834b68876e94a6cffe5963fe0a875d1f69315/run40099854249 completedFAILED13:59:51UTC; actualiPhonebuildSUCCESS. Summarycase1FAIL196.566s: positivefixturevalidatedanditsassertionspass (secondnegativefixturecaptured), butunknownmodeloutputparaphrasesReviewthechecklist,ownerunassigned,duetheNoowner/nodeadline sentence;correctlyrejectedunsupportedClaim. No nullable-fieldnormalizationorvalidatorweakening. QAcase1FAIL114.555s unsupportedEvidence; rawfailedcallnotcaptured,specificquestionstageunproven. Actualdefaultservicecase1FAIL313.242s unsupportedClaim atsummary. Allsemanticoracles/pinsareunchanged. ModelqualityremainsFAILED,notcompletedbyUIcompilation.

No furtherprompt/testloop. Ownerwasaskedonetimewhethercompareonecompatiblelocalmodelwith30mincaporstopmodelwork, duetothenorepeatedtestrunconstraint. Awaitreplybeforecandidateexperiment;elapsedtimeisnotapproval. OfficialMicrosoftPhi-3-mini-4k-instruct-GGUF(MIT,2.2GBQ4asmodelcard)identifiedaspossibleread-onlycandidate,notdownloaded/pinned/evaluated/recommendedasworking. https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-gguf

Inputpackingreviewremovedartificialtwo-sourceinputcap: actualcanonicaltokenizercountsnowpacklongerchunks;output≤2/category,1citationand128map/itemboundspreserved. Existingtwo-sourceactualfixtureshaveidenticalprompts/chunks/schema,nomodelsemanticrepairclaimfromthischange. Finalcompile/package-onlymodeexcludesallmodel/fulltestjobs. ThispreparesanupdatedUIpreviewwhilequalityblockerremains;nomoreinferenceexperimentswithoutownerchoice.


## T07 iLoader installation update — 24 October 2026

The owner reports successful main-app installation with iLoader and explicitly
selected it for all installation/renewal references. T07.1 documentation/copy
migration is complete; T07 remains IN_PROGRESS. Previous installer error -80046
and alternative research are superseded for the current setup; original records
remain in Git history. No failure was relabelled as an iLoader failure.

Project instructions/configuration, app renewal copy, Markdown/Word brief,
source register, Windows guides and local delivery guides use iLoader. The
installed IPA remains unchanged; new app copy requires a future build.
No new tests/CI/builds or IPA from this invocation. JSON/reference/whitespace
checks validate the edit, without claiming native or physical results.
All extension, Action Button, locked/offline, endurance, renewal and protection
device gates remain pending. Other model-quality/development state is preserved.
Next T07 action: record installed build/phone/iOS/tool version, then check the
Live Activity status and Stop control during a short recording.
[Evidence](evidence/T07_ILOADER_INSTALL_2026_10_24.md).

Reference sweep, three JSON parses, whitespace, Word XML/style preservation
and unchanged two-IPA checksum checks pass. Word visual review is pending:
the packaged renderer cannot find LibreOffice and Word is not installed.
No new commit/push; concurrent workflow/model-test work is left untouched.

## Summary/Q&A batch handoff

App screens/shared real-model wiring, durable edits/answers/citations/cancel/export are implemented. Final d6a3293/run40101392948 compile/package SUCCESS,0tests; preview downloaded with matchingSHA256. **Model quality remains FAILED**: current Qwen1.5B unknown-owner/date, default-service summary and QA evidence cases still fail under unchanged oracles. No full/physical acceptance claimed. Original MVP unchanged; preview schema4 prevents old-schema3 binary rollback. See [exact evidence](evidence/SUMMARY_QA_BATCH_2026_10_24.md) and [usage](SUMMARIES_AND_QA.md). Model experiments stopped; awaiting owner choice for one30minute-compatible-model comparison or stop.

| T18/T19 single Phi-3 candidate | Two nested summaries + two selected-meeting questions, actual CPU | Prior Qwen failed; separate comparison | [Pending candidate run](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40104505380) | 1a999b661ef68d4082b0a811d03ec40ef3180b7b | Hosted macOS, pinned b5046/Phi-3 | FAILED overall; Q&A2/2 PASSED | Summary preflight error; two actual generations only; no default/phone/whole-feature pass |

| T18 candidate missing summaries only | testActualPinnedPhi3ComparesTwoSummariesWithReviewedRevision | First-run harness provenance error preserved | [Eight-minute bounded run](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40105186439) | 6d914fe0117964c7019a71d5b9332c9dba3758b4 | Hosted macOS, same pinned Phi/b5046 | NOT_RUN/unverified (job cancelled) | Compile130.24s PASS; no completed case/stage, no semantic outcome inferred |


| MVP1 selected runtime integration | Real installed selected Whisper/Phi | Actual RED run40111205922 | GREEN run40114656922: Whisper live1PASS16.771s, Phi defaultservice1PASS571.357s | d0fe973b0045d5fb11c3dc0a33bd62ab5c39a991 | Hosted macOS CPU, no skips | Partial GREEN | Native metrics2/3 pass; resource reader RED; package/phone gates pending |


| T24/MVP1 model-choice delivery | HF/cards/resources/install/remove/independent Equip + real selected models | Preserved multi-stage RED in MODEL_CATALOG_AND_SUMMARY evidence | [run40117673355](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40117673355):137 focusedPASS/0fail/skip + actualdevicepackage | 4aec851bb1c83ec1a9acb8f48074db79dcdd8a23 | Hosted macOS/iOS26.2Simulator; Windows checksum | CODE_COMPLETE_PENDING_DEVICE | UnsignedIPA delivered; fullbaseline/MVP2/MVP3/phone evidence pending; details evidence/MVP1_MODEL_DELIVERY_2026_10_24.md |

| MVP2 reliability primitives |37 actual cases, SQLite/CAF/real speech | run40119556084:3PASS34FAIL169assertions0skip before implementation | run40121343041 at6adcc04: compile failure,0executed | Native macOS SDK | IN_PROGRESS | First SDK lock-binding repair and new34 integration contracts prepared; no GREEN or device claims |

| MVP2 integration actual RED | Default app7 + actual speech10 + actualPhi1 + relatedportable269 | [run40124109356](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40124109356) | 0348c1c31806d3b88120cc9f61ac449fa290ef5a | macOS/iOS26.2Simulator;0skip | IN_PROGRESS | Speech10PASS; portable28casesFAIL, actualPhi1FAIL, native7FAIL20assert. Repairs unverified; no phonegate claimed |

| MVP2 native Parakeet decoder | RealpinnedCoreMLv2/CPUOnly, licensedaudio | 4640aec/run40126813965:6FAIL beforebehavior | [run40130455240](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40130455240): direct5PASS20.762s; equip/replayactualRED16assert; selectedLiveFAIL | 048481c8c51bd097ffac6b535cd4101470acf3fd | StandardAppleSiliconmacOS;0skip | IN_PROGRESS | Nativebackendworks; repairedappadmissions/metadata needexact-sourceGREEN; noMVP2IPA/deviceclaim |
| MVP2 data/diagnostics | Relatedportable281 + nativeapp10 + speechrecovery10 | PreservedR1/R3/R4 | C6:277portablePASS,10appPASS,10speechPASS;4fixture-pathFAIL | 048481c8c51bd097ffac6b535cd4101470acf3fd | macOS/iOSSimulator | IN_PROGRESS | Snapshot5/archive12/installer5/transfer7/endurance5/resume4PASS; correctedfixture andfinalsourceverification pending |

| MVP2 candidate C7 | Actual installed native speech, library, app and device build | Prior RED retained | [run40131735329](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40131735329): portable280/281PASS, native6/8PASS, app10PASS, speech recovery10PASS; IPA packaging PASS | 36f9c7f23a5e3967cb3cae26d28caec5c8c74de5 | Standard macOS/iOS simulator; no physical evidence | IN_PROGRESS | Three actual cases fail; draft IPA exists but is not MVP2 delivery. Installed-path/native and archive repairs pending. |

| MVP2 delivered / T25 native engine | Real installed Parakeet live/Equip/replay; library durability; device package | R4/R6/R7 actual RED retained | [run40132528745](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40132528745):309focusedPASS/0fail/skip + arm64app/extensionIPA | 35c7cefb946af188f5cc09858dca4ab180d72eab | Hosted macOS/iOS simulator + Windows checksum/ZIP/plist/Mach-O | CODE_COMPLETE_PENDING_DEVICE | IPA SHA21b6feaf59824a2eb6ab92de68fdb07fc9eb36449ba58337b41771ad986ac7f6; guide MVP2_GUIDE.md. All physical gates and full baseline release gate remain pending. |

| MVP3 pause checkpoint | Progress/private-root/latest shortcut | C9 portable4FAIL15assert; nativecompile0tests | [C10 run40134199884](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40134199884) confirmed live before owner pause | 8edff56a96f051587d727812239937ccba51b9a5 | Hosted macOS/iOS simulator | IN_PROGRESS | No C10 outcome inferred; resume same handle/budget4of6. Owner paused to apply modelsetting; all physicalgates pending. |

| MVP3 C10 actual result | Progress and native product contracts | C9progressRED retained; C10nativeRED actual | run40134199884:11portablePASS,1nativeprogressPASS;8nativeFAIL28assert0skip | 8edff56a96f051587d727812239937ccba51b9a5 | macOS/iOS simulator | IN_PROGRESS | Native privacy/latestshortcut repairs awaitGREEN; newUIa11y prepared; no physicalclaims. |

| MVP3 C11 ASR build | Same-revision source ASR without unusedTTS | d6 actualIPARED retained | run40135661801: nativeframeworkSUCCESS, CRC/13hashes/5arch verified; native product0tests compilefailure | b26b89dda04c49c0742417179f79b1c2aa762654 | StandardmacOS/Xcode26.2 +Windowsreceipt | IN_PROGRESS | Actualapp linking/inference/IPAclean-symbolgate pending; firstNotificationbridgecompile repair prepared. |

| MVP3 C12 integration | Current package/runtime/product gates | Current0executed: invalidPackageDescription5.9; no behavioralRED | run40138806203 failed before currenttests; old8edLibraryharness3FAIL64.008s | 14ff749a2bd8678b6523cf377b6695283513a76e | StandardhostedmacOS | IN_PROGRESS | Firsttools6.2repair prepared; no nativequality/packageclaim.6of6batchlimit; nextboundedverification required. |

| MVP3 resumed build and remaining RED | CPU policy/status + real ASR corpus | run40172670154: core460/458PASS/2FAIL/4assert/0skip | GREEN pending; actualASR corpus2PASS | b3f4e61181bdf81a0ab876e5defc3240513b7927 | HostedmacOS/Xcode26.2 | IN_PROGRESS | Native/Phi active; physical NOT_RUN. See evidence/MVP3_DELIVERY_2026_10_25.md. |

| MVP3 focused native/UI RED | Metadata/citation/privacy + requiredscreens/a11y/transcript visibility | run40174152880: native13/8PASS/5FAIL; UI7/2PASS/5FAIL; schema16/15PASS/1FAIL;0skip | Combinedrepairs prepared, GREEN pending | a1308e9283be1d89aa3025ca88fb8a0a43c7974d | HostedmacOS/iOS26.2Simulator | IN_PROGRESS | Latestshortcut/progress/status scopedPASS. Actual finalmodel/native/packagegate next; physicalNOT_RUN. |

| MVP3 delivered functional gate | Models/recording/recovery/library/summary-QA/privacy/a11y/package | Auditable RED in MVP3 delivery evidence | run40181776855 SUCCESS:25Swift+46scripts+100native+10UI+13package+2contracts+2fixture+3hygiene;0fail/skip | 880d3dcd2e21f79e6435ec134279cad192e7435d | HostedmacOS/iOS26.2Simulator +independentWindowsIPA | READY_FOR_DEVICE_VALIDATION | IPA14855799B SHA256b0bc6e2d618f742ab257b85bc81765b25ca34b94b3c9d09fe33656b7aea1f5c9; ownerqualitymanual and allphysicalgatespending. |

| MVP4 T12.1a prepared | Owner storage-metadata export | 15tests+minimal seams prepared; actual RED pending | NOT_RUN | Pending test-first commit | Hosted macOS/iOS required | IN_PROGRESS | No production inspector; no device or quality PASS. |

| T12.1a Core actual RED | Bounded actual metadata/read-only privacy | e9b1701/run40184895367 job121143513139:7executed,2PASS5FAIL28assert0skip | Implementation pending GREEN | e9b1701cb81e0fb5f0a84f608f7c7598cd917449 | Hosted macOS | IN_PROGRESS | Native/UI RED pending; no physical claim. |

| T12.1a native/UI actual RED | Guarded owner metadata report and Prepare/Share screen | e9b1701/run40184895367: native7/2PASS5FAIL18fail(3unexpected), UI1FAIL1assert;0skip | Implementation reviewed; focused GREEN pending | e9b1701cb81e0fb5f0a84f608f7c7598cd917449 | Hosted iOS Simulator | IN_PROGRESS | Original phone protection tests NOT_RUN. Build5 metadata only; no model quality work. |

| T12.1a Core GREEN | Actual bounded storage metadata | R7 7cases/5FAIL28assert | R8run40186443609 Core7PASS0fail/skip0.422s +46scriptsPASS | 3273fb20401023fd8095d36c7007923aa42d7bca | HostedmacOS | IN_PROGRESS | Native/UI/package still live; no physical claim. |

| T12.5/T15.2/T18.7 prepared | Final functional gaps from audit | Tests5portable+9native+3UI prepared; actualRED pending | NOT_RUN | Pending test-firstcommit | HostedmacOS/iOS required | IN_PROGRESS | Emptyseams only, no new inference/modelquality. |

| T12.1a native/package partialGREEN | Actual privacy report and guarded reads | R7actualRED retained | R8native15PASS0fail/skip1.280s; actualdevicebuild5 +3hygienePASS | 3273fb20401023fd8095d36c7007923aa42d7bca | Hosted iOS Simulator/devicecompilation | IN_PROGRESS | UIstilllive; localbytespending; finalMVP4gaps testsfirstb05e7d9pushed. |

| T12.1a storage report final GREEN | Owner-accessible observed metadata and explicit sanitized sharing | R7actualRED preserved | R8run40186443609:7Core+46scripts+15native+3UI+3hygienePASS;0fail/skip; localbytes/pins/noticesPASS | 3273fb20401023fd8095d36c7007923aa42d7bca | HostedmacOS/iOS Simulator +WindowsIPAverification | CODE_COMPLETE_PENDING_DEVICE | Phone17Pro/iOS27.0.1 ownerreported; no physical test result. FinalothergapsR9live. |

| T12.5/T15.2/T18.7 actual RED | Memory cleanup, complete search/history, saved-answer editing | R9run40188134859:5portable/4FAIL14assert;9native/8FAIL20assert;3UI/3FAIL3assert;0skip | Implemented/reviewed; finalGREENpending | 3df777c9cc4beccf652294874e52f889bb9204c3 | HostedmacOS/iOS Simulator | IN_PROGRESS | b05testfirstcode unchanged; build6 finalgate next. No physical/inference-quality claim. |

| MVP4 final candidate | All changed functionality and related regressions/package | R9actualRED3df777c retained | run40190643613 live; GREEN/IPA pending | 36bf6f4c8726fbc5d2efbfa4f740ef4031457233 | HostedmacOS/iOS target | IN_PROGRESS | Build6draftreserved; source716feaeimplementation; no phone/qualityclaim. |


## MVP4 build6 focused UI retry — 25 October 2026

Owner reports iPhone17Pro/iOS27.0.1; no installed-build or Live Activity Stop result. Build6 app source36bf6f4c8726fbc5d2efbfa4f740ef4031457233 has independently verified local IPA14982180B/SHA25608c00c22c0edd446ec0656a5695d9b05e20b7d1cc497f9186f57ec99cf00f2e0. R10/run40190643613 is terminal FAILURE:76portable+46scripts+116native+7UI+3hygiene+2compiledfixture checks passed, one answer UI case failed2 original notes/transcript assertions after wrong-way test navigation;0skip. Harness-only81fbff3 repair retains all assertions and adds a visible top-anchor precondition. Existing focused R11/run40193408469/job121169039791 is live: exact app checkout36bf, separate harness81fb, zero production diff guard, only one answer UI case. No new IPA, quality benchmark, model weights or passed-suite rerun. Next: Observe existing focused run40193408469/job121169039791; verify APP_SOURCE36bf and TEST_HARNESS_SOURCE81fb with zero production differences, then the single answer-edit/navigation/relaunch UI case. No IPA rebuild, passed-suite rerun or model-quality benchmark. On PASS record composite evidence (original run40190643613 remains FAILURE), deliver build6 and updated guide/checklist. Owner iPhone17Pro/iOS27.0.1 facts are OWNER_REPORTED; actual phone gates NOT_RUN.


## MVP4 development delivered — final focused GREEN

R11/run40193408469 is terminal SUCCESS at workflow/harness81fbff3a1bdf4ed17b757dd96d97486d9485254f. Actual logs record APP_SOURCE36bf6f4c8726fbc5d2efbfa4f740ef4031457233 separately, zero production differences, and one actual AnswerEditingUITests case PASS/0fail/0skip in190.795s. Every prior assertion remains; original notes/transcript now checked after the visible top-anchor precondition. R10/run40190643613 remains FAILURE in history; its76portable+46scripts+116native+7UI+3IPA-hygiene+2compiled-fixture PASS results combine with R11 for the exact unchanged app source. No full suite, model quality, weights or new IPA rebuild. Build6 IPA14982180B/SHA25608c00c22c0edd446ec0656a5695d9b05e20b7d1cc497f9186f57ec99cf00f2e0 is delivered with guide/checklist/manifest/receipts. T12.1a/T12.5/T15.2/T18.7 CODE_COMPLETE_PENDING_DEVICE; overall READY_FOR_DEVICE_VALIDATION, not VERIFIED_COMPLETE. Requirement audit R01–R12 records evidence limits and remaining phone gates. Exact next action: Owner phone validation on delivered build6: confirm installed version/build and a short actual recording whose Live Activity Stop saves the meeting; then checklist offline chosen models, Action Button warm/locked continuation/cold-start, two125min passes with120min locked each, storage protection and in-place renewal preservation. Device iPhone17Pro/iOS27.0.1 is OWNER_REPORTED only. No safe remaining development change identified by requirement audit; do not rerun passed suites or model-quality benchmarks while awaiting real evidence.
