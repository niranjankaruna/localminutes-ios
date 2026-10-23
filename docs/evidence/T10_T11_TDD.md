# Actual CPU recognition and live transcript composition

Tasks T10.1/T11. Requirements R05/R08/R09.

T10 test-first source4c520bdb82f6147ae667181bb0b534cadedb960a, pushed before
native production inference. Hosted run40033589101 uses pinned actual sherpa
1.13.8/C/ONNX dependencies, all four verified weights and licensed fixed speech.
Ten mandatory cases cover actual partial/final inference, endpoint reset,
cancellation, source continuity, dedicated worker, final decoder padding and
native unload/reload. Command: `swift test --enable-code-coverage` on standard
hosted macos-15-intel with Xcode26.2.

## T10 actual RED — before native behavior

Run https://github.com/niranjankaruna/localminutes-ios/actions/runs/40033589101
compiled/linked the pinned real runtime and all163 tests. All10ASR cases failed:
nine unexpected `notImplemented` load errors and two wrong-error assertions in
the missing-model case,11assertions,0skips. The actual verified speech fixture
was successfully opened by AVAudioFile before the stub errors. This proves
missing native adapter behavior, not a compile/fixture/tool failure. Native
production implementation was authorized only after reading these terminal logs.

The same run passed all15real SQLite tests. The installer passed18/23 cases;
five replacement cases failed7assertions because manifest validation compared a
replacement revision against unchanged download URLs. These failures remain
visible. The synthetic replacement fixture's revision is being made coherent
with its URLs while preserving every behavioral assertion and production
validation. Full run:163executed,148passed,15failed,18assertion failures,0skipped,
as independently checked by the strict reporter.
GREEN and native iOS compilation remain pending. Ignored log:
`.agent-local/T10-4c520bd-red.log`.

T11 next test-first slice adds actual CPU/SQLite model-lease composition,
converted audio delivery while capture runs, explicit failed ingress, and a
transcript persistence barrier before saved success. Only permission/hardware/
ActivityKit/held lifecycle boundaries may be doubled. Actual inference and
SQLite are mandatory in composition tests. No device outcome is inferred.

No native GREEN, iOS live transcription, signing, two-hour, Action Button,
locked-screen or renewal claim is made here. Raw audio/weights/logs stay ignored.

## T11/T15/T16/T09.2/T17 actual RED — before behavior

Test-first sourceb0cdd8ba4fdb3e3eb67d8f812937e50777db612b was pushed before
the new behavior. Terminal hosted run
https://github.com/niranjankaruna/localminutes-ios/actions/runs/40034410554
compiled/linked and executed202XCTest:153passed,49failed,104assertion failures,
14unexpected,0skipped. The strict reporter required all39new case names and
confirmed the aggregate. Command `swift test --enable-code-coverage` on
macos-15-intel/Xcode26.2. Actual model/framework setup succeeded, including the
verified real1.117GB Qwen and complete b5046 native framework. No fake inference.

Observed RED includes real live-preparation rejection,0-versus1920 converted
frames at the sink, accepted rejected ingress, owner Saved preceding held
transcript finalization, no-op notes failing durable reopen and schema1-versus2,
empty history/selected content, missing exports, nil playback locations/wrong
errors, transport `notImplemented`, and real-Qwen runtime `notImplemented`.
The missing-model live case passed, as expected. The ASR no-op still failed all
10cases because its production implementation was deliberately excluded from
this test-first push. All23installer tests now passed with coherent synthetic
replacement URLs; every original assertion and production validation preserved.

The explicit current-schema assertion evolved1→2 BEFORE migration implementation;
the new actual-v1 preservation/reopen case independently proves required migration.
No test was weakened/deleted/skipped. New implementation is authorized only
after this terminal evidence was read and persisted. Full GREEN is pending.
Ignored actual log: `.agent-local/T11-b0cdd8b-red.log`.

## Native behavior verified and large-buffer regression RED

Source2eaa5d607dd00d36e6c4ab90aef089b84d4bdbd3, hosted run
https://github.com/niranjankaruna/localminutes-ios/actions/runs/40035569538.
Core command selects all seven mandatory non-summary test modules; the separate
mandatory quality job executes all four real-summary cases at the identical SHA.
No skipped or ignored mandatory tests and no continue-on-error.

Core199executed,198passed,1failed,13assertion failures,0skipped. All10actual CPU
recognizer cases passed, including evolving actual speech, final plural word,
native version/CPU config, dedicated off-main worker, reset/cancellation and
unload/reload. Both positive actual live-ASR/SQLite composition cases passed,
including pre-stop text, durable reopened rows, global ranges and leased-model
release. All installer/transport/notes/history/export/real-CAF mapper cases and
existing regressions passed. The only failure is the new test-first
`testLargeConvertedBufferIsSplitIntoBoundedNativeChunksWithoutLosingSpeech`:
nine offers of up to6400frames rejected;0received versus56080 expected,0rows versus1,
captureUnavailable rather than successful flush, missing finalTENTS. This is
meaningful behavioral RED before chunk-splitting implementation, not tool failure.
New regression was committed/pushed before any splitting fix; implementation
is authorized only after this terminal evidence was read and persisted.

Summary quality4executed,2passed,2failed,4assertions,0skipped. Actual b5046 CPU
Qwen generated valid JSON but assigned Maya/Friday rather than Leo/Thursday and
the correct task. Unknown-budget/evidence validation and invalid-GGUF cases pass;
cancel/reuse fails only its unchanged semantic-owner assertion. Native quality
remains FAILED; no canned correction, changed expected owner or pass is claimed.

These are macOS results. iOS compilation, simulator screens, physical locking,
endurance and signing remain unverified. Full workflow is correctly FAILED.
Ignored actual log: `.agent-local/T11-2eaa5d6-validation.log`.

## Buffer repair and core regression GREEN — exact source

Source `7659a1980b53fc17d624973c6666d83084234ab6`, hosted run
https://github.com/niranjankaruna/localminutes-ios/actions/runs/40036438183,
core job120696963024 completed SUCCESS at23:00:51UTC on23October2026.
The test-first regression at2eaa5d6 was repaired only after its13-assertion RED
was read and persisted. The bounded implementation atbc903c3 retains one
admission across at most21copies, each at most3200frames, with continuous
source offsets, explicit queue failure, and drain-before-native-unload ordering.

Actual commands: `swift test --enable-code-coverage --filter
'(HarnessTests|CoreTests|RecordingTests|ModelTests|PersistenceTests|ASRTests|MeetingLibraryTests)'`,
`node --test scripts/tests/*.test.mjs`, and the workflow's repeated five-suite
`swift test --sanitize=thread --filter ...` command. Actual results:
199XCTest passed,0failures/0skips;59script tests passed,0failures/0skips;
85repeated sanitizer cases passed,0failures/0skips/reported races. Strict
case/aggregate reporters passed. The exact new large-buffer case passed in
6.953seconds with the actual model and fixed licensed speech. All10actual
recognizer and all4live-session cases passed, including missing-model refusal.

Parallel read-only review found no additional buffer lifetime/shutdown issue.
This is a core component GREEN, not full workflow or iPhone GREEN. At this
checkpoint native-build has started; its current app screens/SDK tests have not
yet produced results. The separate mandatory real-summary job at the same SHA
still failed:4executed,2passed,2failed,4assertions,0unexpected/0skips. The action
owner/task/deadline assertions remain unchanged (Maya versusLeo, missing guide,
Friday versusThursday). Reuse fails its owner assertion; an immediate cancelled
call did not fail the cancellation assertion. No in-flight cancellation proof
is inferred. Actual logs confirm CPU-mapped weights,0/29GPU layers and CPU KV;
Metal initialization messages mean no blanket absence-of-GPU-activity claim.

Ignored logs: `.agent-local/T11-7659a19-core.log` and
`.agent-local/T17-7659a19-quality.log`. Physical signing, locked continuation,
Action Button, offline iPhone inference, renewal and both owner-run125minute
passes remain NOT_RUN. No candidate artifact has been delivered.
