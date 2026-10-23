# T05.3 runtime test-first drafts

Status: **uncompiled drafts, NOT_RUN**. These .swift.pending files are outside
active Swift package and Xcode source paths. No runtime behavior is implemented,
no test RED/GREEN is claimed, and no microphone or device result exists.

The proposed activation paths are Recording/MicrophoneCaptureRuntime.swift and
Tests/RecordingTests/MicrophoneCaptureRuntimeTests.swift. Activate alongside the
nine callback-admission drafts in docs/drafts/T05.3/ only after the preceding
reporter fix has exact-source full CI GREEN. Commit/push and prove meaningful
hosted behavioral RED before implementing either runtime or gate behavior.

The interface exposes audio facts and cleanup acknowledgement to the existing
RecordingCoordinator. Its MainActor hardware and permission protocols are the
only doubles. The eventual separate serial worker must own the existing actual
OwnedPCMQueue consumer, PCMStreamConverter and SegmentCAFWriter. No injectable
converter/writer/queue or fabricated ActivityKit/recording success is provided.
stopped(id, manifest) follows callback quiescence, drain and deactivation; a nil
manifest conveys no successful media. Failure remains latched separately.

The 13 runtime tests cover denied/cancelled permission, post-activation native
format preparation, queue-dependent first-buffer readiness, invalid queue input
and timestamps, duplicate/stale lifecycle requests and old callbacks, explicit
activation/start failures, actual unsupported-format preparation rejection,
actual filesystem write failure, real 48 kHz stereo to 16 kHz mono conversion and
16-bit CAF decode, and an in-flight callback held across stop. The decoded CAF
check overwrites each borrowed input immediately to test owned copying. The
shutdown case verifies admitted samples survive, so stop/removeTap alone cannot
substitute for admission quiescence before queue.finish.

The internal afterAdmission hook permits deterministic test scheduling. The
public initializer always supplies nil. No production callback may block,
allocate, create tasks, lock, convert or perform file I/O. The test's callback
pause has one two-second deadline; lifecycle/event waits have one-second bounds.
Immutable synthetic AV objects cross a Dispatch boundary only inside an
explicit test ownership box; no AVAudioPCMBuffer is transferred in a Task.

The write-fault fixture replaces only this test's verified empty owned meeting
directory with a regular file. Cleanup is confined to the generated temporary
root and runs only after the runtime reports quiescence; an active failed test
retains its synthetic fixture rather than deleting data under a live worker.

An oversized queue input maps to explicit queueLoss failure and clean stop;
host-only AVAudioTime maps to invalidTimestamp. Neither may emit first-buffer
readiness. Unsupported native Int16 input is a preparation rejection, not a
pretend midstream native conversion error. Existing actual converter fault tests
remain responsible for that boundary.

Swift 6 compilation and native API behavior remain to be verified on hosted
macOS. These tests do not establish microphone permission UI, native tap timing,
device audio-session configuration, real-time performance, interruption/route
handling, live inference, free extension signing, Lock Screen/Action Button,
endurance or renewal. Those gates remain separately pending.
