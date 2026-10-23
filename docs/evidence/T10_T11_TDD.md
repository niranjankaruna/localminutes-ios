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
nine6400-frameoffers rejected;0received versus56080 expected,0rows versus1,
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
