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

Groundeddecoder/merge6, selected-meetingactualFTS6andnativeAppstartup2implementedonlyafter1f03e52actualassertions. Rootreviewedactualdiffs: preparedSQLbindings/UUIDscope/migrationstriggersbackfill, byte-exactquote/range/attributionvalidation+deterministicprovenanceunion/conflictlimits, sharedstart/togglegatewithStopbypass. Current-schema test expectationadvances2->3with documentedmigrationreason; oldv1/v2fixtures/data/equality/literalsearch remainstrict. No newactive tests source5: expected269core/59native/5actualmodel/3UI, plus59Node/TSAN/nativearchive onceGREEN. Windowsguide updatedfromcurrentofficialApple/Sideloadlydocs; no deliveredIPA/signing/phone/renewalpass. InactiveT12Signals3drafts uncompiled/NOT_RUN; onlyactivateafterfullsource5GREEN, sixthrunreservedfirstforneededrepairs. Fullmapreduce/QA/UI/ASRreplay/pressure/diagnostics/accessibility/artifact/physical gatesremainunfinished.


## Exact-source component GREEN at8b653cb

Source8b653cb8c33b7abd2d83e747b7bc404d1900f5f5/run40077503748 completedcorejob120823956509 SUCCESS:269XCTest+59Node+85ThreadSanitizer casespassed,0failures/skips/reportedraces; strictnamedreportersagree. All6groundeddecoder/merge and6actualSQLiteFTS3cases nowGREEN, includinglegacyv1/v2data preservation, selectedmeeting/operator isolation/rank/deletion postings, sourcequotes/ranges/nullableattribute/conflict/provenance validation. This is component evidence; actualfullLLMmapreduce/groundedQAandUIstillunfinished. Independentactualmodeljob120823956336SUCCESS5/5,0fail/skip,includingall4oldsemanticoraclesandrealcanonicaltokenizer/capacity/cancel/unload. NativeiOS/59cases/UI/package remainlive, so nofullworkflowGREEN/retainedartifact/deviceclaim.


Terminal8b653cb/run40077503748:269core+59Node+85TSAN+5actualQwen+59native+3UIand2nativebundlecasesallPASS,0skips/reportedraces; native/UIxcresultagreementsconfirmed. FullworkflowFAILEDonly13-casearchivegate:12pass,1negativeSimulatorfixturewrongerrorbecauseXCTestad-hocsigned/instrumentedthereusedDebugapp. Inputauditcorrectlyrejects_CodeSignaturebeforeplatformchecks; no guardshouldberelaxed. ActualdevicepositiveIPA/archiveCRC/hash/sourcecasepassesbuttemporaryoutputiscleanedandnocandidateisretained. FixharnessorderingbyrunningALL13archivecasesagainstpristinecompiledproductsbeforeXCTest; leavefinalephemeralpackagecreationafteralltests. Thisis2ndscopedorderingrepairforthesamewithin-runreusecause,withactualassertionRED,notpermission/toolfailure. Sixth/finalCIreservedforthisrepair;T12draftsstayinactive/noT12REDorbehaviorclaim.
