# Blockers

## OWNER_PHONE_VALIDATION_REQUIRED — BLOCKED_EXTERNAL

MVP4 build 6 is delivered and `READY_FOR_DEVICE_VALIDATION`. Owner-reported phone:
iPhone 17 Pro, iOS 27.0.1. Exact installed build, extension behavior, and all
physical acceptance results remain unreported. The main-app installation was
owner-reported with iLoader on 24 October 2026; that is not evidence for build 6,
the embedded extension, or renewal.

Pending gates: free signing and embedded extension; Live Activity display/Stop;
Action Button warm start, locked continuation and locked cold-start separately;
chosen models offline; two 125-minute recordings with 120 locked minutes each;
actual file protection/locked access; and in-place signing-renewal preservation.
All device result fields remain `NOT_RUN`. Report any unlock requirement explicitly.

Next: Owner validates delivered build 6 on iPhone 17 Pro / iOS 27.0.1: record installed version and a short recording saved by Live Activity Stop; then complete offline chosen-model use, Action Button warm/locked/cold-start, two 125-minute passes with at least 120 locked minutes each, storage protection, and in-place signing-renewal preservation. See docs/MVP4_DEVICE_CHECKLIST.md. Resume code work on a reproducible defect; do not rerun model-quality benchmarks.

No additional build can supply physical-phone evidence. No account/billing change
is needed for the existing unpublished-release delivery route. Actions-artifact
storage headroom remains unverified and is not used by that route. Model quality
is owner-manual; historical failures have not been turned into passes.

See the [device checklist](MVP4_DEVICE_CHECKLIST.md), [requirement handoff](evidence/MVP4_REQUIREMENT_HANDOFF.md),
and [current state](STATE.json). Earlier resolved implementation issues and
execution boundaries are recorded in [evidence/](evidence/) and the
[historical blocker log](https://github.com/niranjankaruna/localminutes-ios/blob/a314967626b01b0a3a071eb61eb02b2d5d2320e8/docs/BLOCKERS.md).
