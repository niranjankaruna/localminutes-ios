# T18 bounded action-first structured-decoding experiment

Research only. No active Swift API, app manifest, acceptance assertion or model
selection is changed. The existing summary quality gate remains FAILED.

## Real-output RED recorded before the experiment

On24October2026, the actual six saved b5046 CPU outputs from
`T17_PHI_CANDIDATE.md` were reread and reevaluated against the unchanged frozen
semantic rubric. Six actual Python unittest cases executed; all six failed with
assertions,0errors,0skips, process exit1. This is research-output RED, **not**
hosted Swift/native TDD or a repair to application behavior.

Command, using the bundled Python runtime:

```text
python .agent-local/phi-research/baseline_semantic_red.py
```

Cases are testQwenOriginal, testQwenRenamedReordered, testQwenUnknownOwner,
testPhiOriginal, testPhiRenamedReordered and testPhiUnknownOwner. Each calls the
same unchanged evaluate function on actual output JSON, not stored pass/fail
flags, and asserts its complete semantic result. Actual assertion reports
include wrong owner/task/due and missing/incorrect support IDs. Full ignored
log: `.agent-local/phi-research/T18-baseline-semantic-red.log`.

## Single planned decoding change

Hypothesis: emitting the decision before the action anchors generation on the
decision speaker. Compare one grammar requiring fields in this order:
action_task, action_owner, action_due, decision, budget_decided, evidence.
The grammar names only those fields and their types. It includes neither
fixture-specific answers nor speaker names, dates, task words or evidence IDs.

All three exact user prompts, model-specific canonical templates/system-policy
handling, actual model bytes, b5046 CPU runtime and greedy settings remain
unchanged from T17. There will be one actual CLI execution per model/fixture,
no prompt rewrite, inference retry or download. The unchanged rubric will score
the actual outputs. The new grammar also enforces the six requested field types;
the prior generic grammar enforced JSON syntax only. Therefore any observed
effect must be attributed to this structured-decoding change as a whole, not
claimed to isolate field order from every other constraint.

Experiment inference/result was **PENDING** at this test-first checkpoint. The
actual result below was appended only after the baseline assertion RED and the
six bounded real-runtime executions.

## Actual result — partial improvement, quality still FAILED

Actual executions ran24October2026,06:41:20–06:41:57UTC. Grammar SHA256:
`fa9483d7f86006dc4bbcd6ead944ac7047b4e7fa8d4308d1796aea1c81b6c839`.
Baseline output JSON SHA256:
`fa406dca5e263af73d40b3882dd6b7e2575f9d0944aaaed7a54913038f52e94b`.
Pre-experiment real-output RED log SHA256:
`2f1d753c55c853175531716118f708e5da8e06e7343bd11d0942ae6c68aaf010`.

The same unchanged six-case semantic oracle executed again on the new actual
outputs: **6executed,1passed,5assertionfailures,0errors,0skips**. The sole full
pass is Qwen/original. All six actual CLI processes exited0, generated the six
requested keys/types in the required order, and used exactly the prior
canonical prompt files after checking their SHA256 against the baseline.
There was no retry, download, prompt/policy change or answer correction.

| Model / fixture | Actual task / owner / due | Actual evidence | Unchanged semantic result |
| --- | --- | --- | --- |
| Qwen / original | write the installation guide / Leo / Thursday | ["s1","s2"] | PASSED: also correct prototype/Friday decision, Booleanfalse, valid supporting IDs |
| Qwen / renamed/reordered | write the deployment checklist / Priya / Tuesday | ["[a9]","[a7]"] | FAILED: correct task/owner/due/decision, but bracketed IDs are not the supplied IDs; no stripping performed |
| Qwen / unknown owner | ship the dashboard / Nora / Monday | ["u4","u8","u3"] | FAILED: invented assignment, wrong task/due, decision shortened to "We decided" |
| Phi / original | ship the prototype / Maya / Friday | ["s1"] | FAILED: same wrong assignment, missing support and decision date |
| Phi / renamed/reordered | write the deployment checklist / Priya / Tuesday | ["a7","a9"] | FAILED: action/citations improved, but decision "dashboard shipping" omits Monday |
| Phi / unknown owner | ship the dashboard / Nora / Monday | ["u4"] | FAILED: invented assignment, wrong task/due/support and missing decision date |

Actual complete Qwen/original JSON:

```json
{
  "action_task": "write the installation guide",
  "action_owner": "Leo",
  "action_due": "Thursday",
  "decision": "We decided to ship the prototype on Friday.",
  "budget_decided": false,
  "evidence": ["s1", "s2"]
}
```

This is generated actual output, not a fixture answer substituted into inference.
Neither model is selected or declared product-ready from this result. The
original app runtime still uses its existing generic JSON API and its raw
quality gate remains FAILED. The renamed citations and unknown-owner failures
must remain visible; syntax constraints do not establish semantic grounding.

| Model / fixture | Process wall seconds | Prompt tokens/s | Generation tokens/s |
| --- | ---: | ---: | ---: |
| Qwen / original | 3.250 | 205.68 | 52.00 |
| Qwen / renamed/reordered | 3.344 | 192.43 | 52.98 |
| Qwen / unknown owner | 3.422 | 186.05 | 51.76 |
| Phi / original | 6.703 | 53.72 | 22.62 |
| Phi / renamed/reordered | 7.094 | 54.16 | 22.31 |
| Phi / unknown owner | 12.281 | 57.48 | 22.20 |

Same limitations as T17 apply: one-shot Windows observations, CLI load/whitespace
overhead, different actual model templates/system-role handling, and no iPhone
performance, iOS native-quality or physical-device evidence.

## Exact generic grammar used

The Boolean rule allows both values; strings/IDs are unrestricted strings.
No correct owner, task, date, decision or supporting ID is embedded in this
grammar. It applies unchanged to both models and all three fixtures.

```gbnf
root ::= ws "{" ws "\"action_task\"" ws ":" ws string "," ws "\"action_owner\"" ws ":" ws string "," ws "\"action_due\"" ws ":" ws string "," ws "\"decision\"" ws ":" ws string "," ws "\"budget_decided\"" ws ":" ws boolean "," ws "\"evidence\"" ws ":" ws string-array "}" ws
string-array ::= "[" ws (string ("," ws string)*)? "]" ws
boolean ::= ("true" | "false") ws
string ::= "\"" ([^"\\\x00-\x1F] | "\\" (["\\/bfnrt] | "u" [0-9a-fA-F]{4}))* "\"" ws
ws ::= [ \t\n\r]*
```

Ignored exact evidence:

```text
.agent-local/phi-research/baseline_semantic_red.py
.agent-local/phi-research/T18-baseline-semantic-red.log
.agent-local/phi-research/action-first-schema.gbnf
.agent-local/phi-research/run_action_first.py
.agent-local/phi-research/action-first/actual-results.json
.agent-local/phi-research/action-first/unchanged-semantic-oracle.log
.agent-local/phi-research/action-first/*-stdout.txt
.agent-local/phi-research/action-first/*-stderr.txt
```

No subprocess remains active. A next typed-schema API requires new hosted
native test-first acceptance, preserving every existing semantic assertion.
This measured partial improvement authorizes no silent change to the generic
runtime, fixture expectations, citation normalization or model selection.
