# T18.3 concrete pipeline test-first draft

These files are outside active source paths and use `.swift.pending` extensions.
They have not compiled or executed. No new working compiler/runtime/pipeline,
model download, prompt experiment, CI dispatch, Git operation or state change was
performed by this draft task. Current original four semantic oracles remain
unchanged. This is partial T18, not summary/Q&A or application completion.

Activation is a test-first operation in a later invocation after the current
workflow is terminal and the cost/run guard permits another source push:

1. Copy SummaryPipeline.swift.pending to Summaries/SummaryPipeline.swift and the
   three test files to Tests/SummaryTests/. Remove only `.pending` suffixes.
2. Apply the enum replacement/stub fragment in
   StructuredJSONSchema-NestedPatch.swift.pending to the existing type/compiler.
   Do not add a second enum definition. New object/array/nullable/Int64-enum
   cases throw unsupportedType; preserve every existing flat compiler assertion.
3. Add SummaryPipelineTests and NestedStructuredSchemaTests to required core
   filters and explicit case reporting. Anchor the class match: a substring
   `SummaryPipelineTests` also matches `ActualSummaryPipelineTests`. Ensure the
   actual-model class cannot enter the model-free core selection. Add ActualSummaryPipelineTests to the
   dedicated actual-Qwen job with normal pinned artifact verification. Keep all
   original six compiler and four semantic cases required. No skip/opt-in/cache
   replacement is allowed for the actual model.
4. Push/record compatible assertion RED before implementing any new behavior.
   Compiler failure, absent test, fixture setup error or copied file is not RED.

Required boundary cases (three):

```text
testPipelineMapsEveryChunkAndPublishesOnlyValidatedMergedContentWithProvenance
testLaterInvalidGenerationRejectsCrossChunkEvidenceAndPublishesNoPartialSummary
testCancellationAfterOneMapPublishesNothingAndReplacementCannotInheritOldEvidence
```

Required schema capability case (one, necessary before new compiler behavior):

```text
testBoundedNestedNullableCitationSchemaCompilesMetadataWithoutAnswerLiterals
```

Mandatory actual-Qwen pipeline case (one):

```text
testActualQwenMapsAndValidatesGroundedDecisionsActionsAndUnknownAttributes
```

The release API accepts source-selected UUID/immutable notes/segments and two
closures: the real runtime's promptTokenCount and typed generateJSON. Model
revision/prompt version are caller-owned provenance. A run uses the existing
tokenizer chunker, generates one map per chunk, validates each map against that
chunk's source IDs/ranges with GroundedSummaryDecoder, then deterministically
reduces with GroundedSummaryMerger against the full selected source. It publishes
one final result only after every map validates. Any later error/cancellation
must publish no partial result; replacement selection cannot inherit old IDs.
Concurrent calls are rejected with alreadyRunning rather than spawning workers.

Draft schema request: meeting_id is the selected UUID metadata; summary_points
and decisions are bounded arrays of text/evidence objects; actions are bounded
arrays of task/nullable-owner/nullable-due/evidence. Evidence objects contain the
chunk's supplied source-ID domain, Int64start/end metadata domains and an
unrestricted quote string that still must validate against actual source bytes.
Names, dates, task answers, points and decisions are not enum-seeded. The
compiler must bound recursion/array sizes/rule count/full UTF8 grammar size; none
of that new behavior is implemented in this draft.

Unit fixtures double only tokenizer/generated JSON boundaries, not inference.
Their artificial token counts force two chunks; actual production composition
must use the runtime's full canonical token counts. Original notes must be
serialized as MANUAL_NOTES_JSON before the existing EVIDENCE_JSON payload and
remain unchanged. Notes are context in this contract; the existing evidence
type supplies audio ranges only. Notes-only evidence needs an explicit future
source-kind/provenance adapter, not invented audio timing.

The actual integration loads and hashes the pinned real Qwen model and uses
actual native count/generation closures. A small non-sensitive meeting must
produce supported prototype/Friday decision and Leo/guide/Thursday action. A
separate explicit-no-owner/no-deadline fixture must yield a nonempty checklist
action with null owner/due and no invented decision. It cannot pass by merely
rejecting bad model output, returning empty actions or supplying expected
answers. Tests verify evidence quotes/IDs/ranges and model provenance without
demanding a particular paraphrase. Current decoder supports only extractive
quotes and bounded explicit commitments; it does not prove general entailment.
The real-model test may expose further model quality failures; preserve them.

After actual RED, implement only the bounded slice, run focused/regression and
actual-Qwen GREEN at an exact SHA, review and checkpoint. No physical protection,
Lock Screen, Action Button, endurance, signing refresh or completed product claim
follows from these component tests. Heavy-resource admission, app controls,
generated SQLite/editing/checkpoint persistence, sentence subdivision of oversized
atomic segments, full baseline summary behavior and Q&A remain separate work.
