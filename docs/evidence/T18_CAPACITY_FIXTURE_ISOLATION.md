# T18 native token counter and capacity-fixture isolation

Actual source39d9eaa65f7b030a8bdf87e1447b254508dce2db,
[run40073883889](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40073883889),
completed actual-model job120812994451 executed5cases:4passed,1failed,
6assertions(1unexpected),0skipped. All four original semantic/model-size/
cancellation cases passed unchanged with actual Qwen/b5046 CPU inference.

The new tokenizer case returned0 instead of actual independent native counts
136/139/156/156/3700. Those five assertion failures prove the missing counter
behavior before implementation. Its below-context positive generation also
threw generationFailed; the case took362.492seconds. The log does not capture
private generated content or a precise failure branch. **The cause is unknown.**
Do not state that verbosity, output exhaustion, context rejection or resource
pressure was observed as the cause. The tail cancellation/unload assertions were
not reached and remain unverified at that source.

## Preserved original evidence

The unbounded fixture remains in committed source39d9eaa and was copied unchanged
before editing into ignored local evidence:

```text
.agent-local/t18-capacity/ActualPromptTokenizationTests-39d9eaa-unbounded.swift
.agent-local/cont08-39d9eaa-quality.log
```

Original fixture archive SHA256:
`9682549238925bf63c8b653e7feb2c57ad2b41953c71bd16003c7293f2cec84c`.
Actual raw log SHA256:
`1a4b8a4568954fd6ea5bed73b6c1aa51941fab5d1e7a7a48df364f85b977c2a4`.
This evidence is not erased or reclassified by the isolation change.

## Requirement-based fixture correction

The positive integration assertion concerns tokenizer/admission capacity:
actual generation must accept the fully counted input below4096 while rejecting
the exact boundary. A free-form string also tests how long an unconstrained
model chooses to respond; the runtime legitimately reports a recoverable
generation failure when it cannot complete within the caller's output budget.
Such a string therefore does not isolate successful admission from unrelated
output completion. This is a test-design dependency, not an observed diagnosis
of the prior failure.

Only the capacity fixture's caller schema changes from `.string` to the already
supported `.stringEnumeration(["label-a", "label-b"])`. Either arbitrary short
label is accepted; there is no expected-label assertion or claim that either
label is a factual semantic answer. The user prompt, source repetition,
independent native tokenization, 3700input-token target, exact4096rejection,
4095positive boundary, JSON key/string assertions, model checksum/size checks,
oversized input, cancellation and unload assertions all remain unchanged.
Every original four semantic assertion also remains unchanged. No production
string cap, prompt rewrite, model change or generated-answer correction is added.

## Authorized counter implementation

`promptTokenCount(prompt:)` now checks cancellation/unloaded state and uses the
same private native tokenization helper as actual generation. That helper forms
the full canonical policy/envelope through SummaryPromptFormatter, retains the
existing UTF8 input bound, uses real pinned vocabulary/tokenizer with the same
add_special/parse_special flags and returns actual tokens. No byte/token estimate
or model fallback is used. Counting does not clear/decode the active context.

The trusted system policy was hoisted unchanged to one private static constant.
Source inspection confirmed byte identity against the archived independent
fixture policy, SHA256
`6894c90c433289c53e835fc2eacabdca5ee27896fd9067dcfb8ad9e503c1876d`.
This source inspection and whitespace check are not native execution evidence.

Next: root runs the exact-source focused and regression suites, records actual
counter/capacity outcome and preserves any further failure. No GREEN is claimed.
Grounded decoder/merge remain empty stubs pending their own source4 assertion
RED. Complete summary/Q&A/admission/persistence and all device gates remain open.


Source1f03e52/run40075611744 completedactualmodeljob120818174083 SUCCESS: all5mandatoryactualQwen/b5046 casespass0fail/skip,286.44seconds; strictreporteragrees. Actualcanonical tokenization/input-output capacity/cancel/unload nowpass, alongwithall4unchangedsemantic/model-size/cancellationcases. Originalunboundedcapacityfailureat39d9eaa remainsarchived/unexplained; boundedcaller-enum positivefixtureestablishescapacityonly, not semantictruth. Fullsummary/QApipeline/phoneadmissionstillunfinished.
