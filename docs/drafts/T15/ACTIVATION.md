# T15/T16 practical library slice — test-first drafts

Fifteen authored XCTest cases; none compiled or executed. All supplied production
interfaces remain no-op. No active source, existing test, Git setting, commit,
push, workflow, state or CI dispatch is changed by these drafts. Root owns
integration and must record actual hosted assertion RED before implementation.

This slice adds durable original manual notes, usable text/Markdown rendering,
and precise mapping from transcript samples to existing real CAF segments. It
builds on the existing T08 meeting metadata/history/rename/delete/literal-search
tests without duplicating those APIs. It does not implement a second audio store,
fake transcript, fake summary or fake player.

## Exact proposed active paths and imports

- `Persistence/MeetingManualNotes.swift`: copy
  `MeetingManualNotesInterfaces.swift`. It belongs to the existing
  LocalMinutesPersistence target. StoredManualNote belongs to that module.
- `Tests/PersistenceTests/ManualNotePersistenceTests.swift`: copy the same-named
  draft. It tests actual SQLite files and five new behaviors. Existing SQLite3
  linking already applies. No fixture database is committed.
- `MeetingLibrary/MeetingLibrary.swift`: copy MeetingLibraryInterfaces.swift.
  New LocalMinutesMeetingLibrary SwiftPM library/target depends on
  LocalMinutesPersistence and LocalMinutesRecording. Its non-SPM imports support
  eventual direct compilation into the existing main app.
- `Tests/MeetingLibraryTests/MeetingTextExporterTests.swift` and
  `Tests/MeetingLibraryTests/MeetingPlaybackMapperTests.swift`: same-named copies.
  Add one test target depending on LocalMinutesMeetingLibrary,
  LocalMinutesPersistence and LocalMinutesRecording. Existing Apple SDK native
  dependencies apply; playback tests import AVFoundation and create real CAFs.
- Future app compilation adds only MeetingLibrary to the existing main target's
  sources. The extension must not include persistence, export or player code.

The five notes tests use the already existing actor through an extension. Actual
implementation after RED can place the methods in the original actor file or
add a narrow internal connection helper; do not expose C pointers or SQL publicly
just to make an extension convenient. Do not add a parallel notes database that
breaks transactional ownership/deletion.

## Required schema migration and legitimate existing-test update

The first notes case creates an actual version-one SQLite database using the
original T08 table shape and fixed synthetic values. Opening the new adapter
must transactionally migrate to user_version2, preserve that meeting, then save
and reopen its original Unicode note. This is a real migration contract.

The old T08 test `testCreatesAnActualSQLiteDatabaseWithVersionOneSchema` currently
asserts the initial current version is1. In the **test-first activation commit**,
rename it to `testCreatesAnActualSQLiteDatabaseWithCurrentVersionTwoSchema` and
change only the version expectation1→2. Keep its file/table assertions unchanged
and preserve its original RED/GREEN history. This is a requirement-based schema
evolution, not deleting a failure to manufacture GREEN: the old implementation
will now prove actual version1-versus2 RED as well as the new explicit migration
case. Record that reason and both assertion failures before writing migrations.
The existing future-version999 rejection and all other T08 assertions remain.

Version2 adds a manual_notes table owned by meeting UUID with delete cascade,
exact text (including empty clears), nonnegative persisted edit revision and UTC
modified time. Autosave completion means SQLite accepted durable transactional
work, not just updating an in-memory label. An older arriving edit throws
staleRevision; identical same-revision replay is idempotent; different data at
the same revision throws revisionConflict and leaves the accepted note unchanged.
The UI must initialize its next edit revision from persisted data, rather than
resetting to zero on every view appearance. UI debounce/focus/save errors need
their own native UI RED later; none is implied by these storage cases.

## Case inventory and expected no-op failures

| Case | Observable acceptance |
|---|---|
| testManualNoteAutosaveMigratesVersionOneAndPersistsExactUnicodeTextAcrossReopen | Preserve version1 meeting, migrate to2, exact Unicode note/revision after reopen |
| testClearingManualNoteAutosavesAnEmptyValueInsteadOfRestoringOldText | A clear is a saved newer edit, not reappearance of old text |
| testDelayedAutosaveCannotOverwriteANewerDurableManualEdit | Typed stale-revision error and newer durable value preserved |
| testManualNoteReplayIsIdempotentButConflictingSameRevisionIsRejected | Identical replay accepted, conflicting rewrite rejected |
| testManualNotesRequireAnOwnedMeetingAndDeleteOnlyWithThatMeeting | Unknown meeting rejected; rename preserves notes; delete removes only owned note |
| testMarkdownExportIncludesOriginalNotesOrderedTimedTranscriptAndModelProvenance | Readable title/UTC date/notes, source order, 16k utterance timestamps and model revision |
| testPlainTextExportPreservesUnicodeAndLabelsUnavailableTranscriptHonestly | Original text/empty transcript explanation, no invented generated summary |
| testExportsRejectCrossMeetingNoteOrTranscriptInsteadOfLeakingOtherContent | Both formats reject another meeting's note or source rows |
| testMarkdownTreatsMeetingMarkupAsTextAndPlainTextRetainsTheOriginal | Meeting text cannot become active HTML/image markup; plain text remains exact |
| testPlaybackMappingSeeksIntoTheActualSecondCAFWithoutDuplicatingItsFirstFrames | Actual second CAF seek/decode reads expected samples at the mapped offset |
| testPlaybackUsesHalfOpenSegmentBoundsAndRejectsNegativePositions | Exact boundary belongs to next segment, end has no audio, negative rejected |
| testPlaybackDoesNotInventAudioOrClampASeekAcrossAnExplicitManifestGap | No audio in a missing interval; later real CAF offset remains correct |
| testPlaybackRejectsAnotherMeetingsManifestBeforeOpeningAnyAudio | Caller and manifest meeting UUID must match |
| testPlaybackDistinguishesMissingAndUnreadableRealAudioFiles | Missing file and actual corrupt CAF report truthful typed failures |
| testPlaybackRejectsTraversalSymlinkEscapeAndOverlappingManifestRanges | No path escape or ambiguous sample ownership |

No no-op case should pass the whole suite. Negative cases must observe actual
typed errors; positive cases must inspect real durable/reopened content or
actual native CAF samples. Compile/tool failure and zero tests are not RED.

## Formatting and playback decisions to implement only after RED

Markdown uses a title heading, UTC ISO8601 created date, Manual notes and
Transcript headings. Source ranges display HH:mm:ss.SSS from integer16k sample
positions, explicitly described as utterance timing. Original notes stay separate
from finalized transcript; model provenance is retained. Neither format invents
summaries or silently fills absent text. Exports return values only; Files/share
UI and filenames require their own tests. Plain text preserves source content;
Markdown escapes HTML and active Markdown syntax from all meeting-controlled
fields instead of turning spoken links/images into active content.

The mapper consumes the existing AudioCaptureManifest and returns a validated
file URL, CAF frame offset and remaining frames. Validate schema/session,
nonnegative nonoverlapping ranges, totalFrames as the sum of captured frame
counts, supported actual audio format/length, and checked integer arithmetic.
Real canonical paths must remain inside the selected meeting directory after
symlink resolution. Intervals are half-open. Missing global sample intervals
return nil rather than being clamped onto another piece of audio. The gap test
is synthetic manifest metadata over two real native CAF files; it does **not**
prove that current capture/journal code emits/reconciles such gaps. That remains
T08/T11 work, and any manifest semantic change needs its own tests.

Mapping/readback is not audible playback or physical speaker evidence. No
AVAudioEngine playback controller, interruption handling, waveform UI, player
navigation, export sheet, meeting library screen, notes editor, full-text index,
summary/Q&A, recovery journal, model inference, protected-file locking or renewal
preservation is claimed. These remain explicit baseline work, with the owner
performing physical125minute trials manually.

Root next action: activate these interfaces/tests in a fresh permitted test-first
commit only when ready, run the actual15 cases plus schema expectation change,
record RED SHA/run/assertions, then authorize their smallest useful implementation.
