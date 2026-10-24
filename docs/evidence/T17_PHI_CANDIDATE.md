# T17 measured Phi candidate — no quality improvement

Observed 24 October 2026, completed at 06:32:16 UTC on Windows 11. This was a
bounded local comparison using original fictional meeting fixtures. It changed
no app model manifest, runtime, acceptance test or CI configuration. The
candidate is **not selected**: both it and the current Qwen baseline failed all
three complete semantic fixtures. No phone, signing, locked access, endurance
or iOS native-model result is established.

## Reviewed publisher artifacts and actual integrity

Official publisher: [microsoft/Phi-3-mini-4k-instruct-gguf](https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-gguf/tree/a64113399c2f6b8ad3e11c394733a2ddadaa7f33),
immutable revision `a64113399c2f6b8ad3e11c394733a2ddadaa7f33`. The public API
reported private=false, gated=false and license=mit. Its
[pinned LICENSE](https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-gguf/blob/a64113399c2f6b8ad3e11c394733a2ddadaa7f33/LICENSE)
contains the Microsoft copyright and MIT permission/notice terms. This records
published terms rather than making a legal determination. The publisher labels
the artifact Q4_K_M; actual GGUF metadata reports version3, architecturephi3 and
general.file_type15.

Exactly one candidate weight was downloaded into ignored workspace storage:

| Artifact | Actual bytes | Actual SHA256 |
| --- | ---: | --- |
| Phi-3-mini-4k-instruct-q4.gguf | 2,393,231,072 | 8a83c7fb9049a9b2e92266fa7ad04933bb53aa1e85136b7b30f1b8000ff2edef |

The actual length and streaming SHA256 matched the immutable publisher LFS
metadata before any inference. Transfer took21.985seconds; free disk before
transfer was551,649,869,824bytes. No login, credentials, paid service, server,
global installation, second weight candidate or weight commit was used.

Baseline: official Qwen2.5-1.5B-Instruct-GGUF revision
`91cad51170dc346986eccefdc2dd33a9da36ead9`, previously downloaded
`qwen2.5-1.5b-instruct-q4_k_m.gguf`,1,117,320,736bytes. Actual local SHA256 was
rechecked for this comparison and matched
`6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e`.

Both models ran with the official Windows AVX2 CPU asset from
[llama.cpp b5046](https://github.com/ggml-org/llama.cpp/releases/tag/b5046),
source `74d4f5b041ad837153b0e90fc864b8290e01d8d5`. Its
[exact architecture source](https://github.com/ggml-org/llama.cpp/blob/74d4f5b041ad837153b0e90fc864b8290e01d8d5/src/llama-arch.cpp)
and model loader contain PHI3 support. Actual CLI loading/generation below
established Windows compatibility; source inspection alone was not counted as
successful inference.

Runtime artifact `llama-b5046-bin-win-avx2-x64.zip`:18,137,485actual bytes,
independently computed SHA256
`5d534b910f803fd5d4e137edcd58ebeb225a6b6d046ab6b3813d2c0d0ee8dcaf`.
The release API supplied no upstream digest. Therefore this is an actual receipt
from the official HTTPS asset plus independently checked executable version,
**not** a match to a published runtime checksum. Actual `--version` reported
`5046 (74d4f5b0)`, MSVC19.43.34808.0/x64. ZIP paths were checked for traversal
and symlinks before extraction into ignored storage.

## Canonical template and fixed evaluation protocol

A Python standard-library GGUF parser read actual tokenizer.chat_template,
BOS/EOS IDs, token strings and BOS settings. No model output was edited or used
as instructions. Each model used its own actual canonical single-turn envelope:

```text
Qwen:
<|im_start|>system\n{unchanged app system policy}<|im_end|>\n
<|im_start|>user\n{unchanged fixture prompt}<|im_end|>\n
<|im_start|>assistant\n

Phi:
<s><|user|>\n{unchanged fixture prompt}<|end|>\n<|assistant|>\n
```

The actual Phi template emits BOS plus user/assistant turns and **ignores
system-role messages**. Qwen includes the unchanged app system policy. This
instruction/template difference is explicit: the experiment did not invent a
Phi system token, prepend instructions to its user evidence, or claim identical
effective system instructions. Phi stores literal newlines inside its Jinja
expressions; Qwen stores escaped newline text. One pre-inference harness
assertion incorrectly compared those representations and was corrected from
the actual metadata. No Phi inference had run at that point; completed Qwen
outputs were reused without a repeat. Neither prompts nor scoring changed.

Both models used the same b5046 executable and generic JSON GBNF, CPU layers0,
KV offload disabled,4generation/4prompt threads, context2048, batch/ubatch512,
maximum192output tokens, temperature0, seed7, temperature-only sampler chain,
no warmup and a fresh process/context per fixture. Automatic extra BOS was
disabled for both models because each canonical envelope owns its required BOS
placement. No conversation reformatting, context shifting, prompt cache,
remote model URL or inference service was used. Each process had a90second
bound. This is local-file inference evidence, not an OS-wide network-blocking
or iPhone performance measurement.

All six responses had exactly the requested six keys, required string action
fields, Boolean budget_decided and an array of string evidence IDs. Syntax
success was separate from correctness. The unchanged rubric required the
explicit commitment's owner, task and deadline, the actual decision and date,
budget_decided=false, and only supplied evidence IDs including the commitment's
supporting segment. The unknown-owner fixture required an explicit unassigned/
unknown string, never attribution to a speaker who did not accept the task.
No null-to-string conversion, bracket stripping, name repair or other answer
correction was applied.

The original user prompt was copied unchanged from the original native test.
It contains Maya's prototype/Friday team decision at s1, Leo's installation-guide/
Thursday commitment at s2, and the undecided budget at s3. Its UTF8 SHA256 is
`087777ecc1e22382720df8811d3afa7b45cda453ada774ae7c478d5d478ff451`.
The original four native semantic assertions remain unchanged.

The frozen renamed/reordered fixture puts Priya's deployment-checklist/Tuesday
commitment first at a7, the undecided budget at a2, and Omar's dashboard/Monday
decision last at a9. The third fixture has Nora's dashboard/Monday decision at
u4, Ethan's statement that the deployment checklist is needed byTuesday and
**nobody has taken it** at u8, and an undecided budget at u3. Both use the same
requested schema/instruction tail as the original. All exact prompts, canonical
envelopes, hashes and the frozen pre-output rubric remain in ignored evidence.

## Actual outputs and results

Every response below came from actual CPU inference. All six processes exited0;
all six full semantic checks failed.

| Model / fixture | Generated owner | Generated task | Due | Generated evidence | Complete semantic result |
| --- | --- | --- | --- | --- | --- |
| Qwen / original | Maya | ship the prototype | Friday | ["[s1]"] | FAILED: owner, task, due and support IDs |
| Qwen / renamed/reordered | Omar | ship the dashboard | Monday | ["[a9]","[a2]"] | FAILED: owner, task, due and support IDs |
| Qwen / unknown owner | Nora | ship the dashboard | Monday | ["u4","u8","u3"] | FAILED: invented owner and wrong task/due; cited IDs alone do not ground a claim |
| Phi / original | Maya | Ship prototype | Friday | ["s1"] | FAILED: owner, task, due and missing s2 support |
| Phi / renamed/reordered | Omar | Ship the dashboard | Monday | ["a9"] | FAILED: owner, task, due, missing decision date and missing a7 support |
| Phi / unknown owner | Nora | Ship the dashboard | Monday | ["u4"] | FAILED: invented owner, wrong task/due and missing u8 support |

Qwen generated the full decision text for all three fixtures. Phi generated
"Ship prototype on Friday", "Dashboard shipping decision", and "Dashboard
shipping on Monday" respectively; the second omits Monday. All outputs returned
Booleanfalse for the undecided budget. These limited successes do not pass the
action attribution/evidence gate.

| Model / fixture | Process wall seconds | Prompt tokens/s | Generation tokens/s |
| --- | ---: | ---: | ---: |
| Qwen / original | 3.000 | 218.80 | 53.09 |
| Qwen / renamed/reordered | 3.234 | 203.52 | 52.74 |
| Qwen / unknown owner | 3.391 | 201.15 | 52.50 |
| Phi / original | 6.406 | 61.47 | 22.61 |
| Phi / renamed/reordered | 6.703 | 59.21 | 22.53 |
| Phi / unknown owner | 12.313 | 59.54 | 22.14 |

Wall time includes model load, tokenization, generation and process overhead;
the CLI can continue emitting permitted trailing whitespace to its token limit,
whereas the app stops on its first complete JSON object. These are one-shot
desktop observations, not a controlled speed benchmark or app latency claim.
Actual runtime logs report0/29Qwen and0/33Phi layers offloaded. CPU KV buffers
were56MiB and768MiB respectively at context2048. Those buffer sizes are not peak
resident-memory measurements and do not establish phone memory suitability.

## Outcome and exact next boundary

The single candidate comparison is complete. **No measured improvement supports
replacing Qwen with this Phi artifact.** Both fixtures with explicit assignments
still select the decision speaker, including when the actual commitment is the
first segment, and both unknown-owner outputs invent an assignment. Keep
SUMMARY_ATTRIBUTION_QUALITY open, preserve every existing semantic assertion and
do not run another blind prompt repair or automatically download another model.

A next implementation task needs its own observable evidence-grounding contract
and tests before behavior, retaining the original correct-owner gate. A different
candidate also requires separate authorization and measured/native evidence.
No native app compatibility, summary/Q&A completion or device pass follows from
this rejected desktop candidate.

Ignored evidence paths (git check-ignore confirmed weights/results):

```text
.agent-local/phi-research/verified-receipt.json
.agent-local/phi-research/Phi-3-mini-4k-instruct-q4.gguf
.agent-local/phi-research/actual-gguf-metadata.json
.agent-local/phi-research/prepare_candidate.py
.agent-local/phi-research/compare_candidates.py
.agent-local/phi-research/comparison-fixed/frozen-fixtures.json
.agent-local/phi-research/comparison-fixed/actual-results.json
.agent-local/phi-research/comparison-fixed/*-canonical.txt
.agent-local/phi-research/comparison-fixed/*-stdout.txt
.agent-local/phi-research/comparison-fixed/*-stderr.txt
```

No evaluation subprocess remains active. Both owner-run125minute tests and all
physical-device acceptance gates remain pending and are not waived.
