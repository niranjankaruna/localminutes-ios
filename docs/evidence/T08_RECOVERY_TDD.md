# T08.2 actual audio/checkpoint recovery — test-first

Requirements R07/R08/R11. Eight new cases exercise actual SegmentCAFWriter CAF
segments, actual on-disk SQLite/notes/transcript rows, close/reopen, missing and
corrupt bytes, ownership/path rejection, and idempotent recovery. All fixtures
are original non-sensitive synthetic samples/text; no model or owner audio.

Acceptance: a terminated recording becomes recovered rather than completed;
count only readable committed frames, preserve global missing/corrupt ranges,
retain exact original transcript/manual notes, expose the last persisted
transcript endpoint for later repair, quarantine uncommitted/corrupt CAF bytes
without guessing their timeline, and retain the original checkpoint. Repeating
after a real database reopen must not duplicate rows or tail moves. Active and
completed sessions are protected. Unsafe paths/mismatched manifests and a closed
real SQLite store must fail before source-file mutation.

Active files: Tests/MeetingLibraryTests/MeetingRecoveryCoordinatorTests.swift and
MeetingLibrary/MeetingRecoveryCoordinator.swift. The latter is only typed
interfaces with an explicit notImplemented throw. No recovery behavior has
been implemented. Compatible hosted assertion RED and a pushed source SHA are
required before implementation. Windows source inspection is not RED.

The workflow requires every new case by name; expected core total with the
other new T16/formatter cases is224. No current compile, RED or GREEN claim.
Automatic relaunch wiring, transcribing missing work, pressure/interruption
metrics and physical crash/device validation remain separate pending gates.

The additional journal case closes the actual SQLite connection after quarantine,
requires a durable plan preceding the move, and finishes idempotently with a new
coordinator/connection. No fake storage failure or in-memory-only recovery.

Test-first sourcecdf4a06f6a4a9cd226e306941fd0199a18bf418c pushed and remoteHEAD verified before implementation. Hosted run40038154279 active; compatible assertion RED remains pending.
