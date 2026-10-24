# TDD evidence record

Task/child ID: T18.1 tokenizer-based evidence chunk planning (partial T18).
Requirement IDs: R10.
Behavior being implemented: preserve ordered evidence IDs/global sample ranges
and complete sentence text while grouping atomic source segments under an
actual-model token budget; count the full canonical prompt plus reserved output.
Acceptance assertion: every accepted chunk has inputTokens+reservedOutputTokens
strictly below context, up to4096; an oversized atomic segment fails explicitly
rather than dropping, splitting through, or silently truncating its sentences.
Release composition must supply the actual pinned runtime token counter.

## RED — complete before production implementation

Test files:

```text
Tests/SummaryTests/SummaryChunkPlannerTests.swift
Tests/SummaryTests/ActualPromptTokenizationTests.swift
```

Six deterministic planner cases:

```text
testPlannerCountsWholePromptsAndReservesOutputStrictlyBelowContextLimit
testPlannerPreservesWholeSentencesSegmentIDsAndGlobalRangesWithoutLossOrReordering
testOversizedAtomicSegmentThrowsInsteadOfReturningAPartialOrTruncatedPlan
testUnicodeAndEmbeddedRoleTokensRemainSerializedSourceDataForTheTokenizer
testPlannerRejectsInvalidBoundsSourceIdentityRangesAndTokenizerCounts
testPlannerPropagatesTokenizerFailureAndCancellationWithoutPublishingChunks
```

One mandatory actual pinned-runtime case:

```text
testActualCanonicalTokenizerCountsBudgetBoundariesCancellationAndUnload
```

Minimal interface stubs: `Summaries/SummaryChunkPlanner.swift` declares immutable
source/chunk values, the tokenizer boundary, bounds and explicit error types;
`plan` checks Task cancellation then returns an empty array. The only new runtime
method is `promptTokenCount(prompt:)`, which checks cancellation then returns0.
No tokenization or planning behavior is implemented at this checkpoint.
Existing six schema compiler cases and four native semantic assertions remain
unchanged. Their previously authorized implementation is independent of these
new stubs and still requires its own exact-source GREEN.

The caller's prompt prefix is followed by a `EVIDENCE_JSON` payload. Tests decode
that actual JSON and compare original IDs, Int64global sample positions and UTF8
text, including combining forms, multilingual text, embedded role tokens and
newlines. Tokenizer doubles exist only at the unit boundary; they count complete
candidate prompts and exercise strict budget edges. This is not mocked model
inference. No semantic injection-resistance claim follows from JSON serialization.

The actual case requires the existing pinned Qwen artifact and b5046 framework.
It verifies actual model length and streaming SHA256 before entering native code.
A separate real vocab-only native model directly tokenizes the independently
formed full canonical envelope using b5046CAPI; it supplies the expected counts.
The app runtime must match counts for empty/simple/Unicode/control-token inputs.
An independently counted near-limit source verifies generation rejects
input+output=4096 and accepts input+output=4095. Actual model generation is
required below the boundary, but its JSON-shape assertion is capacity evidence,
not summary quality or answer-grounding validation. Oversized UTF8 input,
immediate cancellation and unloaded readiness remain explicit errors.

Exact command and platform: hosted macOS/Xcode26.2,
`swift test --filter SummaryChunkPlannerTests`; dedicated actual-model job also
executes `ActualPromptTokenizationTests` after its normal verified fixture setup.
SummaryTests needs access to binary module `llama` for its independent tokenizer;
root owns package/workflow/report inventory integration.
Source commit: PENDING root test-first commit.
CI run URL / sanitized local log: PENDING.
Executed tests / skipped tests: NOT_RUN; no skipped model gate is authorized.
Observed assertion failure: PENDING compatible execution.
Why meaningful RED is expected: empty plans lose required segments/never count
prompts or throw expected errors;0token counts cannot equal real vocabulary
counts and advertise no valid unloaded/oversized behavior.
RED commit pushed at: PENDING root operation; no implementation authorization yet.

## GREEN

Implementation commit: NOT_IMPLEMENTED for this new planner/counter slice.
Exact command and environment: PENDING.
CI run URL / sanitized result: PENDING.
Executed / passed / failed / skipped counts: NOT_RUN.
Real adapters or model exercised: planned actual Qwen/b5046 vocabulary and native
generation; no claim until execution.
Mock boundaries: tokenizer only in six unit tests, none in actual integration.
Regression suite and result: PENDING hosted strict inventories.

## Review and continuation

Refactor commit(s): none.
Fault injection: tokenizer error, suspended tokenizer cancellation, exact context
edge, malformed IDs/ranges, overlapping sources and nonpositive token counts.
Security/privacy review: only original public synthetic text; no meeting files,
private transcripts, model weights or credentials are committed. Actual runtime
formatter owns role-token escaping. Planner preserves complete atomic source
segments and errors on an oversized one; later sentence-level segmentation,
grounded summaries/actions, unknown-owner correctness, resume/checkpointing,
editing/provenance and Q&A remain mandatory separate work.
Remaining physical-device gates: all applicable gates, including both owner-run
125minute meetings, remain pending; no waiver or phone inference claim.
Next task: root pushes and proves meaningful planner/native-counter RED, then
authorizes bounded implementation and release composition with the real tokenizer.
