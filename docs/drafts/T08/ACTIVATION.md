# T08.1 disk-backed meeting metadata and finalized transcript

Status: test-first drafts only. No hosted compile, assertion RED or implementation
is claimed. These files are outside every active source and test target. Root owns
activation, commits, CI dispatch, evidence and state. No production SQL behavior
has been written. The owner will perform the125minute physical iPhone test;
physical evidence remains pending and is not supplied by these database cases.

This is a deliberately small first T08/T15 slice. It supplies durable metadata,
ordered finalized text and a literal text search restricted to one meeting.
It does not finish T08 crash recovery, T15 UI, T11 recognition assembly, or local
model inference. No database files or actual meeting content belong in Git.

## Exact activation

1. Copy `MeetingStoreInterfaces.swift` to
   `Persistence/SQLiteMeetingStore.swift` and `SQLiteMeetingStoreTests.swift` to
   `Tests/PersistenceTests/SQLiteMeetingStoreTests.swift` without changing their
   assertions. The store is intentionally no-op, so real behavior must fail.
2. Add a `LocalMinutesPersistence` SwiftPM library product and target:

   ```swift
   .library(name: "LocalMinutesPersistence", targets: ["LocalMinutesPersistence"])
   .target(name: "LocalMinutesPersistence", path: "Persistence",
           linkerSettings: [.linkedLibrary("sqlite3")])
   .testTarget(name: "PersistenceTests",
               dependencies: ["LocalMinutesPersistence"],
               path: "Tests/PersistenceTests",
               linkerSettings: [.linkedLibrary("sqlite3")])
   ```

   These are separate entries in the existing products and targets arrays, not a
   replacement Package.swift. `SQLite3` is the proposed Apple SDK Clang module;
   the actual pinned macOS/iOS SDK must compile it before any behavioral result
   is counted. No external Swift package or downloaded SQLite binary is needed.
3. Add `Persistence` only to the existing main application's sources in
   project.yml, and SDK dependency `libsqlite3.tbd`. Do not add persistence or
   an engine to the Live Activity extension. Optionally add the same test file
   to the actual native app-hosted target only after its reporter includes all
   fifteen test names. The conditional import already supports both targets.
4. Run `swift test --filter SQLiteMeetingStoreTests` on hosted pinned macOS.
   Require15 discovered tests and actual assertion failures. Verify the full
   XCTest aggregate using the existing strict reporter and the exact names
   below; a module/link/tool failure is not RED. The root must commit/push this
   test-first step and record its exact SHA/run before implementing storage.
5. After RED, implement the real store in the active path. Keep draft interfaces
   as historical test-first material. Require focused GREEN plus complete current
   Swift/Node/sanitizer/native regressions at the exact implementation SHA.

No extra CI is authorized by this draft. Continuation05 already used6/6 runs;
the root starts a later bounded invocation with a freshly verified free public
standard-runner cost guard. There must be only one active run on the task branch.

## Fifteen observable contracts

| Test name | Missing behavior the no-op should expose |
|---|---|
| `testCreatesAnActualSQLiteDatabaseWithVersionOneSchema` | File missing; once implemented inspect actual SQLite user_version and both tables |
| `testMeetingMetadataSurvivesCloseAndReopen` | Reopened Unicode metadata is nil and a closed store accepts reads |
| `testHistorySortsNewestFirstWithStableUUIDTieBreakAndLimit` | Empty history and an accepted invalid limit |
| `testConcurrentMeetingWritesAndDuplicateIDCannotOverwriteExistingMetadata` | Concurrent durable writes absent, missing duplicate conflict and original metadata |
| `testRenamePersistsLiteralTextWithoutChangingIdentityDateOrTranscript` | No durable title/source data |
| `testRecordingStateAndCapturedDurationAreDurableAndMissingIDIsAnError` | No interrupted checkpoint and missing notFound error |
| `testFinalizedTranscriptIsOrderedBySequenceAndSurvivesReopen` | Finalized rows absent |
| `testReplayingTheSameFinalizedSegmentIsIdempotentAcrossReopen` | Expected one persisted original row, not zero or duplicates |
| `testSegmentIDConflictAndSequenceConflictRollbackTheEntireBatch` | Missing conflict and durable atomic rollback |
| `testUnknownMeetingAndCrossMeetingSegmentsCannotCreateOrphanRecords` | Missing scoped validation/notFound and original meetings |
| `testSearchIsRestrictedToSelectedMeetingOrderedAndCaseInsensitive` | Missing selected-meeting rows in deterministic order |
| `testSearchTreatsQuotesAndSQLWildcardsAsLiteralData` | Literal punctuation query yields no actual source row |
| `testDeletingOneMeetingRemovesOnlyItsMetadataAndTranscript` | Unrelated meeting/source rows must survive reopen |
| `testInvalidSegmentValuesAreRejectedWithoutPartialWrites` | Invalid sequence/time/text/revision accepted |
| `testFutureSchemaIsRejectedWithoutChangingExistingDatabase` | Version999 incorrectly accepted; inspect untouched sentinel |

The synthetic fixtures intentionally contain no real audio, private transcript,
or model output. An empty in-memory mock cannot pass these contracts. Some tests
directly read the adapter's real SQLite file; others close/reopen before checking.
No fake transcript is reachable in the release app from this test bundle.

## Minimal implementation contract after RED

- A single actor owns all access. Its connection/statement lifetime must obey
  Swift6 isolation without passing native pointers across tasks. Keep native
  unchecked Sendable assertions, if any, narrow and documented; views see values.
- `PRAGMA user_version=1` schema contains `meetings` and `transcript_segments`.
  Stable UUIDs are stored canonically; title, UTC Date metadata, explicit
  recording state and captured16k sample count round-trip exactly.
- Each finalized transcript has stable UUID, owning meeting UUID, sequence,
  global16k start/end samples, exact text and model revision. Empty/whitespace
  text, empty model revision, negative sequence/start or end<start are invalid.
  No word-level timing precision is claimed. Actual recognizer utterance-relative
  timestamps need T11 global offsets; interrupted audio gaps remain separate.
- Meeting creation does not overwrite an existing ID. Unknown writes report
  notFound. A valid segment batch to an unknown meeting reports notFound; a batch
  containing another meeting's ID reports invalidInput. Empty finalized batch
  behavior can be a successful no-op; it must not create a meeting.
- Close releases the connection; subsequent access returns the typed closed
  error. A new store instance can reopen the same file with original values.
- Use transactions for segment batches and deletion. Exactly identical replay
  is idempotent. Reused segment ID with different data or reused sequence with
  another ID throws segmentConflict and rolls back earlier inserts in that batch.
- Use prepared statements and bound parameters for all content. Literal search
  may initially use `instr(lower(text), lower(?))`; it is **not** the baseline's
  eventual full-text retrieval index. Search is scoped by bound meeting ID,
  ordered by sequence, and applies a bound positive limit. Blank query returns
  no hits; quotes/percent/underscore remain user data.
- History sorts createdAt descending then canonical UUID ascending, with a
  positive limit. Document the implementation's upper bound before its own test.
- Delete removes only that UUID's metadata/transcript transactionally and is
  idempotent for missing IDs. Audio/manifest deletion is owned elsewhere and
  must later compose safely; this slice intentionally never traverses files.
- Future schema versions fail closed without migration or data rewrite. Initial
  schema creation is the only migration here; old-version migration expansion
  requires its own tests and actual RED.
- Error strings/logs never contain SQL values, transcript/title text or raw
  database paths. Return typed error categories. No network path is added.

## Unfinished mandatory follow-ups

This first slice does not test corrupted tails, CAF/manifest/database reconciliation,
recognition offsets/checkpoint resume, disk-full fault injection, multi-process
concurrent connections, recovered gaps, actual abrupt process termination, WAL/SHM
file protection, exclusion from backup, encrypted custom storage, pagination,
FTS retrieval, notes/summaries/action persistence, audio removal, capture composition,
or any UI. These must remain pending in T08/T11/T15/T16; none may be quietly
counted complete from these fifteen cases. SQLite's own serialization is not a
physical locked-iPhone file-protection result.

## Primary references inspected

- [Swift.org C library module maps](https://www.swift.org/documentation/articles/wrapping-c-cpp-library-in-swift.html)
- [SQLite prepared statement lifecycle](https://www.sqlite.org/c3ref/stmt.html)
- [SQLite parameter binding and text lifetime](https://www.sqlite.org/c3ref/bind_blob.html)
- [SQLite foreign-key enablement](https://www.sqlite.org/foreignkeys.html)

These references inform the proposed adapter boundary; they do not prove the
drafts compile or that any database behavior has run.
