# Continuation09 independent review regressions — inactive

DRAFT / NOT_RUN. Append these two fragments into the named existing test files
for the next test-first push. No new production code, assets, helpers, model pins,
inference doubles, or altered original assertions are required. Add both exact
test names to the core strict reporter; the owner case also belongs to the native
shared-source reporter. Obtain/read/persist actual hosted assertion RED before
repairing either implementation.

- `testInterruptionDuringHeldModelPreparationSettlesInterruptedAndAllowsReplacement`
  reuses `OwnerTestPreparation`, real owner/coordinator/capture/CAF helpers in the
  same RecordingSessionOwnerTests file. Append outside iOS-only conditionals so
  SPM and native tests both run it. Current owner calls coordinator.interrupt even
  before activation, while coordinator rejects that transition; the owner then
  clears its resource epoch but leaves coordinator .preparing. The test requires
  explicit interrupted cleanup while held, settled interrupted/no Saved/no late
  activation, and a replacement that actually reaches recording. Waits are
  bounded; held preparation is always resolved during cleanup.
- `testActualSequentialMeetingsReuseOneSessionWithIndependentMetricsEpochs`
  reuses actual pinned ASR assets, real temporary SQLite, actual CAF writer, and
  the existing same-file metric clock/feed helpers. One live-session instance and
  one injected recorder process two real meetings of different lengths. The
  second metrics snapshot must match its own manifest and contain no timestamp
  errors; both original transcripts must persist with real recognized text.
  Current recorder persists first-meeting cursors while each new meeting starts
  at source sample0, so instrumentation rejects all second-meeting inputs.

Review source locations at draft creation: Recording/RecordingSessionOwner.swift
330–333 and Core/RecordingCoordinator.swift122 for preparation interruption;
Transcription/LiveTranscriptionSession.swift35/95 and
Core/TranscriptionMetrics.swift120/137 for metric cursor reuse. These are source
findings, not executed test results. No physical Lock Screen, Action Button,
endurance, or diagnostics acceptance is inferred.
