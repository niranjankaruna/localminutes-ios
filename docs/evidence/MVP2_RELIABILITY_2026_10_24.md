# MVP2 reliability and data — 24 October 2026

Status IN_PROGRESS. Delivered MVP1 remains source4aec851/run40117673355;
these changes do not alter the already delivered IPA or any physical gate.

## Observable acceptance and tests-first RED

Summary resume reopens a protected validated map prefix, binds exact source,
model/prompt/runtime/plan/budgets and revalidates every cached map before reuse.
Downloads retain bounded verified partial files and strong-ETag range state,
then use existing full-hash/atomic installation. Archives round-trip actual
closed SQLite/CAF bytes with strict path/hash/limits and fresh destinations;
SQLite native backup includes committed WAL without mutating its source.
Recovery requires a capture-time speech installation pin, preserves originals
and global ranges, and rejects a changed checkpoint cursor without skipping
untranscribed audio. Schema5 adds only immutable speech pins; legacy data stays.

Test-first31513b1/checkpoint34ab9e9 are pushed before these implementations.
Exact observed RED source **34ab9e9dd36a73ffa6fcf6e5e717d2b72f4353f1**,
[run40119556084](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40119556084),
standard macos-15-intel/Xcode26.2, exact commands in mvp2-red workflow mode.

| Actual suite | Result |
|---|---|
| DownloadResumeTests | 11executed,2PASS/9FAIL,56assertions,0skip,2.484s |
| MeetingArchiveTests | 10executed,0PASS/10FAIL,31assertions,0skip,0.506s |
| SQLiteSnapshotTests | 5executed,0PASS/5FAIL,9assertions,0skip,0.293s |
| SummaryResumePipelineTests | 4executed,0PASS/4FAIL,60assertions,0skip,0.322s |
| SelectedModelRecoveryTests | 5executed,0PASS/5FAIL,12assertions,0skip,18.424s |
| TranscriptionReplayCheckpointIntegrityTests | 2executed,1PASS/1FAIL,1assertion,0skip,27.710s |

Portable job120947908921:30executed2PASS28FAIL156assertions0skip3.606s.
Recovery job120947908779:7executed1PASS6FAIL13assertions0skip46.133s.
Total37executed3PASS34FAIL169assertions0skip. This is behavioral failure after
successful compilation/real SQLite/CAF/actual speech fixture setup, not a tool
failure, zero tests or skipped fake/native substitute.

Examples: cancelled transfer has no durable checkpoint; source-aware summary
resume returns nil prefix and regenerates2maps instead of1; SQLite snapshot
throws notImplemented; archive notImplemented differs from integrityMismatch;
Whisper preparation saves no captured pin, schema remains4 instead of5, and
mutating only cursor allows actual remaining speech to be skipped. All observed
failures precede the corresponding production implementation. Runtime and HTTP
doubles exist only at orchestration/transport boundaries; actual speech tests
use reviewed model bytes and licensed audio, not supplied recognizer strings.

## Implementation and review pending GREEN

Root implements bounded directory archives/restore with protected staging,
no-follow regular-file handles, streaming hash/copy and exclusive publication.
Independent review found one additional traversal gap: empty meeting folders
are not counted by regular-file limits. A DB-only regression is added before
that repair; initial fixture's3files would have made a2file limit falsely pass.
Next run intentionally observes that new RED while verifying initial repairs.

Native SQLite backup uses the SQLite backup API, bounded pages/busy retries,
closed synced output and exclusive rename; original connection/WAL remains.
Summary maps use actual byte digests, grounded decoding and atomic prefix save.
HTTP resume owns one serial file/delegate queue, retained hashes/strongETag,
strict206/200 handling and only installer-staging publication. Captured speech
pin persists before ingress, is immutable and bound to full installation;
replay loads captured Whisper rather than today's Equip selection. Journalv2
binds cursor to its proof; checksum is integrity checking, not authentication.

Current-schema-only test expectations advance4→5 for the real pin-table
migration; historical v1/v2/v3 fixture versions/data assertions remain unchanged.
Snapshot checks independently compare source version with snapshot version.
The manually constructed legacy4 archive remains4. The strict current-schema
test reporter name is updated with the renamed test. No oracle deletion/skip or
weakened content, privacy, checksum or model-quality rule is authorized.

App resume/recovery/download/cache/Files wiring, backup/restore admission/UI,
full endurance diagnostics and package delivery are still required before MVP2
is delivered. Separate service-integration tests are being prepared; initial
primitive GREEN alone cannot establish usable app behavior or code completion.
All physical-device gates remain NOT_RUN; no human signing/device action is
needed for current safe coding/hosted checks.

## SDK compile failure and next integration RED

Source6adcc04/run40121343041 is terminal FAILURE with **zero executed tests**: Darwin.flock resolves to the SDK struct, so the C lock call did not compile. This is neither behavioral RED nor GREEN. The first repair resolves the constant public libSystem flock symbol with the exact C signature, retaining exclusive/nonblocking fail-closed locking and fd-owned release. No tests/oracles were weakened.

The next test-first batch adds app/session summary resume4, actual Phi cancelled-commit/reopened resume1, backup/admission7, transfer/Files5, endurance5, deletion-artifact3, native app-service7, plus archive-directory1 and quarantined-recovery1 contracts:34 new cases prepared, not claimed executed. Stubs only for these new behaviors. The actual-model case uses pinned Phi inference, real SQLite and protected checkpoints; boundary doubles in orchestration cases are not inference validation. Delete Meeting must remove audio, transcript, notes, summary/edits, Q&A, search/pin rows and owned unfinished summary cache, refuse in-use/unsafe paths, and preserve other meetings/models. C3 runs focused related regressions, native service tests and one actual summary-resume flow in separate bounded jobs, not the full LLM/speech suite per edit.

## C3 actual integration result and repairs

Exact0348c1c/run40124109356 is terminal FAILURE with genuine assertions: portable269executed241PASS28FAIL92assertions0skip; actual speech recovery10PASS0fail/skip49.834s; actual Phi resume1FAIL1assert0skip292.229s (validated map absent before final SQLite commit); native actual app services7FAIL20assert0skip4.625s. Native package graph resolution consumed19:12:59–19:20:28 before compilation; tests completed, no hang inferred. DownloadResume11PASS, basearchive10PASS, pipelineResume4PASS; snapshot3PASS2FAILgenericdatabaseFailure, requiring bounded numeric stage diagnostics. New7library/3deletion/5transfer/5endurance/4session/directory1/quarantine1 and native7 provide actual RED before their current implementations.

Repairs now implement retained service cache wiring, native RSS/sensors/bounded endurance sampler, restored generation and actual owner/service rebinding, real shared maintenance/admission, owned cache cleanup with durable deletion journal, resumable manager/Files boundary and bounded quarantine-preserving archive traversal. These await exact-SHA GREEN. Owner additionally requests native FastConformer-TDTv2; dedicated Core ML + Swift TDT tests and pinned metadata/stub are prepared separately before production behavior. Existing ONNX draft is explicitly superseded by owner and archived unexecuted; no Parakeet inference is claimed.

## Corrected new cache-test fixture premise

C4 added a cache-purge test that incorrectly assumed a completed download retains a duplicate full model. This contradicted the existing DownloadResumeTests cleanup contract and adds storage overhead the owner did not request. Correct the new fixture to assert completed progress is already released, then explicitly seed an owned interrupted retry beside the approved install. Keep all real purge/other-pin/link-refusal assertions unchanged. The C4 no-op purge/link failures remain recorded; no passing result is claimed before the corrected stronger scenario reruns. Production preserves default completed-cache cleanup; no retention option is added to make the erroneous premise green.

## C4 observed results and causal fixture strengthening

Exact4640aec/run40126813965: portable281executed253PASS28FAIL60assertions0skip; nativeapp10executed7PASS3FAIL11assertions0skip (original7 nowallPASS; new epoch/delete-generation/playback-maintenance races actualRED); actualPhi cancelled-commit/reopenedresume1PASS445.283s; actualspeechrecovery10PASS. NativeParakeet setup verifies21actualassets/Swift6.2/ASR-onlydependency, then6nativecasesFAIL6assert0skip2.007s (5directstubfailures; selectedLive invalidManifest). No actualParakeet transcription pass yet.

Current repairs cover nativeCoreMLdecoder/worker/lifecycle/privacy, nestedmodelinstallation/Files/HTTP/lease/remove, exactnativecatalog/resources, 3nativeadmissionraces, archiveenumerationindependentofURLbase/depth, andsnapshotstandaloneheader+immutableintegrityproof. SnapshotC4nativebackup/DELETE/close succeeded butstagedentrycount2failed; no causeclaimedwithoutcategory. Its replacement verifies actualstandaloneDB semantics and rejects unsafe/hotjournal content, not a relaxed data oracle.

Both interruption fixtures formerly emitted response/body/error back-to-back. C4zero-prefix doesnot establish thatFoundationdeliveredbytes toourdelegate. Strengthen onlyfaultscheduling: actualdownload must publish exact1024-byteprefix+checkpointSHA beforetestsignalsdisconnect; missingdurability remainsboundedfailure withcancellation/drain. Keepall11DownloadResumeoracles andFactoryresume/Range/IfRange/errors unchanged. No bytes fabricated, no arbitrarydelay tohidearace, no testskip/deletion.

Two additional INDEPENDENT actual-model tests now cover realselection/reopen (not just an injectedLiveprovider) andcapturednativeCAFReplay. These admissions remainfail-closedstubs forC5actualRED; no hiddenpassingclaim or deliverednativeEquipyet. ActualPhi gate is not repeated forunrelatednativechanges; its exactsource evidence remains4640aec.

## C5 native compile result

Exact057fb5b/run40129821538 nativejob120978957517 failedcompilationwithzeroexecutedtests: FluidAudio module/type namecollisionforAppLogger, noasyncThread.isMainThread access, andUnownedJob SDKargumentlabel isolatedTo. First repair onlychangesloggingqualification, wrapsactualThreadmeasurementinsynchronoushelper, andcorrectsSDKlabel. No observerfacts/oracles/compute/hash/privacychecks areweakened. Two independentselection/replayadmissionsremainstubs: C5doesnotprove theirRED because compilationstopped. Already-passing actualPhi445.283s isexcludedfromthisunrelatedrerun asownerrequested.

C5 remainingjobs were cancelled after the shared native compilation failure was conclusive, avoiding redundant build time. Terminalworkflowconclusioncancelled preserves native/portablefailedjobs; this isnotGREEN, notbehavioralRED, andno skippedtestacceptance. Exact3SDKfixesarethenextcandidate.
