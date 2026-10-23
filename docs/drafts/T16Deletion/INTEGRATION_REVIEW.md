# Notes/library/playback integration review

Read-only review of the actual integrated sources on2026-10-23. The findings
below are concrete scheduling defects inferred from the current code, not
executed regression failures or physical-device results. They remain P1 pending.
No production or test changes were made by this review, and no additional CI
dispatch is authorized. Root must preserve the current six-run invocation cap.

The implemented SQLite actor keeps notes/revisions and transcript rows scoped
correctly. The remaining problems occur where asynchronous screen/OS operations
project those values or resolve an operation's identity across suspension.

## P1: rename can replace a newer selection with an older meeting

Source: `MeetingLibrary/MeetingLibraryController.swift`, rename(_:) around
lines45–51. The method captures selected A, saves A's title, checks that selected
is still A, and then suspends again for `store.meeting(id: A)`. It assigns that
result to selected after resuming without checking selectionRequest again.

Concrete interleaving:

1. rename(A) commits the title and passes its selected.id==A guard.
2. Its actual SQLite read of A completes, but projection is held before assignment.
3. open(B) finishes and publishes B's selected record, transcript and manual note.
4. rename(A) resumes and assigns selected=A while transcript/note still belong to B.

The screen can display a mixed meeting. A later String-based notes save resolves
selected A and can write B's editor text into A. Export currently detects the
cross-meeting source mismatch and rejects it, which helps export but does not
repair the mixed controller state or the subsequent notes write target.

Required regression before repair:

- Use the real temporary SQLite store with A/B metadata, distinct notes and
  distinct finalized source rows. No repository mock.
- Add a bounded test-only scheduling boundary after rename's actual A read and
  before its projected assignment. Public production construction supplies nil.
- Hold rename(A), fully complete open(B), release the old result, and join both.
- Require selected.id==B, B's title/source/note/matches intact, A's renamed title
  durable in SQLite, and no false B error. A later B edit must persist only to B.
- Repeat with a selection failure/clear so an older rename may not resurrect A.

After actual assertion RED, capture the selection epoch at rename admission and
revalidate it **after every awaited read before projection**, rather than relying
on a guard executed before suspension. Refresh/error projection also needs the
operation's epoch so a failed A operation is not attributed to selected B.

## P1: delayed editor saves resolve identity after the user has moved on

Source: `App/LocalMinutesHomeView.swift`, MeetingNotesEditor around lines184–204;
`MeetingLibrary/MeetingLibraryController.swift`, saveNotes(String) around54–70.

The editor's debounced Task captures text but calls saveNotes(String) only after
300ms. The onDisappear Task similarly captures only text. The controller resolves
selected.id and the current note revision when that later call starts. If the
selection/controller projection has changed, an edit created for A can be saved
as B, or can use B's revision. Cancelling the pending debounce does not bind the
onDisappear flush to the meeting that originally produced its text.

There is an additional editor hazard: its task(id: selected.id) writes programmatic
loaded/cleared text into the same state observed by onChange. A transition through
selected=nil can schedule an empty save. A subsequent loaded value matching the
new note exits the onChange guard **before cancelling that pending empty task**.
This needs native editor validation; it must not be claimed reproduced solely
from the controller tests.

Existing unexecuted regression drafts:

- [BoundManualNoteSelectionTests.swift](BoundManualNoteSelectionTests.swift):
  testADebouncedEditRetainsItsOriginalMeetingAfterSelectionChanges and
  testFailedLateAutosaveDoesNotReplaceAnotherMeetingsVisibleNotesOrErrorState.
- [BoundManualNoteInterfaces.swift](BoundManualNoteInterfaces.swift): no-op
  overload taking the existing immutable StoredManualNote, rather than text alone.

Required acceptance:

- Capture meeting UUID, text, reserved monotonically increasing edit revision and
  modified timestamp at the user edit event, **before debounce/navigation**.
  Preserve that immutable value in both delayed save and disappear flush.
- Use real A/B SQLite notes. Capture A's edit, switch/open B, deliver A's delayed
  save, and require only A changes while B's visible/durable note remains intact.
- Close the actual database before the late save. Require its real typed error
  reaches the originating operation and does not alter B's note/error state.
- Add a native editor scheduling test: load A, edit A, navigate/rebind to B before
  debounce, wait/flush; reopen both and compare actual SQLite text/revisions.
- Add a native programmatic-loading case that passes through nil selection and
  loads B's nonempty note. No user edit means no new revision or empty autosave.
- UI must reserve edit order before suspension and use existing SQLite stale/
  conflicting-revision rejection; programmatic loads must not be treated as edits.

These drafts are not yet active, compiled, RED or GREEN. The current production
editor still uses the String overload. Do not describe autosave selection safety
as verified before both controller and native editor assertions execute.

## P1: playback admission races recording admission across a snapshot await

Source: `App/LocalMinutesHomeView.swift`, playSegment(at:) around136–154;
`App/LocalMinutesServices.swift`, playAudio(at:) around85–96;
`App/RecordingApplication.swift`, perform(_:) around58–62.

playSegment reads an asynchronous owner snapshot and later activates
AVAudioSession with category playback. Starting a recording stops existing
playback first, but there is no shared atomic admission between those actions.

Concrete interleaving:

1. A playback request reads idle from the real owner but pauses before activation.
2. Start/Toggle calls stopPlayback while no player exists, then admits a new
   recording/preparation epoch.
3. The old playback request resumes with its already-read idle value and invokes
   playAudio, changing the shared OS audio session during capture's admitted life.

Depending on scheduling, playback can be started during preparation or can
override the microphone session configuration after activation. A snapshot guard
is only an observation; it is not a reservation. This is not evidence that a
physical recording has actually failed, but the current code permits the race.

Required regression before repair:

- Exercise the real RecordingSessionOwner/coordinator plus actual CAF mapping.
  Only OS audio-session/player operations and lifecycle scheduling may be doubled.
  No inference substitute or fabricated recording-ready state is allowed.
- Hold playback after its actual idle snapshot but before session activation.
  Admit real start/preparation, then release playback.
- Require no playback category/activation after the recording reservation, no
  capture-session deactivation by a late playback cleanup, and truthful blocked
  playback status. Verify the owner remains in its correct admitted phase.
- Test the reverse ordering: admitted playback is explicitly stopped/deactivated
  before recording activation proceeds. A failed playback deactivation must stay
  observable/retryable instead of clearing ownership and claiming cleanup.
- Repeat for stopping/cleanupPending: those phases continue to block playback
  until the actual capture/transcript/activity cleanup barrier settles.

After actual RED, use one app-retained audio-use admission gate shared by playback
and recording. Grant and revoke ownership atomically with phase admission; do not
replace it with a second snapshot check separated from activation by another
await. Native session deactivation must be scoped to the operation that owns it.

## Existing open scope retained

The saved owned-deletion drafts remain necessary before exposing complete Delete
UI; current database-only deletion leaves raw CAF files. Playback currently plays
the selected CAF file and does not yet demonstrate continuous multi-file playback,
gap UI or physical speaker behavior. App-switcher redaction, protected-file/backup
policy and actual locked operation remain their own verification gates; this
review supplies no pass or phone failure for those. No requirement is waived.
