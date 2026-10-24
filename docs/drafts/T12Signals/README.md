# T12.2 interruption/signal test-first draft

All `.swift.pending` files are **outside active build/test paths, uncompiled and
NOT_RUN**. No RED/GREEN or phone signal result exists. Intended activation is a
later test-first source after the current source5 work; this does not authorize a
CI run, production interruption behavior or automatic app wiring.

Exactly three draft cases:

1. `testOwnerInterruptionDrainsActualSpeechAndPersistsInterruptedWithoutSavedSuccess`
   uses the pinned licensed LibriSpeech fixture through real capture ownership,
   conversion/CAF, sherpa-onnx CPU inference and SQLite. It holds Activity end
   after actual final ASR/SQLite flush, requires `.interrupted` rather than Saved,
   keeps the real usage lease until combined cleanup, checks final reference
   words including TENTS, and reopens the real database. Only microphone/Activity
   boundaries are doubled. The model lease is checked during inference and after
   complete teardown; it need not remain loaded solely for Activity presentation.
2. `testNativeInterruptionNotificationDrainsCAFWaitsForCleanupAndRejectsOldTap`
   posts the actual AVAudioSession interruption notification on an isolated real
   NotificationCenter. It joins the application-held monitor, holds the existing
   transcript-finalization boundary, decodes real CAF bytes and invokes the
   retained old capture tap after cleanup.
3. `testNativeMediaResetCancelsPendingCaptureAndStaleEpochEndCannotDetachReplacement`
   posts the real media-reset notification during held permission, releases that
   old grant, and requires no old engine start. A replacement actual capture then
   remains monitored despite an old epoch's end command and is interrupted with
   readable CAF. This tests native notification routing, not a real OS reset.

## Exact activation changes, only when root selects this future source

- Copy `RecordingOwnerInterruption.swift.pending` to
  `Recording/RecordingOwnerInterruption.swift`. It is a compiling no-op method;
  do not add an interruption state/flush implementation before behavioral RED.
- Copy `IOSRecordingSignalMonitor.swift.pending` to
  `App/IOSRecordingSignalMonitor.swift`. Its observer/delivery/flush methods are
  deliberately no-op. No UIKit/AppIntents/real-device success is implied.
- Append `RealASROwnerInterruptionTests.swift.pending` **after the final brace** of
  `Tests/ASRTests/LiveTranscriptionSessionTests.swift`. This is an anchored fragment
  because `LiveSessionFixture` and `waitForText` are file-private. Add
  `import LocalMinutesMeetingLibrary` alongside that file's existing imports and
  add `LocalMinutesMeetingLibrary` to the ASRTests target dependencies. Reuse the
  existing mandatory, checksummed model/audio fixture setup; no new download.
- Append `NativeRecordingSignalTests.swift.pending` **after the final `#endif`**
  of `Tests/RecordingTests/RecordingSessionOwnerTests.swift`. The fragment has its
  own `#if os(iOS)` and uses existing private helpers. It adds two Simulator
  methods without changing any current method body or broadening its SPM tests.
- Require all three names in strict log/result reporting. Missing licensed model,
  audio, compile errors or absent tests are setup failures, never behavioral RED.
- Push/verify the test-first source and record actual assertions before behavior.
  This draft changes neither `Package.swift` nor workflows itself.

## Implementation boundary after future RED

The owner must latch the exact current epoch's interruption before any await,
revoke recording readiness, close/quiesce capture and drain the actual pipeline,
then finalize the real LiveTranscriptionSession with an explicit interruption
disposition. Its current `finish` writes completed, so merely calling ordinary
Stop would be an observable regression. Preserve normal Stop behavior with a
default completed disposition. Persist `.interrupted` as the final state; do not
briefly publish completed/Saved and overwrite the row afterward. Retain cleanup
retry and exact shared-token release through the Activity barrier.

Native observers must capture their original epoch before crossing executors;
late events must not select whatever recording happens to be current later.
Snapshot only primitive Sendable notification values. Media reset must not
silently recreate/restart capture or honor a stale permission grant. The monitor
is retained by the application, independently of views, with explicit teardown;
production observation/root wiring needs its own tested activation if not covered.

Route change, resumption gaps, low storage, thermal pressure, locked progress
instrumentation and both physical125-minute passes remain separate pending gates.
No claim is made about callback quiescence supplied by `removeTap` or actual OS
interruption delivery while locked.

Primary SDK references:

- [Apple handling audio interruptions](https://developer.apple.com/documentation/avfaudio/handling-audio-interruptions)
- [Apple interruption notification](https://developer.apple.com/documentation/avfaudio/avaudiosession/interruptionnotification)
- [Apple media-services reset notification](https://developer.apple.com/documentation/avfaudio/avaudiosession/mediaserviceswereresetnotification)
