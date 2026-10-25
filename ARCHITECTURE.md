# LocalMinutes architecture

LocalMinutes is a SwiftUI iPhone application with local recording, speech recognition, meeting storage, and post-recording intelligence. Its central constraint is ownership: asynchronous work must retain the exact recording session, meeting, model installation, and resource lease that authorized it. A late callback must not mutate a replacement session or another selected meeting.

Build and test instructions are in [README.md](./README.md). This document describes the current implementation rather than a roadmap or historical milestone record.

## Structure and composition

[LocalMinutesApp](./App/LocalMinutesApp.swift) presents an application-lived [RecordingApplication](./App/RecordingApplication.swift). [LocalMinutesServices](./App/LocalMinutesServices.swift) composes persistence, model installation and selection, transcription, meeting operations, intelligence, and diagnostics. Views observe these controllers; they do not own microphone or native-model lifetimes.

```mermaid
flowchart TD
    UI[SwiftUI views and App Intents] --> App[RecordingApplication / LocalMinutesServices]
    App --> Owner[RecordingSessionOwner]
    App --> Library[Meeting library controllers]
    App --> Models[Model installation and selection]
    App --> Intelligence[IntelligenceSession]
    Owner --> Capture[Audio capture worker]
    Capture --> CAF[Segmented CAF audio and manifest]
    Capture --> ASR[LiveTranscriptionSession / Parakeet Core ML]
    ASR --> Store[SQLiteMeetingStore]
    Library --> Store
    Library --> CAF
    Intelligence --> Summary[Summary pipeline / question answerer]
    Summary --> Store
    Summary --> Runtime[llama.cpp or Apple Foundation Models]
    Models --> ASR
    Models --> Runtime
```

[Package.swift](./Package.swift) exposes nine Swift libraries for macOS testing. [project.yml](./project.yml) compiles the same directories directly into the iOS app; conditional `SWIFT_PACKAGE` imports support both arrangements.

| Directory | Responsibility |
| --- | --- |
| [App](./App) | Composition, SwiftUI screens, intents, iOS signals, playback ownership, privacy cover, and system metrics |
| [Core](./Core) | Recording state machine, bounded audio queues, resource admission, filesystem policy, archive format, and metrics contracts |
| [Recording](./Recording) | Microphone/audio-session boundaries, conversion, CAF writing, recording owner, and intent routing |
| [Models](./Models) | Immutable manifests, compatibility assessment, transfers, imports, installation leases, and selections |
| [Persistence](./Persistence) | Actor-owned SQLite connection, schema migrations, notes, transcript rows, generated documents, model pins, and checkpoints |
| [MeetingLibrary](./MeetingLibrary) | History, selection, edits, playback mapping, exports, startup reconciliation, recovery, deletion, and library replacement |
| [Transcription](./Transcription) | Parakeet TDT Core ML adapter, live transcription, and checkpointed transcription replay |
| [Summaries](./Summaries) | Native local-language runtime, JSON schemas, token planning, evidence validation, summary maps, and deterministic merge |
| [QuestionAnswering](./QuestionAnswering) | Selected-meeting evidence retrieval, bounded prompts, and exact-quote answers |
| [Intelligence](./Intelligence) | Inference lifecycle, cancellation, commit admission, summary resume, and Apple Foundation Models adapter |
| [Shared](./Shared), [LiveActivityExtension](./LiveActivityExtension) | Recording activity state, scoped Stop control, and WidgetKit presentation |

The extension presents recording state; it does not capture audio or load models. The app and extension share activity attributes and control definitions.

## Ownership and concurrency

UI-facing controllers and application composition run on the main actor. SQLite and model installation each have actor isolation. Parakeet recognition and local-language generation serialize their work behind their adapters. The microphone callback communicates through bounded queues rather than starting asynchronous tasks.

[HeavyModelAdmission](./Core/HeavyModelAdmission.swift) permits one heavy use at a time: live ASR, summary, question answering, or library maintenance. Its lifecycle is `idle → admitted → draining → idle`. A cleanup failure leaves it `cleanupBlocked`; a later retry completes the outstanding cleanup before allowing another use. Cancellation alone does not release the resource.

Meeting usage leases additionally protect recordings and maintenance from deletion races. Playback has its own [ownership controller](./App/PlaybackOwnershipController.swift) because it shares the OS audio session with capture. Starting recording stops playback and drains conflicting replay/intelligence work before acquiring recording resources.

Session UUIDs, epochs, and exact lease tokens distinguish a current operation from stale callbacks. Manual-note reservations similarly capture a meeting and edit revision before debounce; a later selection change cannot retarget the edit.

## Recording and transcription

### Start and readiness

[RecordingCoordinator](./Core/RecordingCoordinator.swift) is the recording state machine. Its phases are idle, preparing, recording, stopping, completed, interrupted, recoverable failure, and failure. [RecordingSessionOwner](./Recording/RecordingSessionOwner.swift) owns the resources needed to implement those transitions.

A start joins startup reconciliation, reserves shared resources, checks model and storage readiness, loads the selected recognizer, creates a meeting with its exact speech-model pin, and prepares the Live Activity and microphone. The app requires at least 1 GB free storage at preparation. It does not declare recording active until all three readiness facts hold:

1. The audio session is active.
2. The capture pipeline has accepted its first buffer.
3. The Live Activity is active.

Missing or invalid speech models reject startup. There is no silent fallback to recording without transcription.

### Audio path

```mermaid
flowchart LR
    Mic[AVAudioEngine tap] --> Queue[OwnedPCMQueue]
    Queue --> Worker[CaptureAudioWorker]
    Worker --> Convert[Persistent AVAudioConverter]
    Convert --> Writer[16 kHz mono CAF writer]
    Writer --> Manifest[Atomic capture manifest]
    Convert --> LiveQueue[Bounded normalized PCM queue]
    LiveQueue --> Recognizer[Serial native recognizer]
    Recognizer --> Final[Final transcript rows in SQLite]
```

[IOSCaptureHardware](./Recording/IOSCaptureHardware.swift) uses an audio session in record/measurement mode and inspects the actual input format. The requested 2,048-frame tap size is a hint, not a promise about callback size. [CaptureCallbackAdmission](./Core/CaptureCallbackAdmission.swift) and [OwnedPCMQueue](./Core/OwnedPCMQueue.swift) bound callback ownership. The real-time callback does not perform file I/O, inference, or task creation. Overlap, invalid input, or lost capacity is treated as a capture failure rather than hidden audio loss.

[CaptureAudioWorker](./Recording/CaptureAudioWorker.swift) drains source PCM on a serial worker. A persistent converter produces 16 kHz mono Float32 samples. Converted audio is written before it is offered to the separate ASR queue, which has 128 slots of at most 3,200 frames each.

[SegmentCAFWriter](./Recording/SegmentCAFWriter.swift) stores 16-bit mono PCM in CAF segments, normally up to 960,000 frames / 60 seconds each. A segment is closed and synchronized before an atomic manifest update publishes its relative path and sample range. The open tail is not treated as durable after a crash. Sample positions form one recording-wide timeline.

[LiveTranscriptionSession](./Transcription/LiveTranscriptionSession.swift) consumes normalized PCM away from the capture callback. Parakeet publishes finalized windows. These segments are written to SQLite before being presented as saved transcript. Bounded PCM queues do not imply constant memory for an entire meeting: accumulated transcript/UI data can grow with its duration.

### Stop and interruptions

Stop closes callback admission, waits for admitted callbacks, drains conversion and CAF writing, finalizes transcription, unloads the native model, releases its installation lease, and ends the Live Activity. Completion is acknowledged only after the owned cleanup succeeds. Failed cleanup retains admission so another operation cannot reuse resources prematurely.

[IOSRecordingSignalMonitor](./App/IOSRecordingSignalMonitor.swift) scopes interruptions, route changes, media-service resets, thermal conditions, and storage signals to the current epoch. A late signal cannot stop a replacement session. Interruptions do not silently restart the microphone.

### Speech recognition

[CoreMLParakeetRecognizer](./Transcription/CoreMLParakeetRecognizer.swift) is the speech adapter for live recording and replay. It uses FluidAudio's Swift TDT decoder with compiled Core ML models, 16 kHz mono PCM, and disjoint five-second windows. It publishes each window's finalized text during capture and flushes the remaining audio on stop. Segment times retain the source sample range; word alignment and speaker diarization are not provided.

[SpeechRecognition](./Transcription/SpeechRecognition.swift) defines errors, lifecycle phases, and finalized segment updates. [ParakeetModelAdapter](./Transcription/ParakeetModelAdapter.swift) selects the decoder using the manifest's explicit contract and validates loaded Core ML input/output descriptions and decoder state shapes.

| Decoder contract | Core ML pack support |
| --- | --- |
| `parakeet-tdt-v2` | int8 encoder; built-in pinned v2 conversion in [ParakeetCoreMLModel](./Models/ParakeetCoreMLModel.swift) or a valid versioned pack |
| `parakeet-tdt-v3` | int8, int8-v2, or int4 encoder; bundled [v3 descriptor](./Resources/ModelPacks/Parakeet-v3.json) uses int8 |

[ParakeetModelPack](./Models/ParakeetModelPack.swift) validates the decoder contract, precision, component paths, immutable revision, sizes, digests, and attribution. It requires the encoder, decoder, preprocessor, matching joint-decision model, and vocabulary. Other decoder contracts are rejected until the app has a matching adapter; a model name alone cannot enable them.

CPU-only is the production default. The adapter also exposes an explicit CPU-and-Neural-Engine policy; neither policy selects GPU inference. Native tests exercise both model versions on hosted macOS. Live speed, thermal endurance, and locked-screen operation on an iPhone remain device properties.

## Model lifecycle

[ModelManifest](./Models/ModelManifest.swift) binds a model identity to an immutable revision, exact file sizes and SHA-256 hashes, license notice, runtime identity, and semantic file roles. Compatibility, resource estimates, byte verification, and successful native load are separate checks.

[HuggingFaceRepository](./Models/HuggingFaceRepository.swift) inspects public repositories through bounded metadata requests. Model cards are displayed as inert text. The app supports specific reviewed runtime contracts: an arbitrary Core ML or GGUF file does not become usable merely because its extension is recognized.

[ModelInstallationManager](./Models/ModelInstallationManager.swift) follows this lifecycle:

1. Download or copy imported files into owned staging.
2. Verify all expected paths, sizes, digests, and required roles.
3. Publish an immutable `Models/<modelID>/<revision>/<installationUUID>/` directory and manifest.
4. Atomically update that model's `current.json` pointer.
5. Reverify bytes when acquiring a usage lease. Keep leased older installations alive across replacement; reject removal while in use.

The model browser omits installed speech runtimes that this build cannot load. Their stored files are preserved. Equipping a supported Parakeet pack replaces the speech selection.

[ModelFilesImporter](./Models/ModelFilesImporter.swift) copies selected Files-provider resources into protected staging. Core ML imports require the complete supported compiled-model tree. Source files are not used as mutable inference storage.

[HTTPSModelTransport](./Models/HTTPSModelTransport.swift) uses HTTPS with an explicit distribution-host allowlist and no account credentials or cookies. [ResumableModelDownload](./Models/ResumableModelDownload.swift) keeps partial bytes and a checkpoint under a separate download root. Resume binds the exact artifact pin, strong ETag, and partial digest; it validates `206` ranges and restarts on a full `200` response.

[ModelSelectionStore](./Models/ModelSelectionStore.swift) persists an exact verified installation and runtime profile per purpose. An explicit absent, invalid, removed, or incompatible selection does not silently fall back. Without a selection record, the app checks the built-in Parakeet v2 and Phi-3 model IDs. Each new meeting stores the exact speech selection it used, including installation UUID.

Apple Foundation Models is a distinct system provider. It has no app-downloaded weights or weight hash and is usable only when the OS reports it available. Its provenance is tied to the system/runtime version.

## Persistence and filesystem layout

The application root is `Application Support/LocalMinutes`. The initial library uses that root directly. After restore, `activeLibrary.json` can select a generation under `LibraryGenerations/<UUID>`.

```text
LocalMinutes/
  activeLibrary.json                   # Present after switching library generations
  meetings.sqlite                      # Initial library database
  Meetings/<meeting UUID>/
    segment-000000.caf
    capture-manifest.json
    recovery-report.json               # When recovery has run
    transcription-replay.json          # When replay has checkpointed
    RecoveryQuarantine/
  Meetings/.pending-deletions/<UUID>/
  SummaryCheckpoints/<meeting UUID>.json
  LibraryGenerations/<UUID>/            # Replacement database, meetings, checkpoints
  Models/
  ModelSelections/
  DownloadResume/
  ModelImports/
  Diagnostics/
  Exports/
```

The model, selection, download, diagnostic, and export roots belong to the application rather than to a replaceable library generation.

[PersistentFilePolicy](./Core/PersistentFilePolicy.swift) applies private directory/file permissions (`0700` / `0600`), excludes owned data from system backup, and applies iOS `completeUntilFirstUserAuthentication` protection. Data is unavailable before the first unlock after boot, but can support locked recording afterward. This is OS file protection, not additional application-level encryption. Path operations reject unsafe links and validate ownership; atomic writes synchronize temporary files before replacement.

[SQLiteMeetingStore](./Persistence/SQLiteMeetingStore.swift) owns its native connection through an actor. It enables foreign keys, full synchronization, a bounded busy timeout, and transactional writes. The code does not explicitly enable WAL as its normal journal mode; privacy handling and tests also cover sidecars when SQLite creates them.

[MeetingSQLiteConnection](./Persistence/MeetingSQLiteConnection.swift) migrates incrementally to schema version 5 and rejects future schema versions before changing them:

| Version | Added data |
| --- | --- |
| 1 | `meetings` and ordered `transcript_segments`, including capture state, sample ranges, and model revision |
| 2 | `manual_notes` with optimistic edit revision and modification time |
| 3 | External-content FTS5 transcript index and synchronization triggers |
| 4 | `generated_documents`, immutable original JSON, separately edited text, provenance, and edit revision |
| 5 | `meeting_speech_model_pins` containing exact model-selection JSON |

Final transcript writes are idempotent for matching IDs/content and reject conflicting sequences or cross-meeting data. Note and generated-text edits use revisions to prevent delayed saves from overwriting newer edits. The original generated JSON is capped at 1 MB and remains separate from user edits and source transcript.

History uses stable cursor pagination; transcript search and evidence retrieval have bounded result sets. Search is scoped to the selected meeting. This is SQLite/FTS retrieval, not a vector database.

## Recovery, deletion, and backup

[LibraryStartupCoordinator](./MeetingLibrary/LibraryStartupCoordinator.swift) replays pending deletion work, pages through unfinished meetings, and reconciles recoverable state before opening recording admission. Failure remains visible instead of assuming an empty healthy library.

[MeetingRecoveryCoordinator](./MeetingLibrary/MeetingRecoveryCoordinator.swift) verifies the capture manifest and decodes closed CAF files. Missing or corrupt audio becomes explicit timeline gaps. Uncommitted or corrupt tails are quarantined; their positions are not guessed. Its durable journal allows retry after metadata failure.

[MeetingTranscriptionReplayCoordinator](./Transcription/MeetingTranscriptionReplayCoordinator.swift) replays recovered audio using the meeting's captured Parakeet model pin. A missing, invalid, or unsupported pin refuses replay without altering the original audio or transcript. A checkpoint binds the audio/recovery manifests, committed transcript rows, and model pin. Resume appends remaining finalized rows without duplicate output. Reinstalling identical weights under another installation UUID does not satisfy the original pin. Checkpoint hashes detect inconsistency; they are not cryptographic authentication against an attacker controlling the library.

[MeetingDeletionCoordinator](./MeetingLibrary/MeetingDeletionCoordinator.swift) checks usage, records a durable request, quarantines owned audio, deletes metadata with cascading rows, and completes filesystem cleanup. Startup can finish an interrupted deletion. Deleting a current meeting does not erase copies already exported or retained in previous library generations.

[MeetingArchive](./Core/MeetingArchive.swift) exports a `.localminutesbackup` directory package containing a consistent SQLite snapshot, allowed meeting files, and a manifest of paths, sizes, and hashes. Limits are 8 GiB total, 512 MiB per file, 16,384 files, and a 1 MiB manifest. Models, selections, diagnostics, and unfinished summary-map checkpoints are excluded. Saved generated documents remain in the database.

[LibraryArchiveCoordinator](./MeetingLibrary/LibraryArchiveCoordinator.swift) validates hashes, paths, and database integrity before restoring into a new generation. It atomically replaces the active-library pointer and [rebinds application services](./App/RecordingApplication+Restore.swift) behind the stable application owner. It retains the previous generation instead of merging into or overwriting the active database.

## Summaries and question answering

[IntelligenceSession](./Intelligence/IntelligenceSession.swift) acquires shared admission, snapshots the selected meeting's source, acquires the selected model installation when applicable, runs generation, and drains/unloads before committing a generated document. Cancellation and SQL commit have an explicit admission boundary: late cancellation cannot erase a document already committed.

The local [summary runtime](./Summaries/LocalSummaryRuntime.swift) uses llama.cpp on CPU with four threads and an app context of 4,096 tokens. It validates supported Qwen2/Phi3 model metadata and chat formatting. JSON generation uses a compiled schema rather than accepting arbitrary prose as a structured result.

[SummaryPipeline](./Summaries/SummaryPipeline.swift) plans atomic transcript segments against the input/output token budget, with a normal output budget of 1,024 tokens. It refuses an oversized segment instead of truncating evidence. It generates bounded maps and combines them with [GroundedSummaryMerger](./Summaries/GroundedSummaryMerger.swift); there is no second model-generated reduction.

[GroundedSummaryValidation](./Summaries/GroundedSummaryValidation.swift) checks source IDs, sample ranges, and literal quotes. Summary/decision text must match source evidence; action tasks must occur in cited text. Owners require the supported explicit speaker commitment form, and deadlines require an explicit source clause. Manual notes provide context but are not citation evidence. These checks constrain provenance; they do not prove that every model-selected statement is semantically appropriate.

Local-model summary checkpoints bind the transcript and notes, chunk plan, model identity/revision/hash, runtime, prompt, and context settings. Saved maps are revalidated on resume. A successful document commit removes the unfinished checkpoint. The [Apple runtime](./Intelligence/AppleFoundationRuntime.swift) does not support this resume path; token budgeting uses conservative estimates on the pinned SDK where an exact count API is unavailable.

[MeetingQuestionAnswerer](./QuestionAnswering/MeetingQuestionAnswerer.swift) uses bounded lexical/FTS queries within one meeting. The current implementation selects the highest-ranked evidence excerpt for the generation prompt. Questions are limited to 2,048 UTF-8 bytes, excerpts to 4,096 bytes, and output to 192 tokens.

Answers must return either `supported_quote` with an allowed source ID and exact UTF-8 substring, or `insufficient_evidence` with no quote. There is no cross-meeting or external-knowledge retrieval. Stored citations preserve the original answer's evidence; editing displayed generated text does not validate new claims against those citations.

## UI, privacy, and diagnostics

[LocalMinutesHomeView](./App/LocalMinutesHomeView.swift) owns tab/navigation presentation. [RecordingControlsView](./App/RecordingControlsView.swift), [ModelBrowserView](./App/ModelBrowserView.swift), and [MeetingIntelligenceView](./App/MeetingIntelligenceView.swift) render observable controller state. Current design behavior lives in SwiftUI source: standard navigation/forms, system symbols, accessibility labels, Dynamic Type support, and explicit busy/error states. There is no separate design-export dependency in the build.

[AppScreenshotsUITests](./Tests/NativeUITests/AppScreenshotsUITests.swift) navigates those same views with the existing isolated library/model fixtures and [DEBUG-only screenshot display inputs](./App/AppScreenshotFixture.swift). The screenshot workflow runs this tour on hosted macOS in light and dark mode; it does not run microphone capture or download inference weights. Named XCTest attachments are exported and checked against the tour's declared captures by [app-screenshots.mjs](./scripts/app-screenshots.mjs). The Windows [download command](./scripts/download-screenshots.mjs) verifies the source commit, PNG checksums and complete filename set before replacing the ignored local `AppUI_Screenshots/` directory. It shares the IPA's [temporary transfer and remote deletion lifecycle](./scripts/github-transfer.mjs). These fixtures are excluded from Release builds and never load a user's default library.

[RecordingAppIntents](./App/RecordingAppIntents.swift) bridges recording Shortcuts into the same owner as the foreground UI. The Live Activity's [Stop intent](./Shared/StopRecordingActivityIntent.swift) carries a session UUID and cannot stop a replacement recording. [OpenLatestMeetingIntent](./App/OpenLatestMeetingIntent.swift) requires local device authentication and foreground navigation. Live Activities show status and elapsed time, not transcript content.

[RecordingPrivacyRoot](./App/RecordingPrivacyRoot.swift) synchronously covers inactive scene content and hides its accessibility tree. This does not stop recording. Backgrounding cancels foreground intelligence; detail views flush pending edits when leaving.

[TranscriptionMetrics](./Core/TranscriptionMetrics.swift) and [EnduranceMetrics](./Core/EnduranceMetrics.swift) record bounded operational metadata such as sample counts, queues, latency, memory, thermal state, and battery facts. Exports are capped at 64 KiB and exclude meeting text/audio. The [storage privacy report](./App/StoragePrivacyReport.swift) reports categories and policy facts without meeting names or content. It is not proof of physical lock-state behavior.

Network operations are model discovery/downloads, not meeting uploads. Text/Markdown sharing and backup export are explicit user actions. The bundled [privacy manifest](./Resources/PrivacyInfo.xcprivacy) declares no tracking or collected-data types and includes the disk-space API reason.

## Native dependencies

| Dependency | Pin and role |
| --- | --- |
| FluidAudio | Revision `c79c4106b954f81205113c3343e5a7e59a1089b5`, optional traits disabled; Parakeet decoding |
| llama.cpp | b5046, pinned framework prepared by [prepare_native_summary.py](./scripts/fixtures/prepare_native_summary.py) |
| Apple frameworks | SwiftUI, AVFoundation, ActivityKit, AppIntents, Core ML, and optionally Foundation Models |

[package-ios.mjs](./scripts/package-ios.mjs) checks bundle/source identity, device architectures, unsigned state, and excluded private/model data. [THIRD_PARTY_NOTICES.txt](./Resources/THIRD_PARTY_NOTICES.txt) contains the retained dependencies' bundled legal notices. Native libraries, model weights, recordings, and generated projects are not committed.
