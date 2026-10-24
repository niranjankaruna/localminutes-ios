# T19.1 selected-meeting FTS evidence — test-first

Status: six authored tests, no compatible compile/RED/GREEN claimed yet.
Only retrieveEvidence(meetingID:query:limit:) returning an empty array is added
to production interfaces. Existing literal search remains unchanged. No working
FTS table, migration, query, generated answer or model inference is introduced.

Acceptance: actual SQLite FTS5 evidence restricted to the selected meeting,
lexical conjunction of user query terms (quotes/OR/NEAR are data), useful BM25
ranking with sequence tie-break, default8 and valid limits1...20, empty/punctuation
input returning no evidence, exact original UUID/text/ranges/model provenance,
append/reopen/idempotence and actual index-posting removal on owned deletion.

Test file: Tests/PersistenceTests/MeetingEvidenceRetrievalTests.swift, six cases:

- testVersionTwoMigrationBuildsActualFTS5WithoutChangingOriginalMetadataNotesOrSource
- testEvidenceQueriesKeepSelectedMeetingIsolationAndTreatOperatorsAndQuotesAsTerms
- testMultiwordEvidenceUsesUsefulRankAndSequenceTieBreakInsteadOfArrivalOrder
- testEvidenceLimitsAreBoundedAndEmptyOrPunctuationInputNeverReturnsAllRows
- testFinalizedAppendIdempotenceAndReopenRetainExactUTF8EvidenceAndProvenance
- testMeetingDeletionRemovesItsActualFTSIndexEntriesAndKeepsOtherEvidenceAfterReopen

The migration case first probes FTS5 in a separate actual temporary SQLite file.
A missing native FTS module is a compatibility/tool issue, not application RED.
It then seeds an actual original version2 database and checks original metadata,
manual notes and UTF8 finalized source before inspecting the real transcript_fts
virtual table and native MATCH postings. No in-memory persistence mock is used.
All fixtures are constant synthetic non-sensitive text. No private audio/data.

Schema decision proposed for this task: version3 adds an FTS5 transcript_fts index
and transactionally backfills version2 source, then maintains append/delete
postings. Existing version1→2 notes migration remains required. Old current-
schema2 assertions are deliberately unchanged in this test-first source.
After actual new regression RED, a requirement-based migration update must
explicitly evolve the current-schema expectation to3 while preserving the old
v1/v2 fixture contents, range/provenance assertions and prior RED/GREEN history.
Do not delete old tests or silently weaken equality to make schema3 GREEN.

Native command after root review/allowed dispatch: swift test on pinned hosted
macOS/Xcode with all six expected names in the strict reporter. Exact source/run,
executed assertions and fixture/native observations remain NOT_RUN. Root owns
Git, workflow, state and CI. No additional dispatch is authorized by this file.

This is retrieval only. Grounded Q&A, generated-answer citation/semantic checks,
token budgets and physical offline behavior remain pending. Evidence output is
original text; fabricated answers or mocked inference cannot satisfy later gates.

Test-first source1f03e5259ead091c616eb4ce3c49f80d1af79018 pushed/remote verified, actual compatible RED pending [run40075611744](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40075611744). No new working behavior before assertions.


## Actual hosted RED, 24 October 2026

Test-first source1f03e5259ead091c616eb4ce3c49f80d1af79018/run[40075611744](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40075611744), completedcorejob120818174062:269cases executed257passed12failed55assertions(1unexpected)0skip. All257earlierregressionspassed, includingall11CAF/SQLiterecovery,4startup,2pagination,4sharedowner,6chunkplanner and3filesystemscope cases. No compile/tool failure or zero-test RED.
AllsixnewFTScasesfailed24assertions(1unexpected missing-index sqlite(1))0skip. The actualnativeFTS5probe succeeded and the migrationcase reached real v2schema/data assertions; applicationstillversion2/no transcript_fts andquerystubreturnedempty. This authorizesactualFTS5schema3/backfill/triggers/bound-selectedquery. Evolve onlycurrent-schema assertions2->3 with explicitmigrationreason; all oldfixturedata/equality/searchsafety remainsmandatory.

## Requirement-based schema expectation evolution before implementation

The current schema advances to3 because T19.1 adds the actual FTS5 index and its
transactional backfill/maintenance. Rename only the current-version creation
test to testCreatesAnActualSQLiteDatabaseWithCurrentVersionThreeSchema and change
its version expectation2→3. The existing version-one manual-note migration case
also expects the new current version3 after opening, while its actual legacy
fixture remains user_version1. The new evidence fixture remains user_version2.
Every metadata/note/source equality, file/table, future999 rejection and literal
search assertion is retained. This expresses the new migration requirement;
it does not accept multiple versions, remove failures or weaken source integrity.
The six original FTS oracles remain unchanged after their actual RED.

Implementation source8b653cb8c33b7abd2d83e747b7bc404d1900f5f5 pushed/remoteverified; exact-source GREENpending [run40077503748](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40077503748). Existingstrongassertionsremainmandatory.


## Exact-source component GREEN at8b653cb

Source8b653cb8c33b7abd2d83e747b7bc404d1900f5f5/run40077503748 completedcorejob120823956509 SUCCESS:269XCTest+59Node+85ThreadSanitizer casespassed,0failures/skips/reportedraces; strictnamedreportersagree. All6groundeddecoder/merge and6actualSQLiteFTS3cases nowGREEN, includinglegacyv1/v2data preservation, selectedmeeting/operator isolation/rank/deletion postings, sourcequotes/ranges/nullableattribute/conflict/provenance validation. This is component evidence; actualfullLLMmapreduce/groundedQAandUIstillunfinished. Independentactualmodeljob120823956336SUCCESS5/5,0fail/skip,includingall4oldsemanticoraclesandrealcanonicaltokenizer/capacity/cancel/unload. NativeiOS/59cases/UI/package remainlive, so nofullworkflowGREEN/retainedartifact/deviceclaim.


## Exact-source full regression GREEN

`db1b8d51c5ff72bf1d8abfd13f99a1da06a11e04` / [run40079629180](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40079629180) completed SUCCESS.269core/59scripts/85TSAN/5actualQwen/59native/3UI/2bundle/13archive cases all pass,0failures/skips/reported races; native/UI xcresult agrees. This supersedes earlier pending-GREEN statements for the bounded component above. It does not complete its broad parent feature or any physical gate. Source, artifact, limits and exact remaining work: [continuation08 checkpoint](CONTINUATION_08_CHECKPOINT.md).
