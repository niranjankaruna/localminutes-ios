# Editable generated summary/Q&A storage: inactive test-first draft

DRAFT / NOT_RUN. All Swift files remain `.pending` and excluded from active
targets. No schema change, compilation, assertion RED, storage implementation,
model result, or UI completion is claimed. Exactly four new cases use actual
temporary SQLite databases and a complete constant legacy-v3 FTS5 fixture.

## Four cases and intended RED

1. `testVersionThreeMigrationAddsSeparateGeneratedStorageWithoutChangingOriginalsOrFTS`:
   requires current schema4 and a separate actual `generated_documents` table;
   preserves exact meeting/manual-note/transcript equality and working legacy FTS.
   Current schema3/no-op seams yield version/table assertion failures.
2. `testSummaryAndQuestionAnswerOriginalsEditsAndProvenanceSurviveReopenSeparately`:
   persists both generated kinds, original UTF-8 JSON bytes, display text, source
   question, generation provenance, revisions, and dates; reopens SQLite, checks
   kind/selected-meeting isolation and deterministic history. No-op creation/read
   yields missing durable records rather than fake persistence.
3. `testOptimisticEditsRejectLateRevisionOriginalReplacementAndWrongMeetingWithoutLosingLatest`:
   compare-and-swap edit0→1 commits; stale revision0, wrong selected meeting, and
   replacement of original generated content are rejected. Latest edited content,
   original provenance/payload, manual notes, and transcript remain intact. Closed
   DB must throw its real failure rather than return successful empty data.
4. `testSelectedMeetingDeletionCascadesBothGeneratedKindsAndPreservesOtherMeetingAfterReopen`:
   deletes both generated kinds owned by one meeting, verifies actual row count,
   and preserves the other meeting's generated record/metadata/notes/source on
   reopen. This is DB ownership only; the existing owned-audio deletion workflow
   must remain responsible for CAF files and its durable deletion journal.

## Activation shape, before implementation

- Copy `StoredGeneratedDocument.swift.pending` into `Persistence/` and the test
  file into `Tests/PersistenceTests/`. Existing Persistence target dependencies,
  SQLite3 linkage, and PersistenceTests core filter suffice. Add all four exact
  case names to the strict reporter before dispatch. No Summary/QA target
  dependency belongs in Persistence; stored generated JSON is opaque validated
  caller output, not a second inference engine or source of meeting text.
- Copy the no-op method extension into `Persistence/` to obtain behavioral RED.
  **Do not assume that this separate-file extension can access the actor's private
  connection.** After recorded hosted assertion RED, move real method bodies into
  `SQLiteMeetingStore.swift` (same file as its private connection) or have the actor
  call a narrowly scoped internal helper using its own connection. Do not expose a
  native pointer, add an unchecked global connection, or loosen private access just
  to make a separate extension implementation compile.
- Commit/push tests and no-op seams first. Read/persist actual compatible assertion
  RED at the exact SHA; compile/tool/environment failures do not authorize behavior.
  Only then implement the schema/methods and prove focused plus original regression
  GREEN. Keep all four assertions/corpus unchanged.

## Storage contract after RED

Propose transactional migration0/1/2/3→4 by appending a separate meeting-owned
`generated_documents` table and index, setting user_version4 only after success.
Keep existing FTS3 structures/triggers and legacy sources unchanged. Preserve all
existing v1/v2/v3 fixture PRAGMAs/data/equality/literal/FTS tests. Only current-schema
expectation names/results advance3→4 with this new migration requirement documented;
do not relabel an old fixture as schema4 or recreate a legacy fixture using a future
current store.

Document identity, meeting, kind, original JSON, source question, model revision,
prompt version, and creation date are immutable. An edit changes only editedText,
modifiedAt, and editRevision with a transactionally checked expectedRevision; the
store increments by one and returns the committed record. A late or stale editor
cannot overwrite a later edit. Empty edited text is a valid deliberate clear. It
must not clear the original JSON or overwrite original manual notes/transcript.
Caller-provided generated JSON is not evidence of actual inference or semantic
grounding; existing Summary/QA validation remains the caller's responsibility.

Queries are selected-meeting scoped, newest createdAt first then UUID ascending,
and have a finite limit (default50, proposed1...1000). Real implementation must use
prepared bindings, checked revision arithmetic, finite timestamps, bounded UTF-8/
JSON/display sizes, typed input errors, FK `ON DELETE CASCADE`, and the existing
exact-file privacy/transaction policy. These four cases are a first storage slice,
not exhaustive malformed-input/limit/cancellation/privacy or UI autosave coverage.

No working storage SQL is provided here. Constant SQL in tests only constructs the
legacy v3 fixture and inspects actual database state. No model weights, recordings,
private transcripts, databases, or native outputs are added to Git.
