# MVP3 delivery work — 25 October 2026

Status: IN_PROGRESS. No MVP3 IPA is delivered yet. Owner resumed work with
GPT-6.1 Sol Medium for root and all subagents and removed the six-run hard cap.
Existing zero-spend, single-active-run and bounded-repair rules remain.

## Build correction and first actual remaining RED

Source: `b3f4e61181bdf81a0ab876e5defc3240513b7927`.
[Run40172670154](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40172670154),
standard hosted macOS/Xcode26.2. The Swift-tools6.2 package correction passed
compilation in the portable and current-Phi lanes. Native iOS build is pending.

RED tests were already committed and pushed in `50a4c68` before production
behavior. Command: the workflow's `core` job, `swift test --enable-code-coverage`
with the committed portable/ASR/persistence/intelligence filter. Job121106637096
executed 460 cases: 458 passed, 2 failed, 4 assertion failures, 0 skips,
263.217 seconds. A complete real XCTest run, not a compiler failure.

- `CoreMLParakeetRecognizerTests.testActualParakeetProductionDefaultRequestsCPUOnlyWithoutAnExplicitOverride`:
  actual loaded default policy was cpuAndNeuralEngine, expected cpuOnly.
- `MeetingContentStatusTests.testActualSQLiteStatusDistinguishesEachMeetingsTranscriptAndSummaryAndRemainsUnknownWhenUnreadable`:
  three status assertions returned unknown instead of the respective persisted
  transcript-only, summary-only and empty-meeting availability. Missing/closed
  database checks remained unchanged.

Smallest repairs: default adapter policy cpuOnly, and a single parameterized
SQLite inventory query inside the database actor. GREEN is pending. Native
screen and citation stubs remain untouched until their actual RED executes.

## Actual speech evaluation

Both fixed three-speaker, 116-reference-word corpus cases passed through the
real pinned engines, including deterministic 15 dB noise. Source and derived
audio hashes, measured SNR and error counts were emitted by the tests.

| Engine | Clean WER | Noise WER | Actual case duration |
|---|---:|---:|---:|
| Native Parakeet, explicitly CPU-only | 14/116 = 12.07% | 1/116 = 0.86% | 36.110 s |
| Streaming Zipformer, CPU, ASR-only sherpa package | 2/116 = 1.72% | 1/116 = 0.86% | 7.294 s |

The first clean Parakeet clip omitted 14 words even though the aggregate met
the existing 15% threshold. Do not describe all clips as accurate. The corpus
is short public audiobook audio, not owner-accent, technical meeting, phone,
locked-screen or endurance evidence. Existing model pins/oracles were unchanged.

## Pending GREEN and delivery

Native product/UI assertions, representative Phi evaluation, final iPhone
app/extension linkage, release fixture exclusion, unused-TTS symbol audit,
exact-source regression and independently verified IPA/checksum are pending.
All physical signing, Lock Screen, Action Button, two125-minute and renewal
gates remain NOT_RUN. Next: finish the active run, implement only proven missing
behavior, then verify and retain the passing package without repeating its
device compilation solely for download.
