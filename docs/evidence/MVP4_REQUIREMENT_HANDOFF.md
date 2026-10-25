# Build6 requirement and evidence handoff

App source `36bf6f4c8726fbc5d2efbfa4f740ef4031457233`; version1.0/build6,
schema5. This is a bounded evidence audit, not a VERIFIED_COMPLETE claim.
Owner-reported phone: iPhone17Pro/iOS27.0.1. No phone result accompanies that fact.

| Requirement | Current evidence and limit | Remaining acceptance |
|---|---|---|
| R01 Windows/repository first | Bootstrap5767409; configured owner/remote, hosted macOS builds and Windows byte verification | No new bootstrap needed |
| R02 tests first | Historical task evidence plus MVP4 storage R7→R8 and final gaps R9→R10; original failures retained | R11 actual one-case PASS; exact app/harness/source guards reviewed |
| R03 unsigned app/extension | Build6 actual arm64 iPhoneOS app+Live Activity, SHA256/CRC/IDs/source/pins/notices verified | Owner free signing and working embedded extension |
| R04 recording | Compatible MVP3 functional checks plus build6 app-hosted regressions; capture lifetime owned by app services | Actual microphone permission/start/stop/saved playback |
| R05 locked live ASR | Real native engine history retained; CPU admission and capture/recovery checks | Recognition progress measured during locked interval; simulator does not prove it |
| R06 controls | Intent/activity contracts and latest-recording navigation evidence retained | Action Button warm, locked continuation, cold-start and Live Activity Stop separately |
| R07 two-hour reliability | Durable segment/backpressure/recovery/metrics checks; build6 memory-warning cleanup lifecycle checks | Two separate125min recordings, each120min continuously locked, with measured thresholds |
| R08 integrity/usability | SQLite/controller regressions; paged history/global title search/later transcript matches; playback, notes and deletion evidence | Phone interruption/recovery and data walkthrough |
| R09 models/offline | Actual local engines; verified install/import/remove/independent Equip, request-path privacy checks | Owner-selected model operation on phone with network disabled after setup |
| R10 summaries/Q&A | Actual local inference history retained; schema/evidence/isolation/controller checks and saved-answer CAS | R11 answer screen PASS; phone functionality and owner-manual output assessment |
| R11 renewal | Stable app/extension IDs and schema5; backup/restore and durable storage checks | In-place seven-day signing renewal with observed data/models/settings/shortcut preservation |
| R12 privacy/accessibility/docs | Native privacy/a11y regressions, compiled Release fixture exclusion, actual hygiene/notices; owner storage metadata report | Owner walkthrough and actual protection/backup/locked-access observations |

R10 is not model-quality PASS. The owner removed automated quality benchmarks
as a delivery gate; failed/cancelled historical model results are preserved.
Memory-warning tests exercise actual UIKit notifications and lifecycle boundaries;
they do not prove survival under physical memory pressure. Storage flags do not
prove locked access. A running Live Activity timer does not prove locked ASR.

## Existing automated batch and remaining focused retry

Run40190643613 is terminal FAILURE:76 related portable,46 script,116 app-hosted,
7 screen,3 actual-IPA hygiene and2 compiled fixture-boundary cases passed;
one answer UI case failed2 original-content assertions after test scrolling
missed the above-screen notes/transcript. No failures are hidden.

Run40193408469 uses harness81fbff3 with exactly the same app source36bf6f4,
verified by checkout/source-stamp/zero-production-diff guards. It overlays only
the repaired UI test and retains all original assertions, adding a visible
top-anchor precondition. Its terminal result is SUCCESS:1 actual case PASS/0fail/0skip in190.795s. APP_SOURCE36bf and TEST_HARNESS_SOURCE81fb are separately logged. The IPA is unchanged.

## Delivered files and next action

[Build6 guide](../MVP4_GUIDE.md), [Windows installation/renewal and Action Button](../WINDOWS_INSTALL.md),
[phone checklist](../MVP4_DEVICE_CHECKLIST.md), [device report template](../templates/DEVICE_TEST_REPORT.md),
[models](../MODELS.md), [backup/recovery](../LIBRARY.md),
[dependency inventory](../DEPENDENCIES.md) and [verification index](../VERIFICATION.md).
The guide describes privacy limitations, ordinary deletion and owner-directed
exports. The IPA directory contains the manifest, dependency receipt and checksums.

MVP4 development is delivered. The sole external prerequisite is owner
phone evidence, beginning with installed build6 and a short Live Activity Stop
recording. Do not declare the full baseline VERIFIED_COMPLETE while any gate
above lacks matching evidence.
