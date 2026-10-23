# Architecture and scope decisions

Initial defaults are specified in the goal document and `project-config.json`; they have not been empirically validated.

For each change record: ADR ID, date, affected requirements, options, constraints, evidence, selected option, consequences, tests to rerun, and owner approval when changing visibility, spend, or mandatory scope. Do not silently weaken acceptance to make completion easier.

## D01 — owner-approved public builds, 23 October 2026

The owner explicitly approved making LocalMinutes public to enable free standard
hosted macOS builds. Configuration and actual GitHub visibility are now public;
the original private bootstrap history remains accurate. Evidence and review:
docs/evidence/T01_PUBLIC_REPOSITORY.md. No paid/larger runner or billing change.
Keep TDD, bounded runs, privacy of meeting data and all physical acceptance gates.

## D02 — transcription priority and manual endurance operator

The owner directs a one-hour push with the maximum available three additional
agents. Prioritize actual model-based streaming transcription, verified model
installation and minimal real meeting persistence. Preserve the already tested
recording foundation and saved regression repair; control polish waits. Root
coordinates Git/CI; agents own bounded disjoint paths and tests-first work.
The owner runs the125minute physical-iPhone checks manually. Both required
passes stay pending until evidence; no duration, count or other criterion waived.
