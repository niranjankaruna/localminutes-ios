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
