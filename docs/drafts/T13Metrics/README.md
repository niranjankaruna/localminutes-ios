# T13 bounded metrics and private checkpoint draft

This is **test-first preparation only**. All `.swift.pending` files are outside
active build/test paths, uncompiled and NOT_RUN. There is no working recorder,
codec, pipeline instrumentation, diagnostics screen or device evidence. Activate
only in a later bounded invocation, prove actual behavioral RED, then implement.
No current CI run, source5/6 test set, state or workflow is changed by this draft.

## Exactly five proposed tests

- `testMonotonicProcessingAndPublicationFactsUseNanosecondsAndCorrectPositiveRTF`
- `testRecentLatencyAndCheckpointRingsAreBoundedWhileCumulativeCountersRemainExact`
- `testForegroundBackgroundCheckpointsPreserveActualProgressAndRejectClockReversal`
- `testDiagnosticsRoundTripKeepsOnlyPinsCountersAndEnumsAndRejectsPrivateFields`
- `testActualCPUConsumerPublishesPrivateMonotonicProgressBeforeFinalFlush`

The first four use a typed monotonic-clock boundary and synthetic metadata, not
inference. They check 25ms processing wall time /100ms audio =RTF0.25, exact cumulative
sample counts, invalid duplicate ranges, bounded recent p50/p95/max (nearest-rank),
ordered visibility checkpoints and rejection of clock reversal without changing
earlier evidence. Ring capacity is1...128. Snapshot inspection is nondestructive.

The fifth reuses actual pinned CPU speech inference, real SQLite/CAF and the
existing licensed `6930-75918-0000.flac` fixture. It uses real uptime, requires
nonzero metrics before Finish, exact processed/captured source samples afterward,
actual final TENTS, and writes/reads a real JSON checkpoint. It asserts that the
actual transcript and fixture path do not leak. A zero/no-op recorder cannot
satisfy these assertions while the unchanged real recognizer still runs.

## Data and privacy contract

- Use uptime nanoseconds, 16k sample positions and explicit processing start/end
  facts. Never derive processing time by subtracting Date or audio timestamps.
- RTF is accumulated processing wall time /processed audio duration. At zero
  processed samples it is nil. This is measured work duration, not a promise of
  physical real-time performance. Partial/final latency is publication uptime
  minus the queued-input uptime for the represented end sample.
- The captured counter here means normalized samples actually accepted at ASR
  ingress. Compare it with the real CAF manifest and explicit overflow/gap facts;
  it does not independently establish lossless hardware capture.
- Keep recent latency/checkpoint rings bounded while cumulative sample/work/error
  counters remain exact. A caller can checkpoint at a controlled cadence; do not
  serialize JSON or add per-buffer tasks in the audio callback.
- Export only schema version, forty-hex source/model pins, constrained runtime
  version/build number, counters, visibility facts, bounded latency statistics and
  enum error counts. Reject invalid identities, >64KiB payloads and unknown fields
  at every schema level, including transcript/audio/private paths/credentials or
  an invented `deviceLocked` assertion. The export API never accepts raw text,
  audio, database errors or arbitrary metadata for passthrough.

## Exact future activation

1. Copy `TranscriptionMetrics.swift.pending` to `Core/TranscriptionMetrics.swift`.
   Its public Sendable interface returns zeros/no-ops; codec throws notImplemented.
   Do not introduce recorder synchronization/statistics/validation before RED.
2. Copy `TranscriptionMetricsTests.swift.pending` to
   `Tests/CoreTests/TranscriptionMetricsTests.swift`.
3. Apply the **within-class replacement fragment**
   `LiveMetricsInitializer.swift.pending` to LiveTranscriptionSession: optional
   recorder field/initializer only, stored and unused. Existing init calls keep
   working. No actual consumer/ingress metrics calls are added before RED.
4. Append `RealASRMetricsTests.swift.pending` after the existing fixture in
   `Tests/ASRTests/LiveTranscriptionSessionTests.swift`; add `import Dispatch`.
   It relies on same-file private helpers. Existing mandatory licensed model/audio
   preparation and Core dependency already exist; no new download is required.
   The integration requires the actual `GITHUB_SHA`; a missing build identity is
   a setup failure and is never filled with a fabricated actual-source claim.
5. Root must add all five names to strict reports, commit/push test-first source,
   record actual compatible assertions, then authorize implementation. Missing
   assets/compiler or zero cases are setup failure, not RED.

## Device evidence remains pending

`.background` is an observed application visibility state, **not a locked-device
state**. The integration test explicitly sets a test marker on hosted macOS; it
does not validate any iOS scene-phase observer, notification delivery, locking or
two-hour operation. Future native scenePhase binding must have its own tests.

For an eventual owner125-minute pass, a future candidate must persist bounded,
redacted processed-sample/uptime checkpoints during the run and correlate them
with independent lock/unlock timing. A timer or final transcript after unlock
cannot prove ASR progressed while locked. Neither this draft nor desktop CPU
timing passes that gate. Clock reboot/restart mapping, periodic protected-file
checkpoint publication, export UI/approval, device memory/thermal/battery facts,
diagnostics retention and both required long runs remain unimplemented/NOT_RUN.

Use [DEVICE_TEST_REPORT](../../templates/DEVICE_TEST_REPORT.md) for owner evidence;
keep raw/local details private. No model weights, audio, meeting text, secrets or
real device logs are added by this draft.
