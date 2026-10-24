# T17.3 explicit structured-schema API — test first

This API evolution preserves the existing actual-model correctness gate. It
does not normalize wrong answers, replace model inference, or claim summaries/
Q&A complete. No working schema compiler or schema-generation overload has
been implemented at this checkpoint.

## Preserved failure history and reason for this separate contract

The original generic JSON runtime's semantic failures remain authoritative:
source7659a19/run40036438183 executed4native cases,2pass2fail,4assertions,0skip.
The owner/task/due assertions failed on the actual pinned b5046/Qwen model.
Root subsequently reported the canonical-format generic path at d699fc5 still
failing quality (1of4passed,6assertions). Generic output syntax alone does not
establish action attribution or supporting citations. No original semantic,
model-length or cancellation assertion has been relaxed.

The bounded [T18 experiment](T18_STRUCTURED_DECODING_EXPERIMENT.md) first
recorded6actual-output research assertion failures, then changed only structured
decoding with the original user prompts, models, templates and CPU/greedy
settings. Its unchanged oracle improved to1pass5fail. Qwen's original fixture
generated the correct Leo/guide/Thursday/correct-decision/[s1,s2] object. Renamed
citations and unknown-owner correctness remained failed. This supports testing
an explicit caller-schema interface; it does not prove that interface on native
Swift or justify a model replacement or silent generic-API change.

## Test-first changes only

- `Summaries/StructuredJSONSchema.swift`: immutable ordered fields, value types,
  supplied string-enumeration domains, bounded grammar budget and typed errors.
  `grammar()` deliberately returns an empty String.
- `Summaries/LocalSummaryRuntime.swift`: one new
  `generateJSON(prompt:schema:maximumTokens:)` overload. It first checks Task
  cancellation, then throws notImplemented. The old generic overload's behavior
  is unchanged.
- `Tests/SummaryTests/StructuredJSONSchemaTests.swift`: six deterministic tests
  below, defining complete grammar/order/type/escaping and validation contracts.
- The original four `LocalSummaryRuntimeTests` keep every assertion, model-size
  check and original user prompt. Generation calls now explicitly supply the
  caller's ordered schema: action_task, action_owner, action_due, decision,
  budget_decided, evidence. Only evidence IDs are restricted to supplied
  [s1,s2,s3]; speaker, task, date and decision strings remain model-generated.

Case inventory:

```text
testCompilerPreservesCallerFieldOrderAndRequestedJSONTypes
testFieldsMustBeNonemptyUniqueAndSafeBoundedIdentifiers
testEnumValuesAreJSONAndGBNFLiteralsWithoutRuleInjectionOrUnicodeLoss
testEmptyScalarEnumFailsButEmptyEvidenceDomainAllowsOnlyAnEmptyArray
testGrammarByteBudgetRejectsInvalidLimitsAndNeverTruncatesACompleteGrammar
testFieldAndEnumerationCollectionsAreBoundedAndDuplicateValuesRejected
```

The enum test includes quotes, backslashes, a newline attempting to introduce a
grammar rule and non-ASCII text. A Foundation JSON encoding oracle supplies
literal expectations. Scalar enums cannot be empty; an empty evidence domain
permits only an empty array. Fields are unique ASCII identifiers of1–64bytes,
at most64fields. Enum domains contain at most256unique values, at most1024UTF8
bytes per value. The configurable full grammar budget is256–65,536UTF8 bytes;
overflow is rejected, never silently truncated.

## Compatible RED required

Hosted compiler/test source SHA and CI run: **PENDING**. Root must push the
test-first source and record actual compiler success plus meaningful failing
assertions/native notImplemented errors before authorizing implementation.
Suggested focused command is `swift test --filter StructuredJSONSchemaTests`;
the dedicated actual-model suite must still prepare and load the pinned real
model/framework and execute all four original semantic cases. Windows file
inspection/whitespace checks passed; no local Swift compilation is claimed.

Later implementation must compile only caller field names/types/source-ID
domains into valid GBNF, use the actual native model and retain cancellation,
fresh-context and CPU constraints. It must not embed answer literals or silently
correct citations. A grounded summary/Q&A pipeline and unknown-owner acceptance
need their own actual test-first work and remain mandatory. All physical-device
gates, including both owner-run125minute meetings, remain pending.

Test-firstsource917844b016664251c545fb70106c50cfceb62694 pushed/remoteverified; actualcompatibleREDpending run40071855360. No newworkingbehaviorbeforeactualassertions.

## Actual hosted RED, 2026-10-24

Source `917844b016664251c545fb70106c50cfceb62694`, run
[40071855360](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40071855360):
completed core job `120806812209` compiled and executed all six new schema
compiler cases. All six failed, 33 assertions, zero unexpected errors/skips:
empty grammar failed order/types/literals and validation did not throw.
Completed actual-model job `120806812055` prepared and loaded the pinned real
Qwen/b5046 CPU runtime, executed all four original quality cases, one passed
and three failed at the explicit new `notImplemented` overload (three errors,
zero skips). This is the expected behavioral stub RED, not semantic GREEN.
The existing original semantic assertions remain unchanged. Compiler/runtime
implementation may now follow; model correctness must still be proved.


## Actual native tokenizer RED and original semantic GREEN

Source39d9eaa65f7b030a8bdf87e1447b254508dce2db/run40073883889, completedactualmodeljob120812994451:5cases executed4passed1failed6assertions(1unexpected)0skip,419.35seconds. Every original4 Qwen semantic/model-size/cancellation assertion now passes with caller schema. No prior oracle was weakened. New actual tokenizer case returnsstub0 instead of independently measured136/139/156/156/3700 native tokens (five meaningful assertions), authorizing real promptTokenCount implementation. Its below-budget positive actual generation also throws generationFailed (unexpected error); absenceofprivateoutput prevents assumingthecause. The near-context fixture used an unconstrained string output and repetitive source; do not silently label it passed or change semantic oracles. Output-bound/test isolation needs a requirement-based auditable decision. Cancellation/unload tail assertions were not reached and remain pending.

Compiler6/6andoriginalnativequality4/4arecomponentGREEN atthisexactsource; fullmodeljob/workflow remainsFAILED fromnewcapacitycase. Fullgrounding/unknownowner/mapreduce/QA/phonevalidationremainmandatory.
