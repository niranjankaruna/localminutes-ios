# LocalMinutes Windows app and local Wi-Fi sync plan

Planning date: 30 October 2026. This is an implementation plan, not a completed Windows application. Implementation has started; the source folders now follow the ios/windows split. See ../windows/README.md for current implementation status. The accompanying Figcraft desktop concepts are design references with illustrative content.

Deliverables: [editable Figcraft desktop design](../windows/Design/LocalMinutes-Windows-Plan.figcraft), [meeting workspace preview](../windows/Design/windows-plan-previews/meetings-summary.png), [sync preview](../windows/Design/windows-plan-previews/sync-ready.png), and [all ten screen previews](../windows/Design/windows-plan-previews/). Open the Figcraft file and use the Windows workspace, Send PC meeting data to iPhone, or Pair devices review flow.

Build a native Windows application with the existing meeting workflows, package it as a portable folder launched by an EXE, and add explicit local-network sending to both platforms. Keep Swift/iOS and Windows implementation separate, joined by a versioned data contract. No hosted service, account system, internet connection, or downloaded model transfer is required for sync.

## Confirmed product decisions

| Topic | Agreed behavior |
| --- | --- |
| Windows device | Windows 11, AMD Ryzen 7 eight-core processor, 64 GB RAM, user-reported NVIDIA RTX 5070 Ti with 16 GB VRAM. Exact CPU model, GPU driver and available disk space are checked during implementation. |
| Packaging | A portable folder with an executable, supporting runtime files, data and separately downloaded models is acceptable. No installer. |
| Direction | Pressing Sync on iPhone sends iPhone data to Windows. Pressing Sync on Windows sends Windows data to iPhone. |
| Conflicting edits | The sending device wins, including when its edit is older by wall-clock time. |
| Deletions | Copy and update only. Deleting on one device does not delete on the other. |
| Windows recording | Microphone only in the first version. |
| Identity | Thin local identity for each app profile and each running process; no login. |
| Models | Download and select models independently on each device. Never transfer model binaries through sync. |
| Repository | Plan to move existing iOS code into `ios/` and put all Windows code into `windows/`, on `main`. |

Version-one operating rule: open LocalMinutes on both devices, keep the iPhone app in the foreground, connect to the same reachable LAN, and choose a trusted receiving device. A PC connected by Ethernet to the same router may also work; matching Wi-Fi names alone does not establish reachability.

## What the existing implementation gives us

The source, rather than older architecture descriptions, is the implementation baseline:

- [Package.swift](../ios/Package.swift) uses Swift 6.2, supports iOS 18+, pins FluidAudio to `c79c4106b954f81205113c3343e5a7e59a1089b5`, and links an Apple llama framework. The [native preparation helper](../ios/scripts/fixtures/prepare_native_summary.py) pins llama.cpp `b11900`.
- [LocalMinutesHomeView.swift](../ios/App/LocalMinutesHomeView.swift) provides Meetings, Record and Settings. [LocalMinutesDesign.swift](../ios/App/LocalMinutesDesign.swift) defines Summary, Transcript, Notes and Ask, with pale gray surfaces and blue accents.
- [MeetingSQLiteConnection.swift](../ios/Persistence/MeetingSQLiteConnection.swift) has schema version 5, including meetings, transcript segments, notes, generated documents, speech-model provenance and FTS5. Stable UUIDs exist, but there is no device-pairing or synchronization protocol.
- [StoredGeneratedDocument.swift](../ios/Persistence/StoredGeneratedDocument.swift) separates original generated JSON from user edits. Local edit revisions protect against stale saves; they cannot be compared across devices to decide which edit wins.
- [MeetingArchive.swift](../ios/Core/MeetingArchive.swift) and [LibraryArchiveCoordinator.swift](../ios/MeetingLibrary/LibraryArchiveCoordinator.swift) provide consistent snapshots, hashes, path validation and recoverable library replacement. Restore replaces a library rather than merging it. Sync must not call restore against the receiving library.
- [SegmentCAFWriter.swift](../ios/Recording/SegmentCAFWriter.swift) stores 16 kHz mono signed 16-bit little-endian PCM in CAF segments, normally up to 60 seconds each. Windows playback cannot be assumed to support CAF automatically.
- [MeetingTranscriptionReplayCoordinator.swift](../ios/Transcription/MeetingTranscriptionReplayCoordinator.swift) requires the original speech-model installation UUID for recovery. A model downloaded on another platform is a different installation.

The current summary/Q&A implementation uses llama.cpp; obsolete references to Apple Intelligence in earlier architecture sections are not a Windows requirement.

## Windows architecture and portable distribution

Use **C# with .NET 10 LTS, WPF and SQLite**. WPF supplies Windows layout, text, keyboard and accessibility facilities without requiring a browser runtime. .NET 10 has published support through November 2028. Pin SDK and dependency versions at implementation time. [Microsoft WPF documentation](https://learn.microsoft.com/en-us/dotnet/desktop/wpf/overview/) and [.NET support policy](https://dotnet.microsoft.com/en-us/platform/support/policy/dotnet-core).

Tauri remains technically possible, but adds Rust/web integration and a WebView2 deployment decision. For this Windows-only application, WPF is the simpler starting point. This is an architecture recommendation, not a claim that portable Tauri apps are impossible. [Tauri Windows distribution guidance](https://v2.tauri.app/distribute/windows-installer/).

Publish a self-contained `win-x64` release. Bundle the .NET runtime; keep native inference dependencies alongside the executable where that makes loading and updates simpler. Do not trim the WPF application initially. Single-file publishing is optional inside the portable package: it does not remove the need for writable recordings/models, and bundled native libraries can extract at launch. [Microsoft deployment guidance](https://learn.microsoft.com/en-us/dotnet/core/deploying/single-file/overview).

Proposed distribution, not yet generated:

```text
LocalMinutes-Windows-x64/
  LocalMinutes.exe
  runtimes/                   verified native dependencies
  licenses/
  LocalMinutes.Data/
    identity/
    libraries/
    sync-staging/
    rollback/
    settings.json
  Models/                     independently downloaded model packs
```

Use `AppContext.BaseDirectory` to resolve the default data root, never the shell's current directory, `Assembly.Location` under single-file publishing, or a temporary extraction directory. If it is unwritable, show a folder chooser. Keep user data outside versioned application binaries; updates replace application files without replacing data or models. Test moving the folder and paths containing spaces and non-ASCII characters.

Portable does not mean completely stateless: the app writes data, the OS may store trust material, GPU acceleration requires a compatible NVIDIA driver, and Windows may request firewall permission. A clean Windows machine must not need a separate .NET, Python, Node, developer-tool or inference-server installation. Audit native runtime redistribution requirements and include permitted app-local dependencies. Code signing and checksums are release tasks; signing cannot guarantee removal of every Windows reputation prompt.

### Windows implementation boundaries

| Module under the proposed Windows solution | Responsibility |
| --- | --- |
| `LocalMinutes.Desktop` | WPF views, view models, navigation, themes, accessibility and dialogs |
| `LocalMinutes.Domain` | Meeting contracts, operation ownership, admission rules and errors |
| `LocalMinutes.Persistence` | SQLite migrations, transactions, FTS5, notes, documents and sync metadata |
| `LocalMinutes.Audio` | Microphone selection/capture, normalization, durable segments, recovery and playback |
| `LocalMinutes.Transcription` | Windows recognizer adapter, live-window handling and replay |
| `LocalMinutes.Intelligence` | llama.cpp interop, prompts, token budgets, validation, summaries and Q&A |
| `LocalMinutes.Models` | Catalogs, hash-verified downloads, installation leases and local selections |
| `LocalMinutes.Sync` | Identity, trust, discovery, transport, staging, sender-wins import and receipts |

Preserve the current application's single-owner approach to recording, playback, inference and maintenance. UI cancellation must drain native work before releasing resources; a late callback must not write into a different meeting.

### Offline inference

Use a pinned Windows llama.cpp build with a small owned interop boundary. Start by checking the existing `b11900` API/model compatibility; do not pair an arbitrary wrapper with a different native ABI. Preserve the current full-transcript prompt, context admission, JSON validation, citations, original-versus-edited text, and failure behavior. Windows builds and CPU/GPU backends are documented by the [llama.cpp maintainers](https://github.com/ggml-org/llama.cpp/blob/master/docs/build.md).

Evaluate sherpa-onnx with compatible Parakeet ONNX v2/v3 packs for Windows speech recognition. FluidAudio/Core ML model files cannot run unchanged on Windows. The maintainer provides a [C# API](https://k2-fsa.github.io/sherpa/onnx/csharp-api/index.html) and [Parakeet model conversions](https://k2-fsa.github.io/sherpa/onnx/pretrained_models/offline-transducer/nemo-transducer-models.html). These are candidate dependencies pending pinned-version integration tests. The relevant recognizers are offline models; live transcription needs explicitly tested windowing, overlap, finalization and timestamp behavior, not an assumption of native streaming parity.

Establish CPU correctness first, then qualify GPU inference on the user's RTX 5070 Ti. Verify exact device capability, driver, CUDA build and redistribution requirements against [NVIDIA Blackwell compatibility guidance](https://docs.nvidia.com/cuda/blackwell-compatibility-guide/). Benchmark actual memory use, transcription throughput, first-token latency and generation speed. Do not infer a supported context length or real-time speed from 16 GB VRAM alone. Retain a tested CPU fallback.

Saved meeting text and audio must work without local model downloads. Reprocessing an imported meeting uses an explicit new local operation with its own provenance. Do not rewrite the original iPhone model pin to pretend it refers to a Windows installation.

Introduce platform-neutral historical provenance separately from executable model selections. The current [MeetingSpeechModelPin.swift](../ios/Persistence/MeetingSpeechModelPin.swift) validates against local runtime profiles; importing a valid Windows ONNX provenance record must not fail merely because iOS cannot execute ONNX. Validate the historical envelope, artifact hashes and relationships without loading a model. Preserve unknown supported-envelope runtime metadata for display/export; require local runtime compatibility only when starting new inference.

## Desktop layout and feature coverage

Use the existing product structure with desktop proportions: persistent left navigation, a searchable meeting list, and a wider reading/editing pane. Keep the blue accent and quiet gray/white surfaces, use Segoe UI on Windows, and preserve a readable content width. Use native window controls, keyboard focus, context menus, text selection and file dialogs.

The Figcraft reference should cover these linked states:

| Screen | Content and interactions |
| --- | --- |
| Meetings and Summary | Library list, title/date/duration, Summary/Transcript/Notes/Ask tabs, Overview and Minutes of Meetings, citations, export and meeting menu |
| Transcript | Sample-aligned timestamps, searchable transcript, citation seeking and playback |
| Notes | Editable meeting notes, visible save state, safe autosave and undo |
| Ask | Question input, saved answers, citations, original/edited text and generation state |
| Record | Microphone selection, model readiness, one start/stop action, timer, live transcript and notes; no invented pause feature |
| Settings | Speech/summary model setup, storage location, backup/restore, permissions, diagnostics and trusted devices |
| Sync ready | Selected peer, explicit source-to-destination direction, model/deletion exclusions and sender-wins explanation |
| Sync progress | Actual transferred bytes/items, preparing/transferring/verifying/saving stages and cancel/pause behavior |
| Sync receipt | Added/updated/unchanged counts, completion time, partial/error explanation when applicable |
| Pair devices | Peer name, fingerprint-bound comparison code, both-device confirmation and cancellation |

The delivered design contains ten editable light-theme 1440x900 screens, with connected review flows. Its layers and prototype destinations were inspected, and all ten PNG exports were visually reviewed. Implementation must also cover empty/search/no-results, first-run setup, permission denial, missing models, low disk, recoverable recording, interrupted transfers and unavailable peers. Add dark-theme and compact-window designs before implementing those states. Validate 1280x800 and 1440x900 layouts plus Windows scaling, keyboard-only use, Narrator and high contrast. Desktop design concepts are not runtime verification.

Windows parity includes recording, local transcription, original audio, playback, manual notes, summaries, saved Q&A, edits, citations, rename/delete, text/Markdown export, backup/restore, model management and recovery. iOS Live Activities and Action Button integrations stay iOS-specific. Windows system-audio capture is outside version one.

## Identity without accounts

Generate these identities locally:

| Identity | Meaning |
| --- | --- |
| `replicaID` | Random persistent UUID for one app data profile, retained across launches and application updates |
| `runID` | New random UUID for each process launch, identifying the currently running instance |
| `deviceName` | Editable name such as “My iPhone” or “My Windows PC” |
| Peer identity key | Cryptographic identity used for pairing; UUIDs and names are not authentication |
| `transferID` | Unique identifier for one immutable send operation and its receipt |

Use a named mutex/file lock to permit only one writer per Windows data root. Distinct profiles may run separately with distinct replica IDs. Detect a cloned portable profile during pairing and offer to make it independent, generating a new identity and clearing its peer trust. Moving a profile preserves its data; if protected key material cannot be opened on the new computer, re-key and re-pair explicitly.

Store iOS keys in Keychain and use Windows OS-protected key storage. Do not sync private keys, paired-device lists or local identity. A future account can associate several replica IDs with an account; meeting IDs and the wire protocol need not be replaced to add that relationship.

## Exact sync behavior

“Sync” means **send this device's saved data**, not automatically exchange both libraries. Device discovery and hash comparisons run both ways, but user content travels in the chosen direction. Keep a visible label such as “Windows PC → My iPhone”. With multiple trusted peers, require choosing one; never broadcast meeting data to all nearby devices.

After initial pairing, tapping Sync to the selected trusted peer starts the send. The receiver accepts only while the app is open and local receiving is enabled. Pairing explicitly establishes permission for later sends; receiving can be disabled and peers forgotten. No confirmation is needed for every conflicting field because sender-wins is the chosen policy.

| Situation | Result |
| --- | --- |
| Sender has a new meeting | Receiver imports it under the same meeting UUID. Sender keeps its copy. |
| Same record ID, identical content | Skip it. |
| Same editable record ID, different content | Replace the receiving version with the sending version, regardless of device clock. |
| Receiver has a meeting or document absent on sender | Keep it. Absence is never a deletion command. |
| Sender intentionally saves an empty note | Apply the empty value as an update; distinguish this from a missing note record. |
| Sender deleted a meeting or summary | Do not delete the receiving copy. A later send in the other direction can bring that copy back. |
| Both sides generated different summary/answer IDs | Keep both saved documents. For a shared meeting, carry an explicit preferred summary reference so the sender's displayed summary can become the displayed version without discarding receiver-only history. |
| Repeated send with no edits | No duplicate meetings/documents and no audio retransmission. |
| Same immutable identity with contradictory original data | Report an integrity error for that operation; sender-wins edits do not authorize silently accepting malformed/colliding source data. |

This deliberately does not make the libraries exact mirrors. Two opposite sends can reconcile their union, but the order matters: whichever device sends a conflicting edit first overwrites the other copy, which can then be sent back. Retain a local pre-import rollback snapshot so an accidental send can be undone. A rollback is recovery history, not a conflict-choice interface or an automatic remote rollback.

An absent or null sender summary preference means no preference update in v1; it never hides or deletes receiver-only summaries. A non-null reference must resolve to an included or existing validated document. A local summary deletion clears the local preference without exporting a clear operation. During migration, initialize missing preferences from the existing latest-created ordering with its stable ID tie-break; do not continually reselect by timestamps after sync. Adding this reference requires updating both platforms' readers, generation, exports and summary-deletion checks together, including [MeetingIntelligenceView.swift](../ios/App/MeetingIntelligenceView.swift). Do not leave two competing rules for which summary is displayed.

### iPhone changes

Add a visible Sync action to the Meetings toolbar and a Sync and devices area in Settings. The action opens the same device selector and source-to-destination summary, with the iPhone as sender. Show this device's friendly name and short identifier, trusted peers, receiving toggle and last completed receipt in Settings. Use native sheets for pairing, sending, interruption and permission recovery; preserve existing meeting tabs and recording controls.

Compose the sync coordinator alongside the existing application-lived services. Integrate with maintenance/admission, draft flushing, storage policy, scene lifecycle and restore rebinding. Receiving must never be owned by a transient detail view. A library restore changes its generation and invalidates staged transfers and digest caches while keeping the local device identity and pairings. Existing older app versions without sync must be reported as incompatible rather than receiving a partial import.

### Data included and excluded

| Copy through sync | Keep local or rebuild |
| --- | --- |
| Meeting IDs, names, dates, durations and durable recording status | App/run identity, trusted peers, keys and permissions |
| Original recorded audio and required capture manifests | Model weights, compiled models, download partials and installation selections |
| Finalized transcripts, sample ranges and source relationships | FTS indexes and other rebuildable caches |
| Saved manual notes, including deliberate empty values | Device-specific microphone, hardware, window and theme preferences |
| Original generated documents, user edits, questions, citations and model/prompt provenance | Temporary export copies, diagnostic logs and transient transfer files |
| Durable evidence needed to preserve interrupted recordings | Running inference state and model/runtime-bound resumability checkpoints |

“All meetings” includes the full paginated library and every historical summary/answer, not just loaded search results or the currently displayed documents. Add bounded export enumeration for generated documents: the current [generatedDocuments implementation](../ios/Persistence/SQLiteMeetingStore.swift) has a 1,000-item maximum and no cursor. Test a meeting with more than 1,000 saved documents. Flush notes and edited documents before snapshotting. Explicitly wait for recording/recovery/generation to finish, or ask the user to stop/cancel them; do not silently omit an active meeting and claim everything synced. An interrupted saved recording can be copied, but its recovery job does not migrate as a running task. Existing model and inference checkpoints may remain on their originating device while all completed user-visible output is copied.

### Cross-platform data contract

Exchange a versioned logical manifest and binary objects, not executable SQL or the receiving database. Specify canonical UUID casing, UTF-8 strings, integer sample counts, explicit UTC timestamp encoding, enum values, null-versus-missing behavior and size limits. Existing SQLite timestamps use Unix seconds and Swift serializes UUIDs in uppercase; adapters must normalize IDs consistently to avoid case-sensitive duplicate keys. Preserve original JSON bytes when their exact hash matters; define canonical encoding for logical record digests.

The manifest identifies protocol/data schema versions, source/target replica, transfer ID, snapshot generation, full-library page sequence, record identities/digests, audio format, object sizes/hashes and required relationships. Reject unsupported required versions before changing local data. Add migrations for replica provenance, record digests, summary display preference, transfer receipts and commit journals. Track a receiver mutation sequence that advances for every relevant metadata or media change, separately from the library generation that changes on restore. Keep local edit revisions local: importing a record must invalidate existing editor reservations rather than trust a foreign revision number. Sender-wins does not require CRDTs, version vectors or an account database.

Keep each platform's storage schema an implementation detail. Establish equivalent validation and a logical exchange contract; rebuild FTS on the receiving platform using compatible tokenizer behavior. Preserve existing backup readability. Schema changes must also update the archive code's hard-coded `1...5` database compatibility range and its tests.

Store and transfer the existing original CAF bytes unchanged. Implement and test a Windows reader/writer for the exact supported PCM CAF subset, including headers, endian handling, segment boundaries, truncated tails and sample offsets. A transient WAV playback adapter is acceptable if it preserves samples and original files. Verify Windows-created recordings play on iPhone before declaring recording parity.

Treat capture audio and transcripts as aggregates with explicit immutable identities, not unrelated replaceable rows. For the same original capture, retain the validated union of closed audio segments and finalized transcript records; derive duration/gaps/status from the resulting timeline. An older sender snapshot cannot shorten that timeline or replace its manifest with one that drops receiver-only audio. Contradictory immutable segment identities fail validation. Sender-wins applies to editable meeting content, not rewriting original audio facts.

New local retranscription creates a separate transcript version, with its own version ID and provenance. Migrate the current unique `(meeting_id, sequence)` key to include that version, preserving existing segment IDs and citations. Retain earlier versions and receiver-only segments; record the selected transcript version explicitly. Summary/answer citations continue pointing to their originating version, even after a different version becomes current. If this versioning is deferred, cross-platform retranscription must also remain unavailable; importing the audio and saved text must still work.

### Discovery, pairing and transport

Use Bonjour/DNS-SD with a declared `_localminutes._tcp` service. On iOS, use Network framework browsing/connections/listeners; on Windows, use the native DNS-SD API and a .NET TLS stream adapter. Validate native API behavior in a small interoperability spike. [Windows DNS-SD discovery](https://learn.microsoft.com/en-us/windows/win32/api/windns/nf-windns-dnsservicebrowse).

Use TLS with paired peer identities. First pairing should offer a short-lived QR invitation containing the full fingerprint and a high-entropy invitation value, or a correctly implemented transcript-bound comparison code confirmed on both devices. A short code must not be the sole encryption secret. Pin trusted identities, reject identity changes until re-paired, expire/rate-limit invitations and authenticate before accepting manifests. Certificate/key provisioning and mutual verification are early spike requirements, using [Apple's local-network TLS guidance](https://developer.apple.com/documentation/network/creating-an-identity-for-local-network-tls).

Each open app hosts a local listener for receiving. This is not a separately installed server: there is no cloud endpoint, relay, broker, port forwarding or background Windows service. Advertise only minimal discovery metadata; keep meeting titles/content out of broadcasts. Use local-network interfaces and no automatic internet fallback. Manual address entry may help when multicast discovery is blocked, but must still authenticate and cannot bypass router client isolation.

Add the iOS Local Network explanation and Bonjour service declaration, and present permission requests in the foreground. Do not add raw multicast entitlement or disable transport security merely to avoid permission work. Test the chosen API configuration against [Apple TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy). On Windows, document the Private-network firewall requirement without disabling the firewall or silently changing machine-wide policy.

Foreground operation is the v1 contract. iOS does not provide an always-available background LAN receiver or arbitrary network-triggered wakeup. On interruption, checkpoint and resume after the app reopens. Continued-processing APIs can be evaluated later for a user-started transfer but cannot justify an always-running listener. [Apple background execution limits](https://developer.apple.com/forums/thread/685525).

### Reliable transfer and apply sequence

1. Acquire source admission, flush drafts, snapshot committed metadata and immutable audio, then release the source to continue editing. The snapshot must own copied bytes or durable references that prevent deletion/garbage collection of every referenced blob until it expires; retaining hashes or paths alone is insufficient. Changes made afterward belong to the next send. Never hash changing files or copy a live SQLite file.
2. Discover/authenticate the selected peer, negotiate versions and acquire one receiver sync reservation. Serialize simultaneous opposite-direction sends; show Busy/Retry instead of applying competing operations.
3. Compare manifest pages and content digests. Resolve differences under sender-wins; skip identical records and blobs. Preflight receiver free space for staging, journal and rollback retention.
4. Transfer missing objects in bounded chunks with backpressure and resumable offsets. Persist progress against the transfer ID and snapshot digest; resumed chunks must belong to that same snapshot. Verify final SHA-256 and byte counts.
5. Validate the staged dataset: allowed object types, lengths, IDs, database relationships, citations and audio timelines. Use opaque content-addressed object names. Reject traversal, links/reparse points, Windows reserved-path tricks, case collisions and arbitrary file writes.
6. Take a brief exclusive apply lease, flush receiver drafts, and validate both library generation and mutation sequence against the comparison baseline. If receiver edits/deletions made previously skipped source content necessary, release the lease, return to comparison, and fetch those records/blobs from the retained immutable source snapshot. Reacquire the lease and revalidate before commit. Never assume an initially identical object is still present. Bound repeated retries and show Busy if local changes prevent a stable apply. Once stable, create the rollback snapshot under the lease; never apply a stale plan over concurrent work.
7. Publish verified immutable objects before referencing them. Transactionally apply matching record updates and new records while retaining receiver-only data; rebuild affected indexes. Persist a transfer commit receipt in the same transaction. A durable journal resolves crashes between filesystem publication and database commit; no committed reference may point to an unfinished file.
8. Durably mirror the transaction's receipt into the local recovery ledger outside library generations, then acknowledge commit, refresh views and release the lease. Only then show completion. Startup reconciles database commit markers with this ledger before accepting another sync. Retried commit/status requests return the existing receipt, so a lost final acknowledgment cannot duplicate data.

For v1, stage the complete changed set before one logical import commit. Large libraries use paginated manifests and streamed blobs, not an in-memory archive. Preserve the source snapshot until the receiver confirms commit or an explicit retention limit expires. On expiration, start a new snapshot cleanly. Keep bounded rollback/staging retention and report available space; do not silently inherit the current archive's 8 GiB total-library limit.

Cancellation before commit leaves the receiving library unchanged. After durable commit, show completed status; cancellation is not a rollback. Logs contain counts, byte sizes, timings and error codes, not recording content or pairing secrets.

Keep mirrored transfer receipts in durable local sync metadata outside replaceable library generations; reconcile all committed markers into that ledger before any restore or rollback. The database transaction and this external journal are not one atomic write, so crash recovery must reconcile their intermediate states before admitting operations. A rollback advances the library generation, invalidates pending plans, and marks the receipt as rolled back while preserving its transfer ID; a delayed retry returns that status and cannot silently reapply the transfer. If edits occurred after the sync, show that restoring the earlier snapshot would also undo those edits, retain a safety copy of the current state, and require explicit recovery confirmation. An intentional new send uses a new transfer ID.

## Planned repository organization

The following tree is proposed; these paths will be created during implementation:

```text
Localminutes/
  AGENTS.md
  README.md                   cross-platform entry point
  .github/workflows/          existing workflows remain at GitHub-required location
  docs/
    sync/                     protocol, schemas and non-executable golden fixtures
  ios/
    App/ Core/ Recording/ Models/ Persistence/ MeetingLibrary/
    Transcription/ Summaries/ QuestionAnswering/ Intelligence/
    Shared/ LiveActivityExtension/ Resources/ Tests/ scripts/
    Package.swift
    project.yml
    README.md
    ARCHITECTURE.md
    Design/                   existing iOS reference and brand assets
  windows/
    LocalMinutes.sln
    src/                      Windows modules listed above
    tests/
    scripts/                  local build, native dependency and publish helpers
    Design/                   desktop Figcraft document and exports
    README.md
```

Keep executable implementation and platform tests inside their platform folder. Root shared material is documentation, schemas and test data rather than a third application codebase. Move this plan into the cross-platform documentation area and the new desktop design into the Windows design area when the reorganization happens; fix their relative links at the same time.

Move iOS files together with their current internal hierarchy using tracked renames. Audit working-directory assumptions in [prepare-ios.sh](../ios/scripts/prepare-ios.sh), [package-ios.mjs](../ios/scripts/package-ios.mjs), native preparation, screenshot/download helpers and tests. Update ignores, documentation, resource paths, native library paths and source-commit stamping. Keep bundle IDs, entitlements and on-device storage paths unchanged so reorganizing source does not reset installed users' data.

Existing workflow paths may need edits to point at `ios/`; keep workflow definitions at root. Do not create workflows, push changes, dispatch/rerun Actions, or use GitHub-hosted macOS verification without the user's explicit authorization. The entire implementation stays on `main`, with no temporary branches or worktrees.

## Implementation milestones and acceptance gates

| Milestone | Work | Required evidence before proceeding |
| --- | --- | --- |
| 1. Compatibility spikes | Portable WPF with real native dependencies; CAF round trip; Windows Parakeet/llama sample; iPhone-to-Windows TLS/discovery | Clean Windows launch, real sample audio playback on both platforms, model output, authenticated connection in both directions |
| 2. Repository move | Move iOS sources and helpers, add Windows solution layout, repair all paths | Path/script checks; local Mac/Xcode generation and native iOS validation when a Mac is available; installed data identity preserved |
| 3. Shared contract | Specify manifest/records/media, add identity and metadata migrations, golden fixtures | Swift and C# agree on IDs, timestamps, canonical hashes, original JSON and schema rejection |
| 4. Windows library | Navigation, reading, playback, notes, edits, export, local deletion, backups | Existing iOS fixture data renders correctly; edits survive restart; citations seek correctly; no models needed for saved data |
| 5. End-to-end sync | Pairing, discovery, buttons, immutable snapshots, sender-wins import, resumable transfer and receipts | Both directions copy all saved data, target-only data survives, repeat send is idempotent, models excluded |
| 6. Windows recording and intelligence | Microphone capture, durable segments, recovery, live transcription, summaries/Q&A, downloads and GPU option | Measured local inference, crash-safe recordings, prompt/evidence parity, CPU fallback and resource admission tests |
| 7. Hardening and portable release | UI states/accessibility, storage recovery, clean-machine packaging, upgrade and move checks | Physical iPhone 17 Pro/iOS 27.2 and the user's Windows PC pass the matrix below; release ZIP, EXE, checksums and usage notes |

Milestone 5 yields a useful Windows library companion, but the requested same-application scope is not complete until Windows recording/intelligence and release validation also pass. Benchmark results determine defaults; no performance or elapsed-time estimate is treated as established before those measurements.

## Validation matrix

| Area | Essential cases |
| --- | --- |
| Direction and data | Phone-to-PC and PC-to-phone; complete pagination; title/notes/document edits; original JSON/citations/audio; receiver-only records; explicit empty notes |
| User's conflict policy | Sender wins even with older timestamps; reverse send ordering; distinct generated versions retained; receiver editor reservations invalidated |
| Deletion policy | Sender deletion does not delete receiver data; deleted records can return on a later opposite send; deleting a summary does not become an implicit tombstone |
| Exclusions | Zero model/download bytes transferred; local identity, keys, selections and hardware settings remain local |
| Integrity and interoperability | CAF headers and sample offsets, Unicode/UUID casing, cross-language hashes/dates, immutable collisions, invalid citations, unsupported versions and corrupt blobs; older capture snapshots retain newer segments; independent transcript versions preserve citations; foreign runtime provenance remains readable |
| Interruptions | Wi-Fi loss, phone background/lock, PC sleep, app/process kill, source snapshot expiry, lost final acknowledgment and repeated commit |
| Atomicity | Failure before files finish, after file publication, during SQL transaction and after receipt commit; rollback after later edits; delayed receipt retries after rollback; source deletion while snapshot retained; full disk and insufficient staging space |
| Ownership | Active recording, playback, pending notes, generation, recovery, deletion, two simultaneous sends and two Windows launches on one profile; receiver edit/delete of an initially skipped record/blob forces comparison and missing-data transfer again |
| Network trust | First pairing, wrong code/fingerprint, revoked peer, cloned identity, permission denied, firewall blocked, VPN and isolated guest Wi-Fi |
| Packaging and updates | Clean Windows 11 without development runtimes; GPU unavailable/driver mismatch; folder move, read-only location, spaces/Unicode paths; update preserves data/models/identity |
| Product | Empty/setup/error states, keyboard and screen reader, high contrast, scaling, narrow window, text selection and actual physical-device round trips |

No application builds, device sync tests or inference benchmarks have been performed as part of this planning task. Windows-local checks can run during implementation. Native iOS compilation and physical-device validation still require the appropriate Mac/signing/device environment; GitHub Actions are not an implicit substitute.
