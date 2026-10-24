# Blockers

No confirmed external blocker prevents current code/test development. T00 authentication
and repository bootstrap succeeded. A sandbox-only network error was resolved
by an authorized direct check; account billing read access was available in the
signed-in browser despite insufficient CLI billing scope.

Observation to track: account Actions storage displays 0.5 GB used / 0.5 GB
included. Artifact headroom is unverified. Initial CI can use test logs without
uploads; check headroom before attempting an IPA artifact. No unrelated artifacts
were deleted and no billing settings were changed. All device gates remain
NOT_RUN, not inferred blocked or passed before a candidate exists.

## ARTIFACT_STORAGE_HEADROOM_UNVERIFIED — external, artifact delivery only

- First observed: 23 October 2026, approximately 14:41 UTC; rechecked about 15:07 UTC.
- Affected: T04/T21 artifact upload and G03 IPA delivery; no effect on current
  core tests or native builds without uploads.
- Evidence: signed-in Actions overview displays 0.5 GB / 0.5 GB and rendered
  progress 100%. Rounded values do not establish any safe upload capacity.
- Attempts/retries: read-only observations only; zero uploads, billing changes
  or deletions attempted. The existing account Actions hard budget remains $0.
- Safe independent work: core behavior, native compilation/testing without
  uploads, local scripts and documentation.
- Owner action when an IPA is ready: free space by reviewing unneeded account
  artifacts, or wait for their expiration, then verify included storage headroom.
  No purchase, public repository or credential is requested.
- Resolution: pending. Never set candidateArtifact until a retained, checksummed
  artifact has actually been delivered and verified.

## Resolved implementation issue — T03.1

Observed by independent review on 23 October 2026 at source
`9c39e5f6a44904dc5746fc31c6a1c5e3c9373fc2`: after activation is emitted,
interrupt is ignored while the phase is still preparing. A late readiness event
can then publish recording. Regression test was written before fixing it;
native RED is verified at `33cd7c6a88195998b6a5f15bb62cc9c6c415045a`, run
39976742123: 20 executed, 19 passed, 1 failed, 6 assertions, 0 skipped.
Next implementation must handle that interruption with
one cleanup command, reject late readiness and preserve interrupted status.
Resolved in continuation at `809f653c8b3cb52c1c04943401eb42d166d7e94b`, run
39978171921: 20 XCTest and 8 reporting tests passed, 0 failures/skips. Independent
review passed; exact tested history was fast-forwarded and verified on main.
No owner action or credential was needed. T03/T03.1 are complete as domain work.

For each blocker record: ID, first observed time, affected tasks/gates, exact sanitized error/evidence, hypotheses already tried, retry count, safe independent work, owner action if required, and resolution evidence. Missing authentication, unknown budget guard, and unavailable physical device must not trigger an endless retry loop.

## Continuation-01 execution boundary — not an external blocker

Six of six permitted new CI runs are complete. The sixth preserved actual
filesystem regression RED, rather than suppressing it. Local fix
`14a988604c05e2484e9d08bf5d4d11e04d217e73` passes 51 Windows script tests and
has passed independent review; it is saved locally without triggering run7.
No native archive or IPA has been produced yet. Resume T04.3 exact-source
macOS GREEN after the next invocation's repository/cost check. Project remains
IN_PROGRESS; this per-invocation boundary requires no owner credential or billing
change. Artifact retention remains the separate headroom blocker above.

Continuation-02 resolved the prior CI boundary: run 39987058071 verified the
saved fix and actual unsigned packaging; all test groups passed. T04.3 is complete.
The IPA was ephemeral, not uploaded or delivered; storage headroom is still
unverified (457.7 / 2,000 minutes used and 100% storage at the new cost observation).
T05 capture development can continue. No owner action is needed for current code.

## Continuation-02 execution boundary — not an external blocker

Six of six new CI runs are terminal. Final sourcec5b45a5/run39994364160 passed
56 XCTest +51 Node +22 repeated queue tests under Thread Sanitizer. CI failed
only because its parser rejects the valid filtered `Selected tests` root;
native-build was skipped and no new IPA exists. This is a small implementation
issue, not a credential, device or cost-control failure. No owner action needed.
Local reporter regression tests prove16 executed/11 passed/5 failed; do not fix
before the required test-first push. Next invocation must recheck the cost guard,
push the saved tests for hosted RED, fix strict selected-suite support and require
exact-source full CI/native GREEN. No seventh run, test skip, parser weakening,
upload, publication or billing change is authorized by this boundary.
The full portable suite at local test-first35074aa is59 executed/54 passed/5 failed,
0 skipped. These are the same selected-suite regressions; production is unchanged.

Continuation-03 resolved the prior reporter boundary: full run39997623318 at4b63907 passed56 XCTest,59 Node,22 repeated TSAN and15 native checks. T05 development continues; artifact retention remains the separate external blocker.


## Continuation-03 execution boundary — not an external blocker

Six of six runs are terminal. T05 component full GREEN is c12bd9c/run40001047762. T06.1 e2876e8/run40004059233 passed87 XCTest+59 Node+53 repeated TSAN but failed actual iOS SDK update/end isolation compilation;0 native checks/no new IPA. This is an internal compile repair, not a credential/device/cost-permission failure. No owner action is needed for current code. A checked ID-only SDK operation candidate is outside active sources; missing-lookup cleanup policy must have regression RED before integration. Resume T06.1.1 after next invocation cost/Git check and require full native GREEN. No seventh dispatch/re-run or weakened concurrency/test gate. Separate ARTIFACT_STORAGE_HEADROOM_UNVERIFIED remains active: final storage100%; no artifact upload.

Continuation-04 resolved the prior native compile issue atb6f4bdf/run40008712625:
all91Swift+59scripts+57TSAN+15native checks passed. First ID-only SDK repair
succeeded. This required no owner action. Resource OS semantics remain pending
phone evidence; separate artifact storage headroom blocker remains. Current2/6
new runs terminal; safeT06.2.1 app-owned composition work continues.

## Continuation-04 execution boundary — not an external blocker

Six of six new runs terminal, final9eeaa25/run40013807701 fullyGREEN:
103Swift+59scripts+69repeatedTSAN+15native checks. T06.1.1SDK repair and
T06.2.1owner/cancellation implementation issues resolved within component scope;
no owner credential/permission action needed for safe next coding task. Native
app/intent composition and models/UI remain unfinished. NextT06.2.2tests are
saved outside active paths; recheck cost/Git next invocation, prove RED then
implement. No seventh run/re-run, no uploads or paid/publication changes.
Separate ARTIFACT_STORAGE_HEADROOM_UNVERIFIED remains active; all device gates
remainNOT_RUN, not passed or inferred blocked merely from code completion.

## Continuation-05 checkpoint — execution boundary and approved public builds

All six runs are terminal. Final6b5fd0c/run40027966192 verified new native Toggle
regression RED (39executed38pass1fail9assertions0skip), then hit the configured
15minute limit during an incomplete UI suite. Local covered repair695b99b is
uncompiled; native25minute bound/public configuration4dfacf6 is also local.
Remote1718b09 preserves RED; main remains known-good. No seventh dispatch or
source push in this invocation. This boundary is not a credential/device failure.

The owner explicitly authorized public visibility to continue free standard
hosted builds. Actual PUBLIC status was verified through authenticated and
unauthenticated GitHub APIs; evidence:T01_PUBLIC_REPOSITORY.md. The private-minute
allowance concern no longer blocks standard macos-15-intel execution under the
verified public policy. No billing settings were changed. Artifact retention
still requires its own verification and remains the separate existing blocker.

The owner requests three sub-agents and a one-hour push focused on actual
transcription; those agents are running. They must not bypass TDD or start
recursive sessions. Next invocation can continue from their test-first outputs
and the saved source history. Physical125minute tests are owner-run/manual and
remain pending, with no waiver or fabricated result.

## SUMMARY_ATTRIBUTION_QUALITY — implementation quality, not an external stop

Current scoped resolution, 24 October 2026: source
`39d9eaa65f7b030a8bdf87e1447b254508dce2db`, run40073883889, passes all four
original actual Qwen/b5046 semantic/model-size/cancellation cases after the
explicit caller-schema implementation. The earlier generic failures below
remain historical evidence; do not restart stopped prompt/model experiments.
This resolves that fixed rubric only. Complete grounded map/reduce summaries,
missing owner/date cases, Q&A, heavy-model admission, persistence and UI remain
unfinished. The new independent token-counter/capacity case was RED and its
source4 repair is pending exact-SHA verification; see
`evidence/T18_CAPACITY_FIXTURE_ISOLATION.md`. No owner credential is needed.

The real verifiedQwen2.5-1.5B Q4_K_M model ran on verifiedWindowsllama.cppb11798. Threeboundedprompt/schema repairattempts stillassigned a fictional volunteeredtask to the wrongspeaker. ExpectedLeo/guide/Thursday assertionsareunchanged. BlindWindowsretriesstopped; actualnativeb5046qualitytestsremainmandatory andpending. Nextdiagnosis: measuredcandidatecomparison or newtest-firstquote-first grounding/validation withexplicitunsupported-output rejection. Do nothardcodefixtureanswers, replaceinference, claimsemanticquality, orstopindependentASR/historywork. Evidence: docs/drafts/T09/Transport/SUMMARY_CANDIDATE_RESEARCH.md.


Native summary confirmation: source7659a19/run40036438183 executed real b5046/Qwen,4tests2pass2fail4assertions0skip. Same owner/task/date failures persist; three bounded Windows prompt retries remain stopped. The native job is not a fourth prompt repair. No owner credential or additional spend is needed to diagnose this internal quality failure. Three other unexecuted P1 library/playback interleavings are documented in docs/drafts/T16Deletion/INTEGRATION_REVIEW.md; their fixes require new regression RED. Current6/6 run budget permits observing the active native job and saving local work, not a seventh dispatch.


## SIMULATOR_FILE_PROTECTION_UNOBSERVABLE — physical metadata gate

Confirmedatcdf4a06/run40038154279: directSDKsetCompleteonoriginalfixturefollowedbygetreturnsnil independentlyofthethen-nooppolicy. Simulatorcannotprovephysicalclass/lockedaccess. Preserveall7fullclassassertionsbyte-identicallyinPhysicalDeviceTests;compileonhostedmacOSforiPhoneOS,butexecutionremainsNOT_RUNuntilrealdeviceevidence. FiveindependentSimulatorFScasescoverbackup/POSIX/atomicwrites/SQLite/CAFwithoutclaimingclasssuccess. Noretriesorclassspoofing; noowneractionneededforcurrentindependentcodework. Actualphonevalidationwillbeconsolidatedwithcandidatehandoff.


## Continuation 08 execution boundary — not an external blocker

All six permitted runs are terminal. Final `db1b8d51c5ff72bf1d8abfd13f99a1da06a11e04` / [run40079629180](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40079629180) passed all application/model/native/UI/archive groups. No internal archive-ordering blocker remains. The next bounded invocation activates T12.2 tests before behavior; full baseline remains IN_PROGRESS. No owner confirmation is needed for independent development. ARTIFACT_STORAGE_HEADROOM_UNVERIFIED still affects retained delivery only. All physical/signing/renewal gates remain NOT_RUN. Details: [checkpoint](evidence/CONTINUATION_08_CHECKPOINT.md).


## T07 installation path resolved with iLoader — 24 October 2026

The owner reports successful main-app installation with iLoader and selected
it as the project installer. The previous -80046 installation-path blocker
is resolved by that reported installation; its exact upstream cause was not
established. T07 is IN_PROGRESS for extension/control/device evidence, and
existing model-quality/artifact issues are unchanged. Next: record exact
installed build/phone/tool versions, then check Live Activity status and Stop.
[Owner-report evidence](evidence/T07_ILOADER_INSTALL_2026_10_24.md).

## MVP delivery workaround observed24October2026

The original Actions artifact storage headroom remains unverified for a full release. It did not block the owner-requested MVP: unpublished draft422706783 retained the unsigned IPA and a Windows download matched SHA256. No billing change, paid storage or public release. MVP delivery has no remaining download blocker; all physical/full-baseline gates remain pending. See evidence/MVP_DELIVERY_2026_10_24.md.


## Qwen QA known-fact over-refusal after three prompt repairs —24October2026

Confirmed1eeb403/run40098679075 actualquestionscase: knownbudgetrefused whileunknownownerrefusescorrectly. Threeblindpromptattemptsstopped;no4thprompt/model-oracleweakening. Aseparateretrieval-precisionrepair(top1single-quoteevidence,ownershipmorphologyandtermcoveragerank)isunderoneboundedactualverification.Contextpollutionisahypothesis. KeepsemanticqualityIN_PROGRESSunlessrawknownandunknownoraclespass.


## Bounded repair actual result; model-quality blocker

Exact588834b68876e94a6cffe5963fe0a875d1f69315/run40099854249 completedFAILED13:59:51UTC; actualiPhonebuildSUCCESS. Summarycase1FAIL196.566s: positivefixturevalidatedanditsassertionspass (secondnegativefixturecaptured), butunknownmodeloutputparaphrasesReviewthechecklist,ownerunassigned,duetheNoowner/nodeadline sentence;correctlyrejectedunsupportedClaim. No nullable-fieldnormalizationorvalidatorweakening. QAcase1FAIL114.555s unsupportedEvidence; rawfailedcallnotcaptured,specificquestionstageunproven. Actualdefaultservicecase1FAIL313.242s unsupportedClaim atsummary. Allsemanticoracles/pinsareunchanged. ModelqualityremainsFAILED,notcompletedbyUIcompilation.

No furtherprompt/testloop. Ownerwasaskedonetimewhethercompareonecompatiblelocalmodelwith30mincaporstopmodelwork, duetothenorepeatedtestrunconstraint. Awaitreplybeforecandidateexperiment;elapsedtimeisnotapproval. OfficialMicrosoftPhi-3-mini-4k-instruct-GGUF(MIT,2.2GBQ4asmodelcard)identifiedaspossibleread-onlycandidate,notdownloaded/pinned/evaluated/recommendedasworking. https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-gguf

Inputpackingreviewremovedartificialtwo-sourceinputcap: actualcanonicaltokenizercountsnowpacklongerchunks;output≤2/category,1citationand128map/itemboundspreserved. Existingtwo-sourceactualfixtureshaveidenticalprompts/chunks/schema,nomodelsemanticrepairclaimfromthischange. Finalcompile/package-onlymodeexcludesallmodel/fulltestjobs. ThispreparesanupdatedUIpreviewwhilequalityblockerremains;nomoreinferenceexperimentswithoutownerchoice.


## Owner decision24October2026 at14:43UTC — one comparison authorized

Owner chose one compatible local model capped30minutes. The earlier pending-choice condition is resolved. One pinned MIT Phi-3 candidate/current-format comparison is run40104505380/source1a999b6; no default-model switch or quality PASS assumed. Stop by15:13:11UTC, retain exact outcome and next task. Qwen quality blocker and all device gates remain pending.


## Single Phi-3 comparison final checkpoint24October2026

Stopped within owner30min window14:43:11–15:13:11UTC. Source1a999b6/run40104505380: native compile/integrity PASS; actual Q&A known42000credits PASS56s and unknown-owner refusal PASS39s, selected-meeting isolation and SQLite originals/reopen assertions pass. XCTest overallFAIL140.207s/3assertions because both summaries used artifactSHA instead of40char modelrevision and generationcount2!=4. This is harness preflight failure, not Phi summary semantic failure. Correction source6d914fe0117964c7019a71d5b9332c9dba3758b4/run40105186439 runs only the2 missing summaries; unchanged semantic assertions/model/prompt/validators. Native compilePASS130.24s; eight-minute job limit cancelled15:11:06UTC with no completed case/stage reports. Summary quality is unverified/inconclusive; no output reconstruction or inferredPASS. No third run, new model, full suite, IPA, default switch or phone gate. Existing installable package unchanged. OverallIN_PROGRESS, completed feature taskIDs:none. Evidence: evidence/PHI3_SINGLE_COMPARISON_2026_10_24.md. Exact next: T18.3: inspect the bounded Phi summary runtime/generation path before further inference; the8min summary-only run40105186439 had no completed case/stage report. Preserve the2/2 actual Q&A observations, all original oracles and failed/timeout evidence. No automatic retry, new candidate, default-model switch or package. Resume a separately bounded implementation batch only when the owner resumes work.


## Current MVP1 delivery and remaining scope

MVP1model-choice source4aec851/run40117673355 is delivered and focusedchecks137PASS. Actionsartifactstorageheadroom remains unverified, but owner-only unpublisheddraft422886787 successfully retains this IPA without Actionsartifactstorage; no owner storage/billing action is needed for this delivery. Phi selectedsummary/QA flows pass measuredsmallfixtures; olderQwenfailures stay recorded and representativequality remains a pending gate, not a current externalcodeblocker.

MVP2replaycursorintegrity is a known internalP1: future2negativecases prepared, noactualRED/fix yet; replay remains unwired. Summaryresume, capturedmodelpins/schema5, resumableHTTP andarchive/snapshot tests are preparedstubs. Currentinvocationused6/6CIruns; nextboundedinvocationmustcapturetheirRED beforeimplementation. This is an executionboundary, not an ownerpause/credentialrequest. Physical LockScreen/ActionButton/extension/offline/2x125min/renewal/protection gates remainNOT_RUN and human-owned.
