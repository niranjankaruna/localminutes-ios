# Actual recovered-audio transcription replay — inactive test-first draft

DRAFT / NOT_RUN. Exactly four cases and a no-op coordinator seam. No active file,
schema, Git, model, workflow, or app/startup behavior changes. No native execution,
replay success, phone behavior, or recovery completeness is claimed.

## Activation and required names

Move the coordinator seam into Transcription/ and tests into Tests/ASRTests/.
Existing ASRTests dependencies and the `(ASRTests|...)` core filter already cover
all four cases and reuse NativeASRFixture from CPUStreamingRecognizerTests.swift.
Add LocalMinutesMeetingLibrary to the LocalMinutesTranscription target dependencies
for report/usage types; that library currently depends only on Core/Persistence/
Recording, so this introduces no module cycle. Native app sources already include
both directories; conditional package imports preserve the single native module.
Add all four exact names to the strict core execution reporter:

- testActualASRReplaysOnlyUntranscribedDurableCAFPreservesGlobalRangesAndIsIdempotentAfterReopen
- testActualReplayKeepsManifestGapAndCorruptTailExplicitWithoutCompressingOrInventingAudio
- testCancelledActualReplayKeepsCommittedCheckpointAndResumesWithoutRepeatingOriginalOrFirstUtterance
- testActualRegistryExcludesReplayFromRecordingAndDurableDeletionInBothDirections

The existing hosted setup supplies LOCALMINUTES_ASR_MODEL_DIRECTORY and
LOCALMINUTES_ASR_FIXTURE_PATH, pinned sherpa1.13.8, and exact licensed LibriSpeech
6930-75918-0000 bytes. No new download/assets, optional inference test, fake speech
text, or model double is introduced. The actual semantic oracle retains the
existing <=15% WER/key-word rubric. Boundaries only pause scheduling after a real
claim or after actual row/checkpoint durability; they never supply recognition.

Commit/push stubs/tests, read/persist compatible behavioral assertion RED, then
implement. A missing model, compile error, or zero executed cases is not RED.
Preserve all existing tests, pins, fixture bytes, and these new oracles.

## Required behavior represented by the cases

Replay only proven readable CAF samples not already covered by original finalized
rows. The first source is immutable synthetic prefix text; later source must be
produced by the actual CPU recognizer from the licensed speech's actual PCM16 CAF.
Original UUID/text/range/model revision and manual note never change. Keep the
crashed/recovered meeting recovered, never normally completed. A separate
transcription-replay checkpoint binds canonical meeting UUID, actual manifest
SHA256, pinned model revision, last committed sequence and global resume position.
Progress is durable before the scheduling callback; cancellation cannot roll back
committed originals or release admission before native drain/unload/model release.

CPUStreamingRecognizer requires its own continuous relative sample cursor starting
at0. Add the immutable global manifest/utterance base when saving segment ranges.
Contiguous healthy files are one continuous audio timeline; a genuine gap closes
the current stream and starts a fresh stream for the next healthy island. Never
feed fabricated silence across missing/corrupt intervals or count decoder-only
lookahead as durable audio. Manifest totalFrames is the sum of declared captured
segments, while timeline extent may include explicit gaps. Return actual durable
and replayed frame counts separately; corruption is quarantined with exact bytes.

The cancellation case pauses only after the first actual new finalized row and
durable checkpoint, cancels, verifies the real meeting claim remains held, then
reopens and finishes the second utterance without repeating committed IDs/text.
The admission case uses the real MeetingUsageRegistry and real deletion journal/
CAF quarantine in both directions. The minimal implementation may use the registry's
existing beginRecording/endRecording lease as a conservative exclusive per-meeting
replay claim; if a distinct named recovery lease is added, its actual shared-state
behavior requires the same tests and must not be an independent snapshot/set.
Use the same app-owned HeavyModelAdmission instance for streaming-ASR replay;
do not introduce a private gate that permits concurrent recording/summary models.

## Important inspected integration boundaries

MeetingRecoveryCoordinator currently persists a report whose equality includes
resumeFromSample recomputed from current transcript rows. Appending replay text
then blindly rerunning recover can reject that old journal as different. The first
case deliberately creates the real pre-replay recovery report and verifies
reopen/idempotence. Treat that report as bound filesystem evidence rather than a
mutable transcription cursor; revalidate actual manifest/files and own replay
progress separately. Do not disable existing journal-tamper validation or trust a
checkpoint as authority for moving files. Any necessary recovery change must follow
the reached actual RED and preserve every existing recovery assertion.

Persisted checkpoint/file ordering must tolerate an actual crash between row commit
and checkpoint publication: deterministic segment identity/row reconciliation must
prevent duplicates. Source ranges must be checked against actual surviving files,
not inferred from only header length or elapsed wall time. Protected atomic writes,
UUID paths, symlink/hardlink defenses, bounded CAF buffers/chunks, and real closed-DB
errors remain mandatory. These four cases are the initial replay slice, not full
crash-injection, checkpoint-tamper, path, startup integration, UI, or endurance proof.
