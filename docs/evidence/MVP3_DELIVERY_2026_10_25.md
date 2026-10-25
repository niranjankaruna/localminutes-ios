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

## First run terminal results

All three lanes finished. Native Release iPhone and Debug Simulator compilation
passed at b3f4e61. The two existing build-contract cases failed because their
expected build was still `1`, while both compiled bundles correctly identify
build `4`. The assertion is updated to the current explicit build `4`; identity,
version, architecture, platform and extension assertions are retained. This
harness failure prevented native product/UI execution, so those tests remain
unverified. No citation or screen behavior RED is inferred from it.

The actual arm64 app/extension package was created ephemerally (14,826,819 bytes,
SHA256 b9a89a266779be54f1c1090532364f25dfa49bd7ea53ebd357e3c1ab5b48de80).
All three real IPA hygiene cases passed, 0 failures/skips, 0.627 seconds:
source/receipt integrity, retained defined CPU ASR entry points, and absence of
unused eSpeak/Piper definitions. The artifact was not retained or delivered.

The Phi lane executed two real cases: basic selected-service summary/Q&A passed
375.208 seconds; the new representative case failed `unsupportedClaim` after
513.558 seconds. Its first raw map used exact valid source paragraphs and correct
Leo/Thursday values, but the schema enumerated whole paragraphs for action
tasks, forcing a conflict with the unchanged guard against paragraph-wide
ownership. Repair generation constraints, not that guard or the model oracle.
A deterministic sentence-schema regression is prepared next; expensive model
inference is not repeated during this focused test-first step.

Next run targets the pending native product/UI cases plus the schema regression
and existing status/progress tests. It does not repeat the real model suite.

## Focused summary regression RED and content-status GREEN

Test-first source `a1308e9283be1d89aa3025ca88fb8a0a43c7974d`,
[run40174152880](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40174152880),
portable job121111124093. `swift test --filter` selected the committed
RecordingProgressPresenter, TranscriptionMetrics, MeetingContentStatus and
SummaryPipeline cases. Actual result: 16 executed, 15 passed, 1 failed,
8 assertion failures, 0 skips, 0.857 seconds.

`testMultiSentenceSourceGrammarPermitsExactSentenceChoicesWithoutForcingParagraphOwnership`
failed 8 assertions in 0.798 seconds: four generated schema fields each offered
one whole 146-byte paragraph instead of the three exact 53/51/40-byte sentences,
and retained the paragraph. This is an actual assertion RED after successful
compilation, before the generation-schema repair. Unicode/source and nullable
attribute checks are retained. A supplied generation boundary exercises schema
construction and real decoding here; it does not substitute for the unchanged
mandatory real-Phi quality case.

The actual SQLite content-status regression now passes. Native product/UI lanes
are still active. No full model suite was repeated for this focused step.

## Focused native behavior results

Same a1308e9/run40174152880, job121111124337: 13 cases executed, 8 passed,
5 failed, 5 assertion failures, 0 skips, 1.767 seconds. Build-identity reader
returned nil (1 expected failure), citation target positives returned nil
(2 expected failures; invalid-citation negative passed), and both privacy cases
failed only their explicit hosting-root accessibility-hidden assertion. The
opaque cover, scene filtering and retained capture/CAF assertions were preserved.
All five latest-meeting cases, actual recording-progress composition, and the
four-shortcut SDK assertion passed.

Minimal implementations now prepared: real bundle metadata; validated complete
citation target with transcript-row selection/scroll and owned playback; explicit
hosting-root accessibility hiding alongside its UIKit window containers, with
exact original-state restoration. Native GREEN and screen-lane result pending.

## Actual screen RED and combined repair candidate

Same a1308e9/run40174152880, job121111124406: 7 UI cases executed, 2 passed,
5 failed, 20 assertion failures, 0 skips, 260.263 seconds. Real seeded library
loaded: editable summary/QA/isolation flow passed (80.315 seconds). Model action
reachability and 44-point targets at largest accessibility text passed (20.674
seconds); only repeated bare spoken labels failed (11 assertions). Required
recording explanations, build identity and history content labels failed their
7 missing-element assertions. These are genuine product RED, not fixture failure.

Two library-flow assertions failed because generated sections preceded the
transcript in a virtualized List, leaving transcript search/rows below the
initial viewport. Move existing generated sections after original transcript;
retain all original tests, saved content and citation callbacks.

Combined candidate implements only these gaps. Medium agents reviewed the final
changes; no concrete compile/data-handling issue was found by inspection. The
final milestone run will exercise actual models, native product and UI cases,
release fixture exclusion, device build and IPA hygiene together. Passing native
bytes are retained in an unpublished owner draft from that same build; delivery
still requires all mandatory lanes and independent Windows byte verification.

## Combined candidate 866935cb observations

[Run40175800050](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40175800050),
exact source `866935cb66445d485f35df9355c35945496b2b4f`:

- Core job121116095720 passed all 461 XCTest cases, 0 failures/skips,
  318.678 seconds; all 62 script cases passed. Separate Thread Sanitizer pass
  executed 88 cases, all passed, 0 failures/skips. The exact-sentence regression
  passed (0.002 seconds), and actual loaded default Parakeet CPU policy passed
  (0.598 seconds). Real corpus error counts matched the earlier observation.
- Native job121116095787 failed compiling the expanded SwiftUI history body
  (`LocalMinutesHomeView.swift:84`, type-check complexity). No product tests
  executed in that lane. First compiler-only correction extracts the existing
  list and row into smaller typed views, preserving content and navigation.
- Phi lane remains active; no outcome inferred.

Independent review also found a fresh-launch summary-selection binding bug.
Five native tests were pushed in `7a7f58b` before any behavior repair. They use
real selection files/installations and production controllers; synthetic invalid
GGUF bytes reject before inference, so these are routing checks only. Actual
native RED is pending. Do not deliver this candidate as completed MVP3 even if
the other model checks pass. Next: focused startup routing RED, smallest binding
repair, relevant GREEN and exact-source verified IPA.

## Correlated grammar regression RED

The 866935cb Phi run finished: basic selected-service case passed867.006s;
representative case failed456.684s on the first map. Quote selection was now
sentence-sized, but text could choose a different sentence and an action could
pair Leo's quote/range with Maya's source ID. The strict validator rejected these
mismatches. No output rewriting or validator relaxation.

Test-first source `45c9f0f79b00382768435009e7667427cee028e8`,
[run40178158700](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40178158700),
job121123256169: 25 executed,22 passed,3 failed,69 assertion failures,0 skips,
1.270 seconds. New compiler union tests found missing alternatives/Unicode
spelling and63 lost branches; the pipeline test failed all3 category assertions
because independent field domains did not bind complete tuples. A clearly marked
first-branch-only compileable stub supplied the necessary new type interface;
production mapping was unchanged until this actual RED.

Proper repair now prepares bounded whole-object alternatives and byte-exact
type reuse. Quote is selected first; its source ID/range and matching text/task
then follow as the same tuple. Nullable owner/due and every validator remain
unchanged. Full choice sets exceeding grammar/compiler bounds retain the existing
complete validated fallback, never a truncated subset. The earlier structural
schema test now traverses alternatives while retaining all exact-sentence,
Unicode, no-paragraph, nullable-attribute and source-preservation assertions.
Hosted GREEN and unchanged real-model quality case remain pending.

## Focused native startup RED and existing feature GREEN

Same45c9f0f/run40178158700, job121123256378:18 executed,14 passed,4 failed,
6 assertions,0 skips,1.797 seconds. All13 existing native product cases passed:
privacy2, citations3, latest-meeting5, progress1, bundle identity1 and shortcut1.
The five new startup cases included one legacy-default pass; four failed on
persisted alternative/explicit unequip and both first-controller-request paths.
The actual retained session was Phi instead of the verified selected artifact.
Synthetic invalid GGUF was never used as successful inference evidence.

Repair: one retained initialization task joins selection verification and binds
the session before generation captures it. Explicit unequip remains nil, missing
legacy selection retains the default missing-model flow, and busy restoration
stays retryable. No model inference is performed at startup. Tests unchanged.

UI job121123256440:7 executed,5 passed,2 failed,3 assertions,0 skips,273.641s.
History/search and notes now passed, along with spoken labels and both required
information cases. The remaining failures were navigation preconditions: QA
text field at y51.3 under the navigation bar was considered hittable but did not
receive keyboard focus, and partly visible AX5 buttons failed the full-frame
assertions. Test helpers now require complete visibility below navigation and
above tabs/keyboard and use bounded short real drags. No assertions, typing,
fixtures, production behavior or required tests were removed or weakened.
Actual harness GREEN remains required in the candidate run.

The next candidate batches these fixes with correlated grammar. Basic Phi and
representative Phi run as independent parallel45-minute jobs, keeping their
unchanged cases/oracles while avoiding a combined runtime timeout.

## Owner-directed functional delivery gate

On25October2026 at09:35UTC the owner explicitly requested functionality and
reliability checks instead of automated model-quality benchmarks, will choose
models and assess them manually, and will not use Phi-3 for summaries. This
overrides the automated quality gate for MVP3; it does not turn failures or
cancellations into passes or permit mock production inference. Existing quality
tests and their historical results are preserved. Phone gates remain pending.

Candidate `ceae957642ba20c6a9447ca314339e346f3f2aee` /
[run40180161772](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40180161772)
was cancelled at the owner's request while the representative quality job was
still active. The completed core lane passed464 cases,62 script tests and88
ThreadSanitizer cases,0 failures/skips. The real selected-service inference case
passed before cancellation. Those are retained observations, not a pass for the
cancelled representative case.

Native Release/device and Debug/simulator compilation passed. Device metadata
contracts2/2 and compiled release-fixture exclusion2/2 passed. Packaging13 cases:
12 passed,1 failed on a second old build assertion (`1`, actual currentbuild4).
The explicit expected value is corrected to4 without dropping any packaging
assertion. A repository sweep found no further build/version assertions in the
native/script tests. Real ephemeral IPA hygiene3/3 passed. Native app/UI cases
were not reached in this run; they remain mandatory.

Next `mvp3-functional` mode runs focused logic reliability plus the complete native
app/UI/build/package/hygiene gates and retains a passing IPA. It does not run
quality benchmarks or download their weights. Runtime/source/pin compatibility
with the completed ceae957 core and actual-inference observations is checked
explicitly; only test metadata, workflow scope and documentation changed.
