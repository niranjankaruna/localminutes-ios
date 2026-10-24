# TDD evidence record

Task/child ID: T18.2 grounded extractive summary domain/decoder/merge.
Requirement IDs: R10.
Behavior being implemented: keep generated summary points, decisions and nullable
actions separate from original selected-meeting evidence/manual notes; validate
exact support and deterministically merge map outputs without losing provenance.
Acceptance assertion: caller-selected meeting binding, known source IDs, exact
source global sample ranges and byte-exact quotes are mandatory. General
paraphrases are rejected in this extractive slice rather than asserted grounded.

## RED — complete before production implementation

Test file: `Tests/SummaryTests/GroundedSummaryTests.swift`.

```text
testExtractiveSummaryDecisionsAndNullableActionsRetainSourceAndManualTextExactly
testDecoderRejectsOtherMeetingAndUnknownSourceIDsBeforePublishingContent
testEvidenceRangesAndVerbatimUTF8QuotesCannotCrossOrNormalizeSources
testPresentNamesAndDatesDoNotSupportAnotherActionsOwnerDueOrParaphrase
testInvalidJSONDuplicateItemsOverflowAndExplicitLimitsCannotPublishPartialData
testMergeIsOrderIndependentAndRetainsEveryEvidenceAndProvenanceWithoutFillingUnknowns
```

Minimal interface stubs:

```text
Summaries/GroundedSummary.swift
Summaries/GroundedSummaryDecoder.swift
Summaries/GroundedSummaryMerger.swift
```

The first file declares immutable selected-meeting source, original manual-note
text, source citations/global sample ranges, caller-owned model/prompt/map
provenance, generated point/action/summary values, limits and typed errors.
It reuses `SummaryEvidenceSegment`. Decoder and merger both deliberately return
empty generated summaries. **No validation or working merge is implemented.**

The raw generation object has meeting_id, summary_points, decisions and actions.
Points contain text/evidence; actions contain task, nullable owner/due, evidence.
Citations contain source_id, start_sample, end_sample and quote. Caller metadata
supplies provenance; the generated JSON cannot certify its own model identity.

The exact extractive acceptance is deliberately narrower than arbitrary English
entailment. Point/decision text must be an exact supported quote, preserving UTF8
combining forms. Action task text must be verbatim support in its own cited
commitment. A nonnull owner needs an explicit speaker-labelled personal
commitment in that same quote (the synthetic accepted shape is `speaker: I will
...`); another mentioned person's name is insufficient. A due claim needs its
own explicit deadline phrase in that action quote, not a date borrowed from
another decision. When such support is unavailable, owner/due stay null.
These are bounded extractive validation rules, not a claim to prove every
semantic relation, decision classification or generalized paraphrase.

Malformed JSON, Int64 overflow, duplicate items/citations/source identities,
unknown IDs, cross-source ranges, stale/normalized quotes, unsupported claims,
invalid provenance and byte/item/quote limits must fail before publishing any
partial result. JSON duplicate-key token parsing is not added by this test
slice; duplicate coverage here concerns generated items/citations/source IDs.

Merge compares maps independently of input order, coalesces identical
extractive point text while retaining both citations and all caller provenance,
orders by source position and preserves nullable fields. Conflicting owner/due
attributes on the same supported action are an explicit conflictingClaim error;
it must not silently fill unknown fields or choose an answer. A map from another
meeting is rejected. Original map/source values remain separate and unchanged.

Exact command/platform: hosted macOS/Xcode26.2,
`swift test --filter GroundedSummaryTests`, included by root in strict core CI.
Source commit: PENDING root test-first source4.
CI run URL / sanitized local log: PENDING.
Executed tests / skipped tests: NOT_RUN.
Observed assertion failure: PENDING compatible execution.
Expected meaningful failure: empty decoder loses required content/provenance,
validation accepts invalid generation, empty merge loses supported evidence.
RED commit pushed at: PENDING root operation. No implementation authorized yet.

## GREEN

Implementation commit: NOT_IMPLEMENTED for this new domain/decoder/merge.
Command/environment/run/results: PENDING.
Real adapters or model exercised: none in this pure slice; no inference claim.
Mock boundaries: only original synthetic untrusted generated-JSON input.
Regression suite and result: PENDING compatible native/package tests.

## Review and continuation

Security/privacy review: fixtures are original fictional text; no model weights,
private meetings or credentials. Exact source ranges identify the full supplied
segment, not invented word timing. Evidence membership and valid JSON alone are
insufficient proof. Generated output has its own values and cannot replace
original user notes/transcript through this API.
Remaining physical-device gates: all applicable gates and both owner-run
125minute meetings remain pending.
Next task: root integrates/pushes these tests after the active workflow is
terminal, proves meaningful RED, then authorizes bounded validation/merge.
Actual Qwen map/reduce, nested-schema generation, complete-meeting sentence
segmentation, generated editing/SQLite retention, checkpoint resume, app model
admission and Q&A remain mandatory independent work, with actual-model tests.
