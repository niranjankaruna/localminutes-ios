# Documentation

Start with the [repository README](../README.md). The current delivery is
**version 1.0, build 6**, awaiting physical-device validation.

## Using LocalMinutes

| Guide | Contents |
| --- | --- |
| [Current build](MVP4_GUIDE.md) | Delivered source, IPA checksum, features, and limitations |
| [Windows installation](WINDOWS_INSTALL.md) | iLoader, free signing, Action Button, and weekly renewal |
| [Models](MODELS.md) | Supported formats, installation/import, and independent Equip choices |
| [Meetings and data](LIBRARY.md) | History, playback, export, deletion, backup, and recovery |
| [Summaries and questions](SUMMARIES_AND_QA.md) | Local generation, source links, editing, and cancellation |
| [Device checklist](MVP4_DEVICE_CHECKLIST.md) | Outstanding installation, offline, locked-screen, endurance, and renewal checks |

## Project contract and current state

- [Implementation goal](IMPLEMENTATION_GOAL.md) and [acceptance tests](ACCEPTANCE_TESTS.md)
  define requirements. The specification is not a statement that every gate passed.
- [STATE.json](STATE.json), [BACKLOG.json](BACKLOG.json), [progress](PROGRESS.md),
  and [blockers](BLOCKERS.md) hold the current checkpoint and exact next action.
- [Verification index](VERIFICATION.md) links actual results, including historical
  failures and the limits of each result. [Evidence](evidence/) retains TDD records,
  dependency receipts, publication approval, and delivery provenance.
- [Decisions](DECISIONS.md), [architecture records](architecture/),
  [dependencies](DEPENDENCIES.md), and [sources](SOURCES.md) explain the design.
- [Summary-model decision](SUMMARY_MODEL_DECISION.md) records a historical starter
  choice; the owner now chooses models and assesses their output manually.
- [Templates](templates/) provide TDD evidence and sanitized device reports.

## Historical material

Obsolete bootstrap prompts, superseded MVP guides, the duplicate Word brief,
and retired uncompiled drafts were removed during consolidation. Live fixture
helpers now live in [scripts/fixtures](../scripts/fixtures/README.md).
All active tests and dedicated evidence records are retained.
Earlier checkpoint snapshots and removed documents remain accessible in
[Git history at a314967](https://github.com/niranjankaruna/localminutes-ios/tree/a314967626b01b0a3a071eb61eb02b2d5d2320e8).
Historical evidence describes its recorded source and date, not current status.
