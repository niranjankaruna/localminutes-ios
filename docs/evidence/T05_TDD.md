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

## Unit and sanitizer execution GREEN; overall CI FAILED

Fix source `c5b45a548afc445306b4eb04ec2af16eb20fd11b`,
[run39994364160](https://github.com/niranjankaruna/localminutes-ios/actions/runs/39994364160),
completed 23 October 2026 17:24 UTC. Actual results: **56 XCTest passed**, including
the two unchanged native-error regression tests; **51 Node tests passed**; **22
queue XCTest passed under Thread Sanitizer**, with no reported race or skip.
The 22 sanitizer cases are repeated executions, not additional unique tests.

The CI run nevertheless **failed**: its evidence parser accepts only the
`All tests` root while `swift test --filter` emits `Selected tests`. After the
successful 22-case sanitizer execution, it reported `Incomplete XCTest aggregate
summary`. The native-build job was skipped. No exact-source native app/archive
GREEN, new IPA, microphone, inference or device result exists at this source.
The last fully GREEN CI remains ca80375/run39987058071, with its older ephemeral
minimal IPA. T05.1/T05.2 remain IN_PROGRESS until the reporting gate and native
regression succeed. No acceptance or sanitizer check is removed.

## T05.2.1 selected-suite reporter regression — local test-first RED

Acceptance: recognize the actual filtered XCTest root while retaining strict
nonzero case count, required test names, skip rejection, matching counts,
failure status/assertions and complete aggregate checks. Never accept an inner
suite as a missing aggregate or mistake separate zero Swift Testing output for
XCTest success.

Eight new cases in `scripts/tests/verify-test-log.test.mjs` reproduce the observed
format. Windows11/Node24.21.0 command `node --test scripts/tests/verify-test-log.test.mjs`
executed 16 tests: **11 passed, 5 failed, 0 skipped**. Two valid selected roots
incorrectly throw `Incomplete XCTest aggregate summary`; name/count/failure
validation also stops at that wrong error. No parser production behavior is
changed. The exact committed source and repeat result will be recorded in the
checkpoint. Test-first changes cannot be pushed now without exceeding six runs;
push and preserve their hosted RED in the next invocation before implementing.

Committed test-first source: `35074aaf5009de2897ba7bf8d7fd3a48ceab624e`
(local only). Repeated the full portable suite at that exact source on Windows11,
Node24.21.0: `node --test scripts/tests/*.test.mjs` executed **59,54 passed,5
failed,0 skipped**, exit1. Existing filesystem and reporting checks pass; only
the selected-suite regressions fail. Sanitized local output is in ignored
`.agent-local/T05-reporter-local-red.log`. Matching native observation remains
run39994364160 at c5b45a5. The parser file is unchanged. No source fix, test skip,
CI suppression, seventh run or remote push occurs after the six-run boundary.
The checkpoint follows this commit; a future push must include both.

## T05.2.1 hosted RED — verified, continuation-03

Saved test-first35074aa/checkpoint were pushed unchanged with current cost
observation at **b04e9a4d3db270c4592bddee3566ffbd6f7d56dd**.
[Run39996675578](https://github.com/niranjankaruna/localminutes-ios/actions/runs/39996675578)
completed with failure on 23 October 2026 at about17:42 UTC: **56 XCTest passed;
59 Node tests executed,54 passed,5 failed,0 skipped**. Both valid selected-root
fixtures incorrectly throw `Incomplete XCTest aggregate summary`; count/name/
failure checks stop at that same wrong error. Compiler and test discovery work.
This confirms the saved Windows RED on hosted macOS before the production fix.
Sanitizer/native build did not run after the Node RED; no new artifact/device
result is inferred. Existing failed run39994364160 remains visible.

After that recorded/pushed RED, the one-line production change accepts exactly
`All tests` or `Selected tests` as aggregate roots. All case/name/count/skip and
failure consistency checks remain intact. Full Windows regression:59/59 passed,
0 failures/skips. The repaired parser also reads the actual archived22-case
sanitizer log from run39994364160 and returns22 passed/0 failed/0 skipped with
both required stress/drain names. This is log parsing, not a new native run.
Exact-source hosted full GREEN is still pending; push invocation run2 next.


## T05.1 / T05.2 / T05.2.1 full GREEN — verified

Source 4b639078337bd37e408cd1a4b58f268db35b2987, [run39997623318](https://github.com/niranjankaruna/localminutes-ios/actions/runs/39997623318), completed successfully 23 October 2026 at17:51 UTC. Committed workflow commands executed **56 XCTest,59 Node,22 repeated queue XCTest under Thread Sanitizer,2 native product checks and13 real packaging tests: all passed, zero failures/skips**. Converter fault regressions are unchanged. Device Release and simulator Debug app plus extension compiled with Xcode26.2/SDK26.2. Strict reporting now accepts the real Selected tests root without weakening validation.

Actual ephemeral unsigned IPA84,620 bytes, SHA256 583e42ac6560960b41c0cb23de0c80a4d5d44824ed4f3608bb2ad1253b3e1c9f, created17:50:56.825Z on runner; not uploaded, retained, delivered, signed or installed. This validates bounded owned handoff, real AVAudioConverter and CAF/manifest helpers within their tested scopes. Microphone lifecycle, locked capture, recovery, real inference and all phone gates remain pending. Parent T05 remains IN_PROGRESS; next T05.3 is test-first callback admission and real microphone runtime.


## T05.3 test-first activation — RED not yet observed

Acceptance: one callback claim per stable epoch, atomic close/quiescence and publication; late old callbacks rejected. Permission cancellation/denial, actual post-activation format, queue-dependent first-buffer signal, duplicate/stale requests, explicit preparation/start/input/write failures, stop drain before deactivation, real stereo48k-to16k mono conversion and actual16-bit CAF decode. Nine gate tests plus13 runtime tests activated with no-op interface stubs only; expected78 XCTest, not observed. Test files:Tests/CoreTests/CaptureCallbackAdmissionTests.swift and Tests/RecordingTests/MicrophoneCaptureRuntimeTests.swift. Command:swift test --enable-code-coverage on hosted macOS/Xcode26.2, then strict reporter. Hardware/permission alone are doubled; actual owned queue, converter and writer remain mandatory. No inference or device result is implied. Run3 next; no production admission/runtime behavior before actual behavioral RED.


## T05.3 RED — verified native assertions before implementation

Test-first source **f6e2b6d8296b4a0cdbc61616c6e4bc509a619c33**, [run39999604752](https://github.com/niranjankaruna/localminutes-ios/actions/runs/39999604752), completed23 October2026 at18:02 UTC. Command:swift test --enable-code-coverage, macos-15-intel/Xcode26.2. **78 executed,56 passed,22 failed,89 assertion failures,0 skipped**. All new9 admission and13 runtime cases failed; all prior cases passed. Gate returns closed instead of admitted and never becomes closed/quiescent. Runtime never requests permission, installs a tap, emits failure/readiness or performs real audio work; XCTUnwrap assertions identify the missing installed callback. Compiler/discovery succeeded; this is behavioral RED, not tool failure. Test-first commit was pushed before run and remains auditable. Node/TSAN/native were not run after Swift RED. Only now may production behavior be implemented.

T05.3 implementation after that RED: a single atomic gate linearizes entry/close and publishes callback exit. Stable tap context validates native format/time and copies through the preallocated queue; only atomic facts cross out. Public construction supplies no test pause hook. A serial worker owns actual native conversion, CAF writing and bounded polling/drain. MainActor runtime handles permission/cancellation, duplicate/stale IDs, resource failure, closed admission and callback quiescence, drain then deactivation then one stopped acknowledgement. Actual iOS-only adapter uses AVAudioApplication, AVAudioSession.record/measurement and AVAudioEngine, with no claimed callback join from stop/removeTap. Native implementation remains uncompiled until run4; all22 tests are unchanged. No new microphone, model, locked-screen or phone claim.
