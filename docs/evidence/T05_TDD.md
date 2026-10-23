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
