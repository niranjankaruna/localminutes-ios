# LocalMinutes

A native iPhone app for recording meetings, transcribing speech locally, and
creating summaries and answers from your own meeting notes. Models run on the
phone; there is no required account, cloud inference service, or backend.

**Current delivery: version 1.0, build 7 — READY_FOR_DEVICE_VALIDATION.**
The app and Live Activity extension have been built on hosted macOS. Functional
and reliability evidence is recorded in the [verification index](docs/VERIFICATION.md).
Physical iPhone acceptance is pending, so the full project remains
`READY_FOR_DEVICE_VALIDATION`. Locked live transcription, Action Button behavior, two-hour
meetings, extension signing, offline phone use, and renewal persistence require
actual device evidence. Model quality is assessed manually by the owner.

## Install and use

1. Use the [current build guide](docs/MODEL_UPGRADE_BUILD7.md) to identify the delivered IPA,
   source commit, and SHA-256. Build artifacts are kept outside Git; the current
   delivery is an unpublished owner draft, not a public release.
2. Follow [Windows installation and seven-day renewal](docs/WINDOWS_INSTALL.md).
   Install with iLoader and a free Apple Account, keeping the app and extension
   identifiers when updating an existing installation.
3. [Install and equip a compatible speech model](docs/MODELS.md). A summary model
   is selected separately. Downloads need connectivity; meeting processing uses
   local engines after setup.
4. Start a recording, then use [meetings, playback, exports, backup and recovery](docs/LIBRARY.md)
   and [local summaries and questions](docs/SUMMARIES_AND_QA.md).
5. Record observations with the [device checklist](docs/MVP4_DEVICE_CHECKLIST.md).

## What is implemented

- Microphone capture, bounded audio queues, durable CAF segments, live transcript
  assembly, interruptions, and recovery.
- Independent speech and summary model installation, integrity checks, import,
  selection, and removal.
- Meeting history and search, manual notes, playback, text exports, full library
  backup/restore, and confirmed deletion.
- Local summaries and meeting questions with source references, editable
  generated text, saved answers, and cancellation/memory cleanup.
- Recording App Intents, Live Activity status and Stop, privacy controls,
  accessibility, sampled diagnostics, and storage metadata reports.

Implemented controls and hosted tests do not establish successful locked-phone
operation. See [acceptance requirements](docs/ACCEPTANCE_TESTS.md) for release gates.

## Repository layout

| Path | Purpose |
| --- | --- |
| `App/` | SwiftUI screens, services, navigation, and iOS adapters |
| `Core/`, `Recording/` | Recording lifecycle, queues, capture, storage policy, and metrics |
| `Models/`, `Transcription/` | Model lifecycle and local speech engines |
| `Persistence/`, `MeetingLibrary/` | SQLite, recovery, history, playback, and backups |
| `Summaries/`, `QuestionAnswering/`, `Intelligence/` | Grounded local generation and orchestration |
| `Shared/`, `LiveActivityExtension/` | Shared recording controls and the Live Activity target |
| `Resources/`, `Vendor/` | Privacy manifest, notices, and the ASR package wrapper |
| `Tests/` | Swift unit, integration, UI, actual-model, and physical-device tests |
| `scripts/` | Packaging, fixture preparation, and repository checks |
| `.github/workflows/` | Manual hosted macOS build and validation jobs |
| `docs/` | Current guides, specification, state, backlog, and evidence |

## Development and checks

The workstation is Windows 11. iOS compilation, Apple-framework tests, and
simulator tests run on GitHub-hosted macOS with Xcode 26.2. The app targets iOS 18
or later. `project.yml` is the XcodeGen project definition; generated Xcode
projects, native frameworks, downloaded models, and build output are ignored.
`Package.swift` defines the Swift modules and focused test targets.

Run portable script checks from the repository root with Node.js 24:

```powershell
node --test scripts/tests/*.test.mjs
```

These checks exercise packaging and test reporting. They do not compile Swift
or validate inference. Native checks under `scripts/native-tests/` and
`scripts/native-hygiene-tests/` require actual compiled products.

The manual workflow is [LocalMinutes build or validation](.github/workflows/core-tests.yml).
Choose its validation mode explicitly: `mvp4-final` exercises current functional
gates; the legacy `mvp` mode intentionally packages an older pinned source.
Native framework and licensed fixture preparation lives in
[scripts/fixtures](scripts/fixtures/README.md). Use standard hosted runners only,
one active run per branch, 45-minute job limits, and zero additional spend.

Read [AGENTS.md](AGENTS.md), [project configuration](project-config.json), and the
[documentation index](docs/README.md) before changing behavior. Preserve the
auditable tests-first sequence and use hosted macOS for compatible RED/GREEN
evidence. `main` is the sole retained branch after repository consolidation.

## Privacy and dependencies

Do not commit meeting recordings, transcripts, databases, model weights,
credentials, signed artifacts, or raw device logs. Inference runs in-process;
explicit model setup and owner-directed sharing are separate operations.
See the [dependency inventory](docs/DEPENDENCIES.md) and
[bundled third-party notices](Resources/THIRD_PARTY_NOTICES.txt) for runtime pins
and attribution. Third-party components retain their own licenses.
