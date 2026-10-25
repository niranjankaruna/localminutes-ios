# Progress

## T26/T27 implementation checkpoint

Latest exact source fe7aa94 / run 40215222725: 123 model tests, 122 passed, one new generic-discovery case failed (three assertions), zero skips. Raw/aggregate progress, Apple selection, pack install/equip and the 512 MiB regression passed; peak growth was 69,632 bytes. The new discovery assertion precedes its implementation. Real v2/v3 adapter, Apple composition/startup and iPhone UI verification remain pending. No new IPA or physical inference result is claimed. Next: focused native model-upgrades tests and startup binding after its behavioral RED. See T26/T27 evidence.

## Model format clarification — 25 October 2026

Source inspection at `ac26bec9ed68503371cce061a6e9d4d615f4bae5` confirms that
the Core ML adapter requires the complete pinned Parakeet v2 `.mlmodelc` set.
Direct `.mlpackage`/`.mlmodel` import and runtime compilation are not implemented.
The other adapters support the reviewed Zipformer ONNX set, Whisper GGML, and
compatible Qwen2/Phi3 GGUF. See [models](MODELS.md).
Latest existing CI run `40193408469` was re-read through the GitHub connector:
completed/success at `81fbff3a1bdf4ed17b757dd96d97486d9485254f`.
CLI authentication could not be verified; connector read succeeded. No code task,
test run, build, commit, artifact, or device result was added by this inquiry.
All physical gates remain pending. Next: owner validates delivered build 6 using
[the device checklist](MVP4_DEVICE_CHECKLIST.md); resume implementation for a
reproducible defect or an explicit new feature.

## Current checkpoint â€” 25 October 2026

MVP4 version 1.0, build 6 is delivered and `READY_FOR_DEVICE_VALIDATION`.
Overall project execution is `BLOCKED_EXTERNAL` on
`OWNER_PHONE_VALIDATION_REQUIRED`; `VERIFIED_COMPLETE` remains false.
The latest app source is `36bf6f4c8726fbc5d2efbfa4f740ef4031457233`.
Original [run 40190643613](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40190643613) remains FAILURE;
its passing functional groups combine with the unchanged-app, harness-only
[focused retry 40193408469](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40193408469), which passed one
answer-editing UI case with zero failures/skips. The IPA and evidence are in the
[build guide](MVP4_GUIDE.md) and [requirement handoff](evidence/MVP4_REQUIREMENT_HANDOFF.md).

## Repository consolidation â€” 25 October 2026

User requested preserving all branch work on main, deleting every other branch,
adding a README, and removing stale material. All six local and six remote branch
tips were inspected after fetch. `main` was 75 commits behind `task/t06-activity`;
fast-forwarded to `a314967626b01b0a3a071eb61eb02b2d5d2320e8`. Every other branch tip is its ancestor.
No rebase, squash, force push, or application behavior change was needed.

Documentation now has a root README, a current index, model and library guides,
and concise state/progress/blocker records. The five live native fixture helpers
were relocated to `scripts/fixtures/`; workflow and helper references follow them.
Obsolete bootstrap prompts, old MVP guides, the duplicate Word copy, and retired
uncompiled drafts are removed. All active tests, dedicated TDD/quality evidence,
dependency receipts, and ignored local delivery files are preserved.

Baseline before cleanup: Windows / Node 24.21.0, 62 script tests passed,
zero failures/skips. At cleanup commit `eeb9a5dc65a06ef11142c449e4a5e3170500eb69`, the post-cleanup script suite also
passed all 62 cases with zero failures/skips. The repository audit passed:
219 source/test files unchanged, all five helper imports valid, 163 documentation
links resolved, historical checkout paths valid, and acceptance/device contracts
unchanged. All five task branches were deleted locally and on origin after
verified push and ancestry checks. Local and remote main matched; the tree was
clean. `REPO_CLEANUP` is `VERIFIED_COMPLETE`. Details are recorded in [maintenance evidence](evidence/REPOSITORY_CLEANUP_2026_10_25.md).
The existing ignored build 6 IPA still matches its recorded SHA-256.
This follow-up checkpoint updates only documentation/status and Python line-ending
hygiene. No new CI run, iOS build, model-quality benchmark, or device test is
implied by these checks.

## Exact next action

Owner validates delivered build 6 on iPhone 17 Pro / iOS 27.0.1: record installed version and a short recording saved by Live Activity Stop; then complete offline chosen-model use, Action Button warm/locked/cold-start, two 125-minute passes with at least 120 locked minutes each, storage protection, and in-place signing-renewal preservation. See docs/MVP4_DEVICE_CHECKLIST.md. Resume code work on a reproducible defect; do not rerun model-quality benchmarks.

## Historical progress

Dedicated historical evidence remains in [evidence/](evidence/). Repeated earlier
checkpoint snapshots and their original results remain in the
[pre-cleanup progress log](https://github.com/niranjankaruna/localminutes-ios/blob/a314967626b01b0a3a071eb61eb02b2d5d2320e8/docs/PROGRESS.md).
