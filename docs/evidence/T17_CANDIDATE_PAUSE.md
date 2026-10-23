# T17 candidate investigation paused

Paused on the owner's instruction, 23 October 2026 UTC (24 October local time).
Root is checkpointing the goal. This worker started no candidate download or
new inference process. No owned subprocess is active and no partial candidate
download exists. No active application source, manifest, tests, Git state or CI
was changed by this candidate investigation.

## Findings saved before pause

The official publisher's
[Qwen2.5-3B-Instruct-GGUF revision](https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-GGUF/tree/7dabda4d13d513e3e842b20f0d435c732f172cbe)
is pinned to `7dabda4d13d513e3e842b20f0d435c732f172cbe`.
Published metadata reports artifact `qwen2.5-3b-instruct-q4_k_m.gguf`,
2,104,932,768 bytes and LFS SHA256
`626b4a6678b86442240e33df819e00132d3ba7dddfe1cdc4fbb18e0a9615c62d`.
These are **upstream reported** values; this worker did not download or hash
that artifact. The publisher labels it `qwen-research`; its
[pinned license](https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-GGUF/blob/7dabda4d13d513e3e842b20f0d435c732f172cbe/LICENSE)
states research/evaluation and noncommercial restrictions. It is not the
Apache 2.0 license used by the current 1.5B candidate. Root rejected this 3B
candidate for production selection and instructed that it not be downloaded.
This is a record of published terms, not a legal determination.

Available disk was observed as 546,299,559,936 bytes before any proposed model
download. Existing verified 1.5B weights and Windows CPU runtime remain under
ignored `.agent-local/qwen-research/`; no additional weights were downloaded.

An ignored evaluation script was prepared but **never executed**:

```text
.agent-local/qwen-research/measure_candidates.py
```

It still targets the rejected 3B candidate. **Do not run it** as a continuation
action. No comparative results were produced, and no candidate improvement,
native compatibility or device readiness is claimed.

## Exact next action after the owner resumes

Root first reconciles the running `cdf4a06` test-first CI and its formatter/
privacy assertions. Formatter and privacy behavior still require the root's
verified meaningful RED and implementation authorization.

If root resumes the separate candidate investigation, first verify an official
publisher's permissively licensed GGUF around 2–3 GB against actual pinned
`b5046` runtime support and published artifact metadata. Root suggested
Microsoft's Phi-3-mini-4k-instruct GGUF as a possibility; it was **not yet
investigated or accepted**. Review its actual tokenizer template and architecture,
then use the single unused candidate-download slot for a bounded comparison
with the unchanged original evidence plus renamed/reordered and unknown-owner
fixtures. Keep prompts, schema, decoding and evidence rubric fixed across the
comparison; record every failure and template/runtime difference. Do not change
the app candidate without measured improvement and a new native gate.

The original four actual-model semantic assertions remain unchanged. Both
owner-run 125-minute physical iPhone tests and all other physical-device gates
remain pending; this investigation supplies no device evidence.
