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
