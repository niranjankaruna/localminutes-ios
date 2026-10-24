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

First source `1a999b661ef68d4082b0a811d03ec40ef3180b7b`, run40104505380,
job120903281785 completed FAILED14:59:07UTC: one actual XCTest, three assertion
failures, zero skipped,140.207seconds. Candidate bytes/SHA and MIT license
verified; actual licenseSHA256
`fa8235e5b48faca34e3ca98cf4f694ef08bd216d28b58071a1f85b1d50cb814d`.
Native compilation succeeded. Stage observations:

- Q&A known budget: PASSED,56seconds; actual selected source42000credits.
- Q&A unknown owner: PASSED,39seconds; actual insufficient-evidence refusal.
- Positive summary: NOT_RUN for generation; preflight GroundedSummaryError.
- Unknown owner/date summary: NOT_RUN for generation; same preflight failure.

Only two actual generations occurred. This is a comparison-harness error, not
a measured Phi summary semantic failure: the harness supplied64-character
artifactSHA as modelRevision; unchanged provenance validation requires the
40-character immutable model revision. The first failure remains visible.
One focused correction uses the real immutable revision and a separate case
running only the two missing summaries, keeping all existing four-case and
semantic assertions. Q&A is not repeated. No prompt/model/validator changes.
This corrects the initial one-job plan while retaining the owner's one-model,
30-minute cap; follow-up job is bounded8minutes and must stop by15:13:11UTC.

No phone/signing/Lock Screen/Action Button/renewal or endurance gate is implied.
No fresh IPA is requested for this experiment. Final summary outcome pending.


Final follow-up: source6d914fe0117964c7019a71d5b9332c9dba3758b4, [run40105186439](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40105186439), job120905305903. Native compilation completed15:06:31UTC,130.24seconds. Eight-minute job budget cancelled execution15:11:06UTC; no completed XCTest or CANDIDATE_STAGE report is present. Both summary semantic outcomes remain NOT_RUN/unverified. No second candidate, Q&A repeat, third run, default switch or new IPA. Summary-only timeout is not a model-quality PASS or a measured semanticFAIL. Existing Qwen default failures remain. Completed feature taskIDs:none; overallIN_PROGRESS. Exact next: T18.3: inspect the bounded Phi summary runtime/generation path before further inference; the8min summary-only run40105186439 had no completed case/stage report. Preserve the2/2 actual Q&A observations, all original oracles and failed/timeout evidence. No automatic retry, new candidate, default-model switch or package. Resume a separately bounded implementation batch only when the owner resumes work.
