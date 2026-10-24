# Single owner-authorized Phi-3 comparison

Owner selected one compatible local-model comparison, capped at 30 minutes.
Started 2026-10-24 14:43:11 UTC; absolute stop 15:13:11 UTC. One manual hosted
macOS job, four bounded actual CPU generations, no prompt-tuning loop and no
default application model change. Current app/Qwen quality remains FAILED.

Candidate: Microsoft Phi-3-mini-4k-instruct, MIT; immutable Hugging Face revision
`a64113399c2f6b8ad3e11c394733a2ddadaa7f33`, file
`Phi-3-mini-4k-instruct-q4.gguf`, 2,393,231,072 bytes, SHA256
`8a83c7fb9049a9b2e92266fa7ad04933bb53aa1e85136b7b30f1b8000ff2edef`.
Use the existing pinned llama.cpp b5046 framework. Phi's user-only template folds
the unchanged system policy into user content; native token counting and generation
share that envelope. Default Qwen behavior, pins and existing oracles are unchanged.

History is retained: earlier ignored Windows flat-schema Phi experiments failed
all three summaries; they did not exercise today's nested summary/nullable action
and selected-meeting Q&A flows with the current policy. This single current-format
comparison tests those four outcomes without erasing the earlier failures.

Planned observation: meaningful positive summary, unknown owner/date summary,
known selected-meeting answer, unknown owner refusal despite another meeting's
answer. Actual raw JSON and validators decide; mocks and rewritten output are
excluded. Existing fixture/manual-note/transcript bytes must survive reopen.

CI result: NOT_RUN at this checkpoint. Source/run and actual outcome will be
recorded after the single job. No phone/signing/Lock Screen/Action Button/renewal
or endurance gate is implied. No fresh IPA is requested for this experiment.
