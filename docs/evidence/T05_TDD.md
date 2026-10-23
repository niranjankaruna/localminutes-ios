# T05 capture pipeline — tests-first evidence

Task/child IDs: T05.1 and T05.2; parent T05 remains IN_PROGRESS.
Requirements: R04 and R08; architecture section 8.2/8.3.

Observable acceptance: owned, bounded planar PCM FIFO with explicit source-time
loss and once-only drain; real AVFoundation conversion to 16 kHz mono preserving
duration/signal across chunk boundaries; real 16-bit mono CAF segment contents,
rotation, idempotent flush, atomic manifest and explicit validation/I/O errors.

## Test-first preparation — not a RED or GREEN result

22 queue tests are in `Tests/CoreTests/OwnedPCMQueueTests.swift`. The tests include
actual parallel producer/consumer stress with bounded deadlines, capacity and
metadata allocation bounds, integer rollover, source ownership and loss accounting.
Five conversion tests and six writer tests use original generated tones/samples
in `Tests/RecordingTests/`. No microphone recording, private audio, model or mock
recognizer is involved. Writer tests open the real resulting CAF through AVAudioFile
and decode its PCM and persisted manifest; filesystem error uses an actual file.
Independent review additionally strengthened the cross-append sample comparison
and bounded a failed-count comparison to avoid unsafe fixture pointer access.
The test-only follow-up additionally verifies a closed CAF and persisted checkpoint
before final finish (rather than waiting until the whole meeting ends). It has
not yet been observed on hosted macOS. Expected follow-up count: 54 XCTest.

`Core/OwnedPCMQueue.swift` and `Recording/*.swift` contain only minimal interfaces
and deliberately missing behavior. No production queue, resampling or persistence
algorithm exists at this step. Swift is unavailable locally; static review and
Windows text checks cannot establish native compilation or RED.

Intended command: `swift test --enable-code-coverage` on standard hosted
macos-15-intel with Xcode 26.2 / Swift 6.2.3, followed by existing script regressions.
Expected XCTest count: 53 (20 existing + 22 queue + 5 conversion + 6 writer).
Actual source SHA, run, discovered counts and assertions remain pending.
CI run 2 of the current six-run invocation is next. Production implementation
must wait for meaningful native behavioral RED. A compile error does not qualify.

## Review and continuation

An independent bounded agent wrote the two queue test/interface files. Root
reviewed the contract and prepared conversion/writer tests and native wiring;
static review is not compiler or real-time performance evidence. The explicit
single-producer/single-consumer contract and ordering rationale are in
`docs/architecture/0001-owned-audio-handoff.md`.

Next: verify hosted RED, commit its evidence, implement the tested slices, then
require GREEN including real device/simulator compilation and existing archive
regressions. Microphone adapter T05.3 follows. Interruption/recovery, on-device
protection, models, signing, Lock Screen, Action Button, two long runs and renewal
remain NOT_RUN. No retained candidate artifact exists.

## RED — verified native execution, 23 October 2026 16:59 UTC

Source: `818481cc11d0c92b8a8d361d9441f82590f4ca98`, committed and pushed
test-first before any queue/converter/writer algorithm.
[Run 39990764814](https://github.com/niranjankaruna/localminutes-ios/actions/runs/39990764814)
completed with failure. Actual `swift test --enable-code-coverage` on
macos-15-intel / Xcode26.2 compiled and discovered all 53 XCTest: 20 passed,
33 failed, 139 assertion failures, 0 skipped. Existing coordinator/harness tests
all passed. Expected new test names were verified by the evidence reporter.

Examples: `testAcceptedPCMIsOwnedAndSurvivesSourceMutation` expected `.accepted`
but observed `.invalidBuffer`, then expected its chunk but observed `.empty`.
`testCapacityMustBeAPositivePowerOfTwo` expected a configuration error but none
was thrown. Conversion/writer positive paths caught `.notImplemented`, while
format and filesystem rejection assertions observed the wrong/no error. This
is executable missing behavior, not a toolchain or compilation failure.

Swift RED stopped the following Node command and skipped the native-build job.
There is no script-regression, native app, microphone, model or device result
from this run. The expanded 54-test writer follow-up must also be pushed before
implementation; it changes no production behavior and preserves this RED.

## Expanded writer RED — verified, 23 October 2026 17:03 UTC

Test-only source `bc4e1b7dfd3b09a977826462febcc1263e2cfbae` was pushed before
any writer behavior. [Run39991627557](https://github.com/niranjankaruna/localminutes-ios/actions/runs/39991627557)
compiled successfully and executed 54 XCTest: 20 passed, 34 failed, 140 assertion
failures, 0 skipped. `testCompletedSegmentIsReadableAndCheckpointedBeforeFinish`
failed with caught `.notImplemented`; the other writer/queue/conversion failures
remained visible. Node and native-build again did not run after Swift RED.
The actual result is saved before implementing writer behavior. Queue/converter
implementation began only after the earlier matching RED was verified.

## Implementation prepared — native GREEN pending

The conversion worker now averages planar channels explicitly and uses one real
AVAudioConverter per sample-rate epoch, respecting requested input lengths,
temporary input starvation and once-only final end-of-stream. It never resets
between chunks. Same-rate input still gets an owned mono copy. Worker allocations
and conversion are outside the planned real-time callback.

The serial CAF writer uses real AVAudioFile Float32-to-16-bit writes, a bounded
scratch buffer, approximately one-minute segments by default, explicit close and
file synchronization, and atomically replaced metadata for closed segments.
Append/finish/format/I/O state is explicit. No recovery or power-loss guarantee
is inferred from this code: T08 still needs reconciliation, fault injection,
database journal and protection-policy tests. The caller must supply an app-owned
session directory. No model, recording-only fallback success or device pass.

Primary API checks on 23 October: Apple's
[TN3136 conversion guidance](https://developer.apple.com/documentation/technotes/tn3136-avaudioconverter-performing-sample-rate-conversions)
and [AVAudioFile.close](https://developer.apple.com/documentation/avfaudio/avaudiofile/close()).
The latter is available from iOS18/macOS15, matching the project minimum, and
updates file headers on explicit close. Actual compilation and decoded sample
assertions, not this documentation observation, must establish native GREEN.

Queue implementation was reviewed against its actual diff and 22 original tests.
Preallocation covers samples and metadata; no heap-owning payload, collection,
task, lock, conversion or I/O occurs in enqueue/dequeue. Release/acquire ordering
includes reloading the write cursor after finish, preventing a stale empty read
from dropping a final published chunk. This is a code review, not a real-time
performance measurement. The next hosted run also executes all 22 queue tests
under Thread Sanitizer with the same strict nonzero/discovery/exit checks.

Independent review found a converter failure-state regression before first GREEN:
finish marks completion before its throwing native drain. A repeated finish can
then return an empty success after a lost tail. A deterministic native-boundary
fault test must prove RED before changing that state. Successful signal tests
continue to require real AVAudioConverter; the fault double is test-only.

Two regression tests now require native append/drain failure to remain explicit
on every later call without reentering the damaged SDK stream. A small internal
conversion-engine boundary permits deterministic SDK-error injection; the public
initializer always uses real AVAudioConverter. Failure-state behavior is unchanged
before this RED run. All 5 signal/format tests still use the actual native engine.
Expected count: 56 XCTest. Next is invocation run 4 of 6; assertions unverified.

## Regression attempt 1 — compiler failure, not RED

Source `e072a6f6b335313736780a89398391f868f39093`,
[run39993142381](https://github.com/niranjankaruna/localminutes-ios/actions/runs/39993142381),
failed compilation: AVAudioConverterInputBlock is Sendable in the actual SDK;
captured AVAudioPCMBuffer/self and mutable cursor locals were rejected. Zero
XCTest executed; no behavioral RED, GREEN, sanitizer or native result exists.
The JSON documentation declaration did not expose that annotation; the compiler
is authoritative. First compile repair moves input ownership/cursor into a
lock-protected callback context. The lock is solely on the conversion worker,
never the engine tap or queue producer. Public conversion remains serial-owned.
No terminal failure behavior is fixed before the fault tests actually run.
Next is run 5 of 6; the prior genuine 53/54-test RED remains preserved.

## Converter regression RED — verified, 23 October 2026 17:19 UTC

Source `ef6cad857ce22750ec359fb61cee660de303db62`,
[run39993877448](https://github.com/niranjankaruna/localminutes-ios/actions/runs/39993877448),
compiled and executed 56 XCTest: **54 passed, 2 failed, 5 assertion failures,
0 skipped**. All 22 queue, 5 real conversion/format, 7 real writer and 20 prior
tests passed. Only the two native-error boundary regression tests failed:
repeated finish did not throw; append returned `.finished` after drain failure;
the failed native engine was reentered 3 times instead of once. This is meaningful
RED after the compiler repair, recorded before the failure-state fix.
Node, sanitizer and native-build did not run after the Swift regression failure.
