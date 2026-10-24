# TDD evidence record

Task/child ID: T08 shared owner/deletion/startup admission
Requirement IDs: app-owned recording lifetime, safe owned deletion, startup recovery admission
Behavior being implemented: one shared exact-token reservation before owner preparation; retain it until every cleanup barrier settles; reject recording while startup recovery is pending/failed.
Acceptance assertion: actual SQLite metadata and committed CAF bytes cannot be deleted during held owner preparation or cancelled-owner transcript cleanup; exact release permits deletion; stale tokens cannot unlock a replacement; startup denial has zero preparation/OS/database effects, and success allows actual synthetic PCM/CAF capture.

## RED — complete before production implementation

Test file: `Tests/MeetingLibraryTests/SharedMeetingAdmissionTests.swift`.

Test names:

- `testOwnerReservationBlocksRealDeletionBeforeHeldPreparation`
- `testCancelledOwnerRetainsUsageThroughHeldTranscriptCleanupBeforeDeletion`
- `testStartupPendingAndFailureDenyOwnerBeforeAllPreparationAndOSUseUntilSuccess`
- `testExactUsageTokenRejectsStaleReleaseAfterReplacement`

Minimal interface stubs: `Core/RecordingUsageAdmission.swift`; optional stored/unused owner initializer dependency; nil/no-op registry protocol adapter; ignored startup flag/no-op completion. Existing owner/registry behavior and old test assertions are unchanged.
Exact command and platform: pending root's hosted macOS Swift/XCTest invocation; Windows has no compatible Swift runtime.
Source commit: PENDING.
CI run URL / sanitized local log: PENDING.
Executed tests / skipped tests: NOT_RUN.
Observed assertion failure: NOT_RUN.
Why this proves missing behavior rather than a broken toolchain: compatible behavioral execution is required; compile/setup failures will not count as RED.
RED commit pushed at: PENDING.

## GREEN

Implementation commit: NOT_IMPLEMENTED.
Exact command and environment: NOT_RUN.
CI run URL / sanitized result: PENDING.
Executed / passed / failed / skipped counts: NOT_RUN.
Real adapters or model exercised: tests use actual recording owner/coordinator, SQLite, CAF writer/reader and owned deletion; no real inference claim.
Mock boundaries: model preparation/finalization, microphone permission/hardware and ActivityKit lifecycle only.
Regression suite and result: PENDING. No old assertion body was edited.

## Review and continuation

Refactor commit(s): none.
Fault injection: held preparation, cancellation during held permission, held finalization, pending/failed startup, stale/replacement exact tokens.
Security/privacy/accessibility review: generated original synthetic fixtures remain under checked owned roots; all held continuations released before teardown; actual owner cleanup and SQLite close precede deletion of fixture roots.
Remaining physical-device gates: protection, locked capture, Action Button, both 125-minute passes, signing/renewal and refresh preservation remain NOT_RUN.
Next task: root reviews/pushes test-first source, proves compatible assertion RED, then authorizes behavior. No owner admission/startup adapter implementation exists yet.

Empty/pending fields are unverified, never a pass. No speech/model weights, real meeting data or credentials are included.
