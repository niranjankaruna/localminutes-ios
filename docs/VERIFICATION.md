# Verification index

## Main-only branch cleanup after build 7 — 25 October 2026

Completed BRANCH_CLEANUP_BUILD7: fast-forwarded main from ac26bec to 1706998, preserving all nine task-branch commits, then pushed main and deleted codex/parakeet-downloads locally and on origin. Fresh inventories show only main; the default branch is main. No force push, history rewrite, source/test change, rebuild or new CI run. Latest relevant native CI 40220308515 remains SUCCESS for delivered app source 6c02ccd. The build 7 IPA still matches SHA-256 4adfea3a38463b69423d58e4d8f1b2434f65ceeb2483e091eb26a0987ec0f967.

[Maintenance evidence](evidence/MAIN_ONLY_BUILD7_2026_10_25.md). Overall application state remains READY_FOR_DEVICE_VALIDATION; all physical-phone gates remain NOT_RUN. Next: Owner installs and validates delivered build 7 on iPhone 17 Pro / iOS 27.0.1 using docs/MODEL_UPGRADE_DEVICE_CHECKLIST.md and docs/MVP4_DEVICE_CHECKLIST.md; all phone inference, signing, Lock Screen, endurance and renewal gates remain pending.

## T26/T27 delivered — build 7

T26/T27 are CODE_COMPLETE_PENDING_DEVICE. Unsigned version 1.0/build 7, source `6c02ccdd911017a613de2052e5fee1e611b953f7`, is delivered locally in `.agent-local/delivery/build7-6c02ccd` and retained in an unpublished owner draft. Package: 15,088,983 bytes; SHA-256 `4adfea3a38463b69423d58e4d8f1b2434f65ceeb2483e091eb26a0987ec0f967`. [Build/installation details](MODEL_UPGRADE_BUILD7.md). Overall status is READY_FOR_DEVICE_VALIDATION, never VERIFIED_COMPLETE.

Exact-source model run 40220017845: 123 model and 67 script cases passed. Native run 40220308515, attempt 2: 15 actual v2/v3/Apple-JSON and 195 Core/storage/summary/coordinator cases passed; the original 12 app and six UI cases and the package jobs passed. All selected cases have zero failures/skips. Attempt 1's DNS setup failure remains recorded; only its failed model job was retried. The 512 MiB memory regression added 40,960 bytes of peak process memory. The actual downloaded IPA passed three native-hygiene checks on Windows, ZIP CRC, app/extension identity, v3 descriptor inclusion and receipt checks. Model weights and meeting files are absent.

The owner cancelled screenshots. All screenshot-only files were deleted, the existing Library UI test was restored, and no screenshot workflow was committed or run. Native Apple schema/composition checks do not claim Apple model generation. Full model-quality benchmarks and physical-phone gates were not run. Next: Owner installs build 7 over the existing app with iLoader, records its displayed version, checks retained v2/chosen v3 and Apple on-device inference offline, then completes Live Activity/Action Button/locked two-hour/file-protection/renewal gates using the device checklists.

## Model format source review — 25 October 2026

Read-only application inspection at `ac26bec9ed68503371cce061a6e9d4d615f4bae5`:
[the manifest](../Models/ParakeetCoreMLModel.swift) and
[runtime compatibility](../Models/ModelRuntimeCompatibility.swift) require the
complete reviewed Parakeet v2 `.mlmodelc` set; the
[recognizer](../Transcription/CoreMLParakeetRecognizer.swift) validates its exact
paths, sizes, and hashes before local loading. No `.mlpackage`/`.mlmodel` import
or compilation path is implemented. Other supported adapters are in
[the model guide](MODELS.md).
Latest existing CI run `40193408469` was re-read through the GitHub connector:
completed/success at `81fbff3a1bdf4ed17b757dd96d97486d9485254f`.
CLI authentication could not be verified; connector read succeeded.
No task completion, test execution, build, commit, artifact, or phone result is
claimed by this review. Device gates remain pending; next action is the owner
build 6 check in [the device checklist](MVP4_DEVICE_CHECKLIST.md).

## Current delivered application

Build 6 app source: `36bf6f4c8726fbc5d2efbfa4f740ef4031457233`.
IPA SHA-256: `08c00c22c0edd446ec0656a5695d9b05e20b7d1cc497f9186f57ec99cf00f2e0`.
Status: `READY_FOR_DEVICE_VALIDATION`; overall `BLOCKED_EXTERNAL`.

| Evidence | Actual result and scope |
| --- | --- |
| [MVP4 original batch](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40190643613) | FAILURE retained: 76 portable, 46 script, 116 native app, 7 UI, 3 actual-IPA hygiene, and 2 compiled-fixture checks passed; one answer UI case failed original-content assertions after test navigation. |
| [Focused UI retry](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40193408469) | SUCCESS: one answer-edit/navigation/relaunch case, zero failures/skips, 190.795 seconds. Harness `81fbff3`, exact unchanged app `36bf6f4`, zero production diff. |
| [Requirement handoff](evidence/MVP4_REQUIREMENT_HANDOFF.md) | R01â€“R12 mapping, composite evidence, original failures, and remaining physical gates. |
| [Build and checksums](MVP4_GUIDE.md) | Version 1.0/build 6/schema 5; unsigned app plus extension; local IPA verification and retained owner draft. |
| [Dependency receipt](evidence/MVP4_DEPENDENCY_RECEIPT_36bf6f4.json) | Exact recorded runtime sources and bundled notices for the delivered build. |
| [Device checklist](MVP4_DEVICE_CHECKLIST.md) | All physical gates NOT_RUN. Simulator/native compilation does not pass locked iPhone behavior. |

Automated model-quality benchmarks are not an MVP3 delivery gate under the owner's
25 October decision. Historical quality failures, actual results, and all active
quality tests remain preserved. No model-quality or phone PASS is inferred here.

## Repository maintenance

[Repository cleanup evidence](evidence/REPOSITORY_CLEANUP_2026_10_25.md) records
the completed `REPO_CLEANUP`: all branch tips merged, only main retained locally
and remotely, and cleanup commit `eeb9a5dc65a06ef11142c449e4a5e3170500eb69` verified on origin. The exact-source
portable suite passed 62/62, zero failures/skips. The audit found 219 protected
files unchanged, all five helper imports valid, and 163 relative documentation
links resolved. Historical model results and all device gates remain unchanged.
These checks do not create a new validated iOS artifact.

## Historical evidence catalog

Each record is scoped to its named source, date, platform, and actual result.
Old pending labels are historical; consult STATE.json for the current action.
Full earlier tables are available in the
[pre-cleanup verification log](https://github.com/niranjankaruna/localminutes-ios/blob/a314967626b01b0a3a071eb61eb02b2d5d2320e8/docs/VERIFICATION.md).

- [CI_INVOCATIONS.md](evidence/CI_INVOCATIONS.md)
- [CONTINUATION_08_CHECKPOINT.md](evidence/CONTINUATION_08_CHECKPOINT.md)
- [MODEL_CATALOG_AND_SUMMARY_2026_10_24.md](evidence/MODEL_CATALOG_AND_SUMMARY_2026_10_24.md)
- [MVP1_MODEL_DELIVERY_2026_10_24.md](evidence/MVP1_MODEL_DELIVERY_2026_10_24.md)
- [MVP2_RELIABILITY_2026_10_24.md](evidence/MVP2_RELIABILITY_2026_10_24.md)
- [MVP3_DELIVERY_2026_10_25.md](evidence/MVP3_DELIVERY_2026_10_25.md)
- [MVP3_DEPENDENCY_RECEIPT_880d3dc.json](evidence/MVP3_DEPENDENCY_RECEIPT_880d3dc.json)
- [MVP3_PRODUCT_GATES_2026_10_24.md](evidence/MVP3_PRODUCT_GATES_2026_10_24.md)
- [MVP4_ANSWER_UI_HARNESS_REPAIR.md](evidence/MVP4_ANSWER_UI_HARNESS_REPAIR.md)
- [MVP4_DEPENDENCY_RECEIPT_36bf6f4.json](evidence/MVP4_DEPENDENCY_RECEIPT_36bf6f4.json)
- [MVP4_FINAL_GAPS_TDD.md](evidence/MVP4_FINAL_GAPS_TDD.md)
- [MVP4_REQUIREMENT_HANDOFF.md](evidence/MVP4_REQUIREMENT_HANDOFF.md)
- [MVP4_STORAGE_AUDIT_TDD.md](evidence/MVP4_STORAGE_AUDIT_TDD.md)
- [MVP_DELIVERY_2026_10_24.md](evidence/MVP_DELIVERY_2026_10_24.md)
- [PHI3_SINGLE_COMPARISON_2026_10_24.md](evidence/PHI3_SINGLE_COMPARISON_2026_10_24.md)
- [SUMMARY_QA_BATCH_2026_10_24.md](evidence/SUMMARY_QA_BATCH_2026_10_24.md)
- [T00_BOOTSTRAP.md](evidence/T00_BOOTSTRAP.md)
- [T01_ENVIRONMENT.md](evidence/T01_ENVIRONMENT.md)
- [T01_PUBLIC_REPOSITORY.md](evidence/T01_PUBLIC_REPOSITORY.md)
- [T02_TDD.md](evidence/T02_TDD.md)
- [T03_TDD.md](evidence/T03_TDD.md)
- [T04_PRISTINE_PACKAGE_ORDER_TDD.md](evidence/T04_PRISTINE_PACKAGE_ORDER_TDD.md)
- [T04_TDD.md](evidence/T04_TDD.md)
- [T04_UPSTREAM_RESEARCH.md](evidence/T04_UPSTREAM_RESEARCH.md)
- [T05_TDD.md](evidence/T05_TDD.md)
- [T06_TDD.md](evidence/T06_TDD.md)
- [T07_ILOADER_INSTALL_2026_10_24.md](evidence/T07_ILOADER_INSTALL_2026_10_24.md)
- [T08_NATIVE_STARTUP_TDD.md](evidence/T08_NATIVE_STARTUP_TDD.md)
- [T08_RECOVERY_REVIEW_TDD.md](evidence/T08_RECOVERY_REVIEW_TDD.md)
- [T08_RECOVERY_TDD.md](evidence/T08_RECOVERY_TDD.md)
- [T08_SHARED_ADMISSION_TDD.md](evidence/T08_SHARED_ADMISSION_TDD.md)
- [T08_STARTUP_TDD.md](evidence/T08_STARTUP_TDD.md)
- [T08_T09_TDD.md](evidence/T08_T09_TDD.md)
- [T09_DOWNLOAD_INTEGRATION.md](evidence/T09_DOWNLOAD_INTEGRATION.md)
- [T10_CANDIDATE.md](evidence/T10_CANDIDATE.md)
- [T10_T11_TDD.md](evidence/T10_T11_TDD.md)
- [T12_FILESYSTEM_BOUNDARY_TDD.md](evidence/T12_FILESYSTEM_BOUNDARY_TDD.md)
- [T12_PRIVACY_TDD.md](evidence/T12_PRIVACY_TDD.md)
- [T12_T13_T18_T19_TDD.md](evidence/T12_T13_T18_T19_TDD.md)
- [T16_INTEGRATION_TDD.md](evidence/T16_INTEGRATION_TDD.md)
- [T16_PLAYBACK_TDD.md](evidence/T16_PLAYBACK_TDD.md)
- [T17_CANDIDATE_PAUSE.md](evidence/T17_CANDIDATE_PAUSE.md)
- [T17_FORMATTER_TDD.md](evidence/T17_FORMATTER_TDD.md)
- [T17_PHI_CANDIDATE.md](evidence/T17_PHI_CANDIDATE.md)
- [T17_STRUCTURED_SCHEMA_TDD.md](evidence/T17_STRUCTURED_SCHEMA_TDD.md)
- [T18_CAPACITY_FIXTURE_ISOLATION.md](evidence/T18_CAPACITY_FIXTURE_ISOLATION.md)
- [T18_GROUNDED_DOMAIN_TDD.md](evidence/T18_GROUNDED_DOMAIN_TDD.md)
- [T18_STRUCTURED_DECODING_EXPERIMENT.md](evidence/T18_STRUCTURED_DECODING_EXPERIMENT.md)
- [T18_TOKEN_CHUNK_TDD.md](evidence/T18_TOKEN_CHUNK_TDD.md)
- [T19_RETRIEVAL_TDD.md](evidence/T19_RETRIEVAL_TDD.md)
