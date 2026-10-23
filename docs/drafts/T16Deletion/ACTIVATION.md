# Owned meeting deletion and bound autosave — drafts only

Status: eight authored tests, uncompiled/unexecuted. Six use actual temporary
SQLite plus native-written CAF files; two use real SQLite and the real screen
controller. No production behavior has been added. All four active ownership
boundaries remain unchanged: capture, metadata, library controller and app UI.
Root owns activation/Git/CI and must prove hosted assertion RED before writing
deletion, reconciliation, new owner wiring or bound-autosave behavior.

The current controller's deleteSelected removes database rows only. Do not expose
that as complete meeting deletion while owned raw CAF audio remains on disk.
These contracts are intended to close that concrete gap. Normal deletion is not
forensic secure erasure on flash storage, and no such claim is made.

## Exact active destinations

- Copy MeetingDeletionInterfaces.swift to
  `MeetingLibrary/MeetingDeletionCoordinator.swift` as minimal interfaces only.
  Copy BoundManualNoteInterfaces.swift to
  `MeetingLibrary/BoundManualNoteEditing.swift` as its no-op overload.
- Copy the two test files to `Tests/MeetingLibraryTests/`. The existing test target
  already depends on LocalMinutesPersistence, LocalMinutesRecording and
  LocalMinutesMeetingLibrary, with Apple AVFoundation/SQLite available. There is
  no new downloaded dependency or fixture database.
- Require all eight exact names below in the strict reporter. Run hosted XCTest
  and record actual executed assertions/SHA/run before implementation. Native
  tool failure, zero tests or a hang is not RED. The scheduling hook is bounded
  and the tests release it even if a required stage is absent.
- Source activation must respect the current invocation run cap. This draft is
  not permission to dispatch an extra workflow or bypass a pending native run.

| Case | Required observation |
|---|---|
| testConfirmedDeletionRemovesOwnedCAFMetadataNotesAndTranscriptOnly | Selected meeting rows, notes, finalized text and entire owned CAF directory disappear; other meeting/model bytes remain |
| testAnActiveRecordingLeasePreventsDeletionUntilItsCleanupReleasesTheLease | Active/preparing/stopping reservation blocks any data removal; settled release permits complete deletion |
| testDeletionRejectsAnAliasedMeetingDirectoryWithoutFollowingItsSymlink | A UUID-shaped symlink to models fails closed before deleting metadata or model bytes |
| testDeletionRejectsNestedEscapingLinksAndMismatchedManifestOwnership | Nested escape or another session's actual capture manifest fails closed |
| testUnavailableActualSQLiteLeavesOriginalAudioUntouchedBeforeDeletionStarts | Closed actual adapter reports metadata failure with original audio/rows preserved |
| testMetadataFailureAfterQuarantineCanBeRecoveredIdempotentlyFromRealDisk | Hold exact stage, close actual SQLite, observe honest failure, reopen and finish persisted intent from a new service; repeat is harmless |
| testADebouncedEditRetainsItsOriginalMeetingAfterSelectionChanges | Immutable delayed edit for A saves only A while selected B's note/state remain unchanged |
| testFailedLateAutosaveDoesNotReplaceAnotherMeetingsVisibleNotesOrErrorState | Closed actual SQLite error reaches the originating save while visible B remains unchanged |

## Small complete deletion contract after actual RED

Meeting UUID is the only deletion argument. The caller cannot supply a raw
relative/absolute meeting path. Derive `recordingsRoot/<canonical UUID>`; validate
the configured root, every directory ancestor and nested entry before any move
or removal. Reject directory/descendant symlinks and all escaping aliases. Use
canonical component boundaries, not a string prefix that accepts a sibling name.
Require the existing capture-manifest schema/session UUID to agree with the
meeting being deleted. Treat its paths as untrusted. Models and other meeting
directories remain outside this operation's ownership.

Serialize delete admission with capture through one application-retained
MeetingUsageRegistry. It is proposed as MainActor-isolated because the real
RecordingSessionOwner is MainActor-isolated: capture can synchronously reserve
before its first suspension, avoiding a new admission race. The deletion actor
must acquire the same gate before filesystem or database work. A matching
recording/preparation/stopping/cleanup lease rejects deletion. A deletion lease
blocks capture of the same UUID until deletion/reconciliation has settled.
Native audio callbacks never touch this registry. No gate is created per view.

The tests currently exercise a real proposed registry, rather than faking a live
flag, but they **do not** prove actual RecordingSessionOwner integration. Add and
prove a bounded owner-preparation/cleanup regression RED before wiring that lease
into the owner and before claiming active-recording deletion protection in the
app. The owner must retain the lease through transcript-finalization and resource
cleanup, including failures; releasing merely when a view disappears is invalid.

SQLite deletion and filesystem deletion cannot form one ordinary SQLite
transaction. Use a minimal durable deletion intent and same-volume quarantine:

1. Acquire the deletion gate and read required metadata from actual SQLite.
   A closed/unavailable adapter fails before touching the original CAF directory.
2. Validate ownership and persist an atomic marker containing schema version and
   meeting UUID only. Suggested private location:
   `recordingsRoot/.pending-deletions/<UUID>/request.json`. Never trust a path
   embedded in a marker. Validate marker directory names and symlink boundaries.
3. Move the validated owned directory on the same volume to an `audio` child of
   that request directory. Preserve all CAF/manifest bytes while metadata is not
   committed. The test-only beforeMetadataDeletion hook runs at this exact stage.
   The test inspects an actual schema1/meetingID marker and compares every
   quarantined CAF's bytes both before and after the real metadata failure.
4. Delete the matching SQLite meeting, notes and transcript transactionally.
   Only an actual committed return permits final audio/quarantine removal.
5. Purge the owned quarantine and marker, then report success and release the
   deletion reservation. If metadata or cleanup fails, report a typed failure;
   retain enough durable intent/bytes for retry. Never report complete deletion
   while an owned original/quarantined audio directory remains.

recoverPendingDeletions validates each marker and resumes the confirmed intent
idempotently using a newly opened actual database. It must handle metadata already
gone or still present, original versus quarantined directory location, and a
missing directory after an earlier completed step. A pending request must never
become permission to traverse arbitrary marker-provided paths. The test simulates
a real database failure after quarantine and a new coordinator, not a true abrupt
process kill; broader crash/fault coverage remains pending.

Production app startup must restore/reconcile pending reservations before capture
or destructive UI becomes available. If recovery fails, show pending deletion
truthfully and continue independent safe work; do not discard the journal or
silently let that UUID start recording. Avoid meeting text/raw paths in errors.

Only after coordinator and actual owner wiring are verified should the controller
route confirmed deletion through this service and clear selection on settled
success. Its current database-only convenience method is not the final app flow.
The native confirmation sheet, cancel action, accessibility, interruption and
failure/pending UI still need actual native UI RED before those behaviors.

## Bound manual-note editing contract

The new overload accepts the existing immutable StoredManualNote value. The
editor captures meeting ID, reserved edit revision, timestamp and text **when
the user edits**, before debounce or navigation suspension. A delayed task must
never look up a new current selection to decide where old text belongs.

The persistence layer's existing revision protection remains authoritative.
The controller forwards the real save failure to the originating operation;
visible note/error state changes only if it still belongs to that edit's meeting
and revision. A late A save or failure may not rewrite selected B's note/label.
This does not replace tests for current String-based immediate saves or revision
conflicts. Add native editor debounce/navigation tests before claiming complete
UI autosave correctness; these two tests cover actual controller/SQLite isolation.

## Limits kept pending

No active owner lease, delete UI, actual deletion/recovery implementation, native
UI autosave behavior, crash-kill/disk-full fault result, forensic erase guarantee,
protected-file locked access, physical microphone, Action Button, signing, renewal
or125minute endurance evidence is supplied. The owner continues physical tests
manually. These drafts must not change completion state or be counted as GREEN.
