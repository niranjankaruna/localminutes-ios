# TDD evidence record

Task/child ID: T08.3 automatic library reconciliation and bounded enumeration.
Requirement: real SQLite/CAF recovery at launch, confirmed deletion first,
explicit errors and capture admission closed until initialization settles.

## RED — pending before implementation

Four cases in `Tests/MeetingLibraryTests/LibraryStartupCoordinatorTests.swift`:

```text
testStartupReplaysDurableDeletionBeforeEnumeratingUnfinishedAudioAndThenAllowsCapture
testStartupProcessesUnfinishedMeetingsBeyondOnePageAndIsIdempotentAcrossReopen
testStartupRecordsAnIsolatedCorruptMeetingButProcessesHealthyOthersBeforeReady
testDatabaseAndDeletionReplayFailuresKeepStartupFailedAndCaptureAdmissionClosed
```

Two in `Tests/PersistenceTests/UnfinishedMeetingPaginationTests.swift`:

```text
testUnfinishedMeetingsUseExclusiveUUIDKeysetsAndExcludeCompletedFromEveryPage
testUnfinishedPaginationDefaultsToOneHundredValidatesBoundsAndReportsAClosedActualDatabase
```

Only minimal interfaces exist: startup `run()` throws notImplemented and
`unfinishedMeetings(afterID:limit:)` returns an empty array. Registry startup
readiness is also a no-op in the separate shared-admission test-first slice.
No production startup behavior precedes actual compatible RED.

Command/platform: hosted macOS/Xcode26.2 `swift test` with the mandatory
MeetingLibraryTests/PersistenceTests filters and strict named-case reporter.
Exact source/CI run/assertion results: PENDING root commit and hosted execution.
Compiler/tool failures or zero cases will not authorize implementation.

Fixtures use actual SQLite rows and native four-frame CAFs, including 103
unfinished meetings across all unfinished states, a completed meeting whose
bytes must remain unchanged, real close/reopen, durable deletion request/audio
quarantine and a malformed deletion marker. No ASR output is fabricated.
An isolated corrupt meeting must be reported while healthy rows are processed;
only global database or deletion-replay failure leaves the whole startup failed.

## GREEN

Implementation/CI/counts: PENDING. Existing component recovery repairs have
their own previously observed RED and are independent of these new stubs.

## Review and continuation

Windows whitespace review only; not a native build. Root reviewed actual tests,
fixtures, ownership and no-op diffs. Shared owner admission has its own four
composition tests in T08_SHARED_ADMISSION_TDD.md. ASR replay after reconciliation,
app startup wiring and all physical/signing/locked/endurance/renewal gates remain
pending. Next: record genuine hosted RED, then implement only these contracts.
