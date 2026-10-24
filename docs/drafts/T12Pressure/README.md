# T12 reserve/pressure/route/thermal: inactive test-first draft

Exactly four cases, uncompiled and NOT_RUN. No current production behavior,
phone result, physical pressure event, locked result or endurance pass is claimed.

1. `testOneGigabyteReservePrecedesActualModelPreparationAndAcceptsExactBoundary`
   uses a genuinely installed pinned model but denies 999,999,999 available bytes
   before actual Live preparation, database/directory creation, permission,
   Activity request or audio activation. Exactly 1,000,000,000 bytes admits real
   preparation without falsely reporting first-buffer recording readiness.
2. `testPeriodicLowStorageDrainsActualSpeechAndPersistsInterruptedWithoutSaved`
   feeds the existing licensed speech through real capture conversion, CAF,
   sherpa-onnx CPU and SQLite. A deterministic monotonic poll at 4,999,999,999 ns
   does not reread capacity; 5,000,000,000 ns observes the new low reserve. It holds
   real cleanup at the Activity boundary, requires `.storageFull`, durable
   `.interrupted`, exact decoded CAF frames/reference words, reopen durability,
   no Saved and no restart after capacity returns.
3. `testNativeInputRouteLossStopsCaptureButCategoryChangeAndEndedSignalsDoNot`
   posts real SDK notifications on an isolated NotificationCenter with only the
   input-availability query doubled. It ignores category activation and ordinary
   ended notifications, distinguishes output change from input loss, decodes real
   CAF after loss, rejects a late old tap, and refuses automatic restart on route,
   reset or interruption recovery.
4. `testNativeCriticalThermalSignalDrainsCAFAndDoesNotHonorLatePermissionOrRestart`
   posts the actual ProcessInfo notification using only the thermal query as a
   boundary. It drains actual CAF for active capture and rejects a held late
   permission grant for a replacement interrupted at critical pressure. Fair
   state and nominal recovery do not create start/stop churn or restart capture.

## Exact activation

- Apply only minimal declarations/unused fields in `ACTIVATION_PATCH.md`.
- Append `OwnerPressureASRTests.swift.pending` to
  `Tests/ASRTests/LiveTranscriptionSessionTests.swift`. Its helpers require that
  exact file's private LiveSessionFixture, waitForText, T12Speech helpers and
  current imports. Preserve every old method body. Existing model/audio setup
  and hashes remain mandatory; no new fixture/download or mocked inference.
- Append `NativeRouteThermalTests.swift.pending` after the final brace/conditional
  in `Tests/RecordingTests/RecordingSessionOwnerTests.swift`, preserving private
  owner helpers. Its `#if os(iOS)` excludes the two SDK monitor cases from SPM.
  Current LocalMinutesAppTests already compiles this file. No new app target or
  extension is necessary.
- Require the two new SPM/actual-ASR and two native names explicitly in existing
  log/xcresult checks and increase expected discovery counts appropriately.
  Setup, download, compilation, timeout-only, skip or zero-test results are not
  behavioral RED. Record exact SHA/run/assertions before production behavior.

## Deliberate boundaries and remaining work

One GB means 1,000,000,000 available bytes after installed weights already occupy
their disk space. This draft chooses the same initial configurable reserve for
start and periodic unsafe-space stop; it is a conservative policy, not a measured
two-hour storage requirement. A lower configurable threshold must never silently
undercut the specification minimum. Low-space capacity and time are controlled
boundaries; no test fills the CI disk or triggers genuine thermal throttling.

The proposed poll method tests deterministic periodic eligibility, not a running
app timer. Default file-capacity adapter, app-retained periodic scheduling,
background delivery/cadence, global clock reversal/query failure, cancellation,
stale poll completion and reserve configuration validation need their own tested
wiring before claiming production pressure coverage. No periodic Task is added
per audio buffer. Late polls/notifications must never select a newer epoch or
auto-restart capture. Serious-pressure performance adaptation and explicit
route-format/gap handling remain separate contracts.

The ASR cases permit 12-second bounded model operations; all held Activity/OS
continuations are released before fixture removal. Native cases use existing
one-second bounded owner helpers and generated owned roots. There is no actual
device storage/thermal/route evidence and neither owner-run 125-minute pass.

T13 follow-up remains separate: the real manifest runtime identifier is
`sherpa-onnx-1.13.8`; the current numeric-only diagnostics codec must get a
constrained reviewed `sherpa-onnx-` prefix rule after its native assertion RED.
Do not permit arbitrary runtime strings or alter that codec from this draft.
