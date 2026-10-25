# Progress

## T26/T27 delivered — build 7

T26/T27 are CODE_COMPLETE_PENDING_DEVICE. Unsigned version 1.0/build 7, source `6c02ccdd911017a613de2052e5fee1e611b953f7`, is delivered locally in `.agent-local/delivery/build7-6c02ccd` and retained in an unpublished owner draft. Package: 15,088,983 bytes; SHA-256 `4adfea3a38463b69423d58e4d8f1b2434f65ceeb2483e091eb26a0987ec0f967`. [Build/installation details](MODEL_UPGRADE_BUILD7.md). Overall status is READY_FOR_DEVICE_VALIDATION, never VERIFIED_COMPLETE.

Exact-source model run 40220017845: 123 model and 67 script cases passed. Native run 40220308515, attempt 2: 15 actual v2/v3/Apple-JSON and 195 Core/storage/summary/coordinator cases passed; the original 12 app and six UI cases and the package jobs passed. All selected cases have zero failures/skips. Attempt 1's DNS setup failure remains recorded; only its failed model job was retried. The 512 MiB memory regression added 40,960 bytes of peak process memory. The actual downloaded IPA passed three native-hygiene checks on Windows, ZIP CRC, app/extension identity, v3 descriptor inclusion and receipt checks. Model weights and meeting files are absent.

The owner cancelled screenshots. All screenshot-only files were deleted, the existing Library UI test was restored, and no screenshot workflow was committed or run. Native Apple schema/composition checks do not claim Apple model generation. Full model-quality benchmarks and physical-phone gates were not run. Next: Owner installs build 7 over the existing app with iLoader, records its displayed version, checks retained v2/chosen v3 and Apple on-device inference offline, then completes Live Activity/Action Button/locked two-hour/file-protection/renewal gates using the device checklists.

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
