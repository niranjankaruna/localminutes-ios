# LocalMinutes

LocalMinutes is an iPhone app for recording meetings, transcribing audio on the device, and generating summaries and answers from a selected meeting. Meeting data stays in the app unless the user explicitly exports it. There is no application server, account system, or cloud transcription service.

The app has three tabs:

- **Meetings:** history and search, with focused Summary, Transcript, Notes, and Ask views. Meeting actions provide rename, recovery, export, and deletion.
- **Record:** a single start/stop control, live transcript and notes, recording status, and a Live Activity. Shortcuts support starting, stopping, and toggling a recording.
- **Settings:** a fixed speech and summary model catalogue, verified downloads, equip/remove controls, library backup/restore, privacy, and diagnostics.

See [ARCHITECTURE.md](./ARCHITECTURE.md) for ownership, data flow, storage, recovery, and inference contracts.

Transcription applies gentle noise reduction to a copy of the audio, retaining the original recording and timestamps. Reduction is deliberately limited and never mutes quiet sections. This targets steady background noise; improved recognition of soft or distant voices still needs real-room iPhone validation.

## Requirements

| Item | Requirement |
| --- | --- |
| App | iPhone, iOS 18 or later; microphone permission and a verified speech model |
| Development | macOS 15 or later, Xcode 26.2 / Swift 6.2 toolchain |
| Project generation | XcodeGen 2.46.0 or later; CI pins 2.46.0 |
| Build helpers | Python 3 with its standard library, Git, and Node.js 22 |

Internet access is needed to fetch native libraries, Swift packages, and model weights. Installed local models process recordings without a network service. Storage and RAM estimates in the model browser are advisory; installation verification does not establish inference speed or accuracy on a particular phone.

## Build

Run commands from the repository root. [Package.swift](./Package.swift) defines the Swift modules and macOS tests; [project.yml](./project.yml) defines the iOS app, extension, and native test targets. Generated Xcode projects and downloaded artifacts are ignored by Git.

Prepare the native libraries **before** resolving Swift packages or generating the Xcode project:

```bash
export DEVELOPER_DIR=/Applications/Xcode_26.2.app/Contents/Developer
python3 scripts/fixtures/prepare_native_summary.py --framework-only --with-simulator
xcodegen generate --spec project.yml
export LOCALMINUTES_SOURCE_COMMIT="$(git rev-parse HEAD)"

xcodebuild -project LocalMinutes.xcodeproj -scheme LocalMinutes \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/simulator CODE_SIGNING_ALLOWED=NO \
  LOCALMINUTES_SOURCE_COMMIT="$LOCALMINUTES_SOURCE_COMMIT" build
```

The summary helper prepares the pinned llama.cpp framework. `--framework-only` downloads no model weights. Swift Package Manager resolves FluidAudio for Parakeet Core ML speech inference. [prepare-ios.sh](./scripts/prepare-ios.sh) prepares the framework and pinned XcodeGen automatically for hosted iOS workflows.

IPA builds call `bash scripts/prepare-ios.sh --device-only` to use the verified prebuilt device framework without compiling a simulator slice. Screenshot and iOS test workflows use the default preparation, which also builds the simulator framework.

The app requires a valid 40-character source commit stamp and numeric build number when initializing services. If building in Xcode's UI, set `LOCALMINUTES_SOURCE_COMMIT` in the app and extension build settings to the checkout's commit. A missing stamp can leave recording services unavailable.

Signing is disabled in the checked-in project configuration. Running on a physical iPhone requires configuring signing for both the app and its Live Activity extension. An unsigned IPA is a packaging output, not an installable signed app.

## Use the app

1. Open **Settings → Speech** and download Parakeet v2 or v3, then equip it for recording. The Record tab also opens setup when a model is missing. Both cards show their source repository, model details, download progress, and installed state.
2. In **Settings → Summaries & answers**, choose a family and variant, download it, and equip it. The catalogue includes Qwen 2.5 (0.5B/1.5B), Qwen 3 (0.6B/1.7B/4B/4B Instruct 2507), Phi-3 mini 4K, Phi-4 mini, Gemma 3 (1B/4B IT QAT), and Gemma 4 (E2B/E4B IT QAT). Each variant card shows its maximum context in tokens, applied automatically to summaries and answers. There is no repository search or arbitrary model import. Qwen 2.5 3B is excluded.
3. Start recording from **Record** or a recording Shortcut. Recording becomes active only after the audio session, microphone buffer, and Live Activity are ready. There is no recording-only fallback when speech preparation fails.
4. Stop recording before requesting a summary or asking a question. Review generated content and its citations. Editable generated text is kept separately from the original output and transcript.

Recording, playback, inference, and library maintenance share admission controls. A pending cleanup can temporarily block another operation until its resources are released. Interrupted audio remains available for recovery; recovery needs the exact speech-model installation originally pinned to the meeting.

Summary and Q&A generation request iOS background execution when you start them. On iOS 26+, continued-processing tasks keep generation attached to system-managed execution after switching apps or locking the screen, with generic progress and cancellation controls. Busy systems can queue the request; the app waits for its launch instead of cancelling it after five seconds or starting inference under a short fallback allowance. Installed models report progress during file verification, prompt processing, and response generation, as well as after each validated summary section. Locking the screen and leaving the detail view do not cancel generation; reopening a meeting rejoins its active controller. Earlier iOS versions, or devices where the scheduler rejects a continued task, use UIKit's limited background allowance. iOS can still expire work under resource pressure or stop it when the app is force-quit; interrupted summaries show an explanation and a Resume summary action, and validated local-summary checkpoints survive reopening. Physical-device execution time and locked-screen behavior require device testing.

**Remove** deletes installed model files and retained partial-download bytes; it also clears the equipped selection when necessary. Meetings and notes remain. A model in active use cannot be removed until its inference work finishes. Downloading does not automatically equip a model. Apple Intelligence is no longer offered. A previously saved Apple selection is treated as explicitly unequipped, so choose a downloaded model; existing saved summaries remain in the library.

During summary or answer generation, the detail screen shows a progress bar, percentage, elapsed time, and estimated time remaining. The same tracker supplies the continued-processing notification, whose short title is Summary or Answer. Elapsed time includes waiting and locked-screen time for the current attempt; it freezes when the attempt ends. Estimates use recent measured generation progress, start as Estimating, and are recalculated after phase changes, recovery, or a stall. Percentage reaches 100 only after the generated document is saved. iOS owns the system notification's fonts and slow-progress Continue prompt; the app cannot disable that prompt through the documented API.

Long ASR paragraphs use compact sentence-reference selection instead of asking the model to repeat full quotes and citation metadata. If normal extraction reaches its output limit, that section gets one compact recovery attempt. The app expands selected references from the original transcript and validates each batch before checkpointing or publishing anything. Compact selection receives a smaller token budget sized for its allowed IDs, while the number of allowed findings grows with the selected model's output budget. If multiple batches exceed the 128-item result limit, all batches participate in consolidation; the transcript tail is not simply discarded. Expanded citation maps can use up to 1 MiB, within an independent 96 MiB checkpoint envelope limit.

Long transcripts, including two-hour meetings, are processed as model-sized sections. Oversized source paragraphs are split without removing text or changing their original citation IDs and audio ranges. Jobs can contain up to 1,024 sections; this is separate from the 128-item limit on an individual response. When a transcript needs more than eight sections, the planner reserves space for a running brief of earlier validated topics, decisions, and tasks. Later sections receive that brief as context, while citations must still come from their current evidence. A final consolidation pass reviews all section findings in bounded groups, then selects a coherent meeting-wide result with its original citations. This reduces context loss but does not promise perfect recall or automatic resolution of ambiguity. Completed section checkpoints rebuild the brief on resume; final consolidation can be rerun without regenerating those sections. Version 4 adds model-specific output and finding budgets to the existing context-bound planning; an interrupted older-version job requires an explicit fresh start, while already saved summaries remain readable. Two-hour scale and interruption regressions use synthetic model boundaries; on-device speed and real-model quality still require validation.

The [catalogue data](./Models/Resources/SummaryCatalog.json) pins each summary artifact to an exact publisher revision, byte count, and SHA-256. Sources are Qwen, Microsoft, Google, and reviewed Unsloth/llama.cpp organization conversions. Gemma 3 uses public `ggml-org` QAT conversions with Google's Gemma terms retained. Model download size is not a promise of available RAM, inference speed, or answer quality on every iPhone.

Published context limits verified on 2026-10-29, including both input and output tokens:

| Model variant | Maximum context | App summary output cap | Publisher specification |
| --- | ---: | ---: | --- |
| Qwen 2.5 0.5B | 32,768 | 8,192 | [Qwen](https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF) |
| Qwen 2.5 1.5B | 32,768 | 8,192 | [Qwen](https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF) |
| Qwen 3 0.6B | 32,768 | 16,384 | [Qwen](https://huggingface.co/Qwen/Qwen3-0.6B-GGUF) |
| Qwen 3 1.7B | 32,768 | 16,384 | [Qwen](https://huggingface.co/Qwen/Qwen3-1.7B-GGUF) |
| Qwen 3 4B | 131,072, with YaRN | 16,384 | [Qwen](https://huggingface.co/Qwen/Qwen3-4B-GGUF) |
| Qwen 3 4B Instruct 2507 | 262,144 | 16,384 | [Qwen](https://huggingface.co/Qwen/Qwen3-4B-Instruct-2507) |
| Phi-3 Mini 4K | 4,096 | 2,048 | [Microsoft](https://huggingface.co/microsoft/Phi-3-mini-4k-instruct) |
| Phi-4 Mini | 131,072 | 16,384 | [Microsoft](https://huggingface.co/microsoft/Phi-4-mini-instruct) |
| Gemma 3 1B | 32,768 | 8,192 | [Google](https://developers.googleblog.com/gemma-explained-whats-new-in-gemma-3/) |
| Gemma 3 4B | 131,072 | 8,192 | [Google](https://developers.googleblog.com/gemma-explained-whats-new-in-gemma-3/) |
| Gemma 4 E2B | 131,072 | 16,384 | [Google](https://huggingface.co/google/gemma-4-E2B-it-qat-q4_0-gguf) |
| Gemma 4 E4B | 131,072 | 16,384 | [Google](https://huggingface.co/google/gemma-4-E4B-it-qat-q4_0-gguf) |

The selected variant supplies the runtime and planner limit, including for existing installations with matching pinned weights. Qwen 3 4B enables the publisher's [YaRN settings](https://qwen.readthedocs.io/en/latest/run_locally/llama.cpp.html) to extend its native 32,768-token window by a factor of four. Context memory grows to fit actual requests up to the selected maximum; a short request does not preallocate the entire maximum window. Full-window requests still require sufficient device memory. Output, citation, and extraction bounds remain separate from the context capacity. Old unfinished jobs whose context settings changed require a fresh summary; completed documents remain readable.

Output caps are ceilings, not target lengths, and are reserved inside the total context window. Qwen 2.5 uses its published 8,192-token generation limit; Qwen 3 uses its [16,384-token non-thinking/instruct limit](https://qwen.readthedocs.io/en/latest/getting_started/concepts.html). Gemma 3 uses the 8,192-token output limit reported in its [model card](https://huggingface.co/google/gemma-3-1b-it). Phi and Gemma 4 caps are app policies within their published context windows, not claims of separate vendor output limits. Phi-3 retains half its 4K window for input; Phi-4 and Gemma 4 use a 16K ceiling. Each extraction category can retain up to 4, 16, or 32 findings for the 2K, 8K, or 16K budgets. Compact ID responses reserve only what their selected-item count needs. Q&A still returns a bounded evidence quote using its separate 192-token response budget.

## GitHub workflows from Windows

There are three manually triggered workflows. None publishes releases or uses persistent build caches:

- [Run all tests](./.github/workflows/tests.yml) runs every retained SwiftPM test, including actual model inference and speech-quality tests, plus Node tests, iOS app-hosted/UI tests, native packaging tests. Its macOS runners discard build outputs when the jobs end. No physical iPhone or self-hosted Mac is needed.
- [Build IPA for local download](./.github/workflows/build-ipa.yml) builds an unsigned IPA for the local transfer script. It uploads only a temporary transfer artifact, not a release.
- [Capture app UI for local download](./.github/workflows/app-screenshots.yml) runs the real app in an iPhone simulator, captures light/dark screenshots with sample data, and transfers them to the local project.

After committing and pushing these files to GitHub, run all tests from the Actions page or with GitHub CLI:

```powershell
gh workflow run tests.yml
```

To build and download on Windows, install Node.js 22 and GitHub CLI, authenticate with `gh auth login`, and run from a clean, pushed checkout:

```powershell
node scripts/download-ipa.mjs
```

[download-ipa.mjs](./scripts/download-ipa.mjs) dispatches the build for the current branch, waits for its uniquely identified run, downloads the IPA and receipts into a new folder under `Downloads/LocalMinutes`, verifies the source commit and checksum, and deletes the temporary artifact and build run. Use `--ref BRANCH_OR_TAG` or `--output NEW_DIRECTORY` to override the defaults. Existing output directories are never overwritten. GitHub authentication must permit workflow dispatch and Actions deletion in this repository.

Keep the script running through cleanup. If the local handoff stops, the workflow deletes its transfer artifact after a 15-minute wait. GitHub's one-day artifact retention is a final fallback if workflow cleanup itself is interrupted; the script reports API cleanup failures rather than claiming the remote build was deleted. The test workflow retains its normal test logs, but no build artifacts.

The downloader prints its GitHub run URL and retries transient status/discovery API failures up to five attempts, with a 30-second timeout per read. A persistent connection outage leaves the run intact and reports its URL instead of cancelling a healthy build. You can check that run and download its artifact in GitHub when connectivity returns; the normal transfer expiry still applies. Explicit cancellation and verification failures retain the existing cleanup behavior. Dispatch is never automatically retried, to avoid creating duplicate builds.

If a build fails before producing an IPA, the download script saves `build-failure.log` and `build-failure.json` in that request's download directory before deleting the workflow run. It fetches full failed-job logs directly from the API so long compiler-command lines do not truncate the error that follows. The report also preserves job steps and check annotations, including runner failures; the terminal prints the first failures and compiler crash details. These diagnostics are not an IPA. If a log or annotation cannot be retrieved, the report records that limitation and retains the available evidence.

### Review the UI from Windows

After committing and pushing, use the same Node.js/GitHub CLI setup to run:

```powershell
node scripts/download-screenshots.mjs
```

[download-screenshots.mjs](./scripts/download-screenshots.mjs) starts the screenshot workflow, waits for capture, verifies every requested PNG and its source commit, then updates **`AppUI_Screenshots/` in this project**. Use `--ref BRANCH_OR_TAG` to select a pushed ref that matches the local commit. Run this command on Windows and keep it open; a GitHub-hosted workflow by itself cannot write to your local disk.

Choose an appearance, categories, or individual screens to avoid capturing the whole app:

```powershell
# List category names and every exact screen name without starting a workflow.
node scripts/download-screenshots.mjs --list

# All transcript and summary screens, dark mode only (7 screenshots).
node scripts/download-screenshots.mjs --appearance dark --categories transcript,summary

# Just these two screens, in both appearances (4 screenshots).
node scripts/download-screenshots.mjs --screens meeting_transcript,meeting_share_sheet

# A screen and its category's related states, in both appearances (6 screenshots).
node scripts/download-screenshots.mjs --screens meeting_transcript --related

# Preview any selection by adding --list; this makes no GitHub requests.
node scripts/download-screenshots.mjs --appearance light --categories parakeet --list
```

`--appearance` accepts `both` (default), `light`, or `dark`. `--categories` and `--screens` accept comma-separated names; when both are supplied, their selections are combined without duplicates. `--related` requires `--screens` and adds every scene in each named screen's category. With neither category nor screen filters, all scenes are selected. Unknown names fail before dispatch. The workflow's manual inputs expose the same `appearance`, `categories`, `screens`, and `related` choices; the local command handles download and remote cleanup.

The [scene catalog](./Shared/AppScreenshotScene.swift) defines 41 screen/section states (82 PNGs with both appearances). [app-screenshots.mjs](./scripts/app-screenshots.mjs) groups them as follows; counts are per appearance:

| Category | Scenes | Included views |
| --- | ---: | --- |
| `recording` | 5 | Idle, model required, active recording, live transcript, live notes |
| `library` | 7 | Empty/history, actions, search, backup, restore picker, meeting deletion |
| `notes` | 1 | Meeting notes |
| `transcript` | 3 | Transcript, transcript search, empty transcript |
| `summary` | 4 | Summary, reset confirmation, empty summary, model required |
| `questions` | 1 | Saved questions and answers |
| `sharing` | 2 | Export and share sheet |
| `models` | 2 | Speech and summary model lists |
| `parakeet` | 8 | Repository, source, compatibility, requirements, download selection, import/pack pickers, model card |
| `downloads` | 2 | Download and verification progress |
| `installed-models` | 3 | Installed summary models, details, removal confirmation |
| `settings` | 3 | Storage check, app version, device information |

Output is grouped by appearance first, then category, with stable filenames:

```text
AppUI_Screenshots/
  light/
    transcript/meeting_transcript_light.png
    summary/meeting_summary_light.png
  dark/
    transcript/meeting_transcript_dark.png
    summary/meeting_summary_dark.png
  manifest.json
```

A successful partial run replaces only its selected images and preserves the rest. Each image's manifest entry retains its own commit, capture time, simulator, dimensions, and checksum, so a gallery can contain captures from several commits. An existing flat gallery is reorganized into this structure when it is next updated. A full run replaces the whole set, removing obsolete filenames. An incomplete or invalid download leaves the previous gallery in place. Progress is numbered against the selected total, such as `[3/6]`, alongside XCTest's elapsed time.

The folder is ignored by Git; screenshots are not committed or published. Temporary GitHub artifacts and the screenshot workflow run are deleted after the local transfer. The same 15-minute cleanup and one-day retention fallback described above apply. If final folder replacement fails, the command reports where the new and previous sets remain without restoring files automatically.

The [capture tests](./Tests/NativeUITests/AppScreenshotsUITests.swift) launch a fresh app instance and isolated sample library for each scene. The app selects the tab/meeting, loads data, expands the required section, and scrolls to a named anchor. Capture waits for an explicit data-ready marker and the scene's visible accessibility target. For Parakeet compatibility and requirements headings, if the form positions a heading behind the navigation bar, one drag calculated from the measured heading and navigation bounds uncovers it; capture also requires the entire heading to fit inside the visible content area. Native menus, share sheets, pickers, and confirmations use only their explicit presentation controls (at most two taps for the restore picker reached through its menu). There are no swipe searches or dependencies on a previous scene. Each scene has bounded readiness waits; failure records a diagnostic image and accessibility tree, then capture continues with the next scene.

The workflow selects an installed simulator runtime matching Xcode's iOS SDK. Simulator startup has a separate five-minute limit; a startup failure stops capture and reports the available devices. Screenshots retain the simulator's normal status bar, so its clock and indicators can vary between runs.

Long pages have separate captures for their sections. Capture uses the production SwiftUI views with DEBUG-only sample meetings and display inputs. Recording/download states, missing-model messages, and the model card fixture are presentation examples, not real microphone activity or inference. No model weights are downloaded for this workflow. iOS-owned surfaces outside the app, such as the Lock Screen/Dynamic Island, are not part of the catalog. Screenshots use [XCTest screenshot attachments](https://developer.apple.com/documentation/xcuiautomation/xcuiscreenshot).

If capture or compilation fails after the capture step starts, the workflow transfers the available images, diagnostic images, `manifest.json`, and `capture.log`. The local command reports the failure and leaves that evidence in `.agent-local/screenshots-<request-id>/`; it preserves the previous `AppUI_Screenshots/` gallery and still deletes the temporary GitHub artifact and run. Simulator/setup failures before capture remain workflow errors without a screenshot bundle.

Open the PNGs on Windows and give feedback using their filenames. Rerun the same command after pushing UI changes to replace the images.

## Local validation on macOS

After preparing the native frameworks, a quick check that does not download model fixtures is:

```bash
swift test --skip 'ASRTests[.](?!ASRCorpusScoringTests)|Actual[A-Za-z]+Tests|Phi3IntegrationTests|LocalSummaryRuntimeTests'
node --test scripts/tests/*.test.mjs
```

The exclusion selects tests that do not require downloaded model/audio fixtures; it does not mark missing native inputs as passing. Real-model tests remain in the repository and fail if their required inputs are absent.

### Native model fixtures

The helpers below verify pinned revisions, byte counts, and SHA-256 values. Their outputs stay under ignored `.agent-local/`. The full test workflow prepares all of them automatically. For local development, prepare only the suites relevant to a change.

| Model | Preparation from repository root | Test environment |
| --- | --- | --- |
| Parakeet v2 | `python3 scripts/fixtures/prepare_native_parakeet_fixture.py` | `LOCALMINUTES_PARAKEET_COREML_MODEL_DIRECTORY=$PWD/.agent-local/parakeet-coreml-fixtures/model`; `LOCALMINUTES_PARAKEET_COREML_FIXTURE_PATH=$PWD/.agent-local/parakeet-coreml-fixtures/6930-75918-0000.flac` |
| Parakeet v3 | `python3 scripts/fixtures/prepare_native_parakeet_fixture.py --version v3` | `LOCALMINUTES_PARAKEET_V3_DIRECTORY=$PWD/.agent-local/parakeet-v3-fixtures/model`; `LOCALMINUTES_PARAKEET_V3_PACK=$PWD/Tests/Fixtures/Parakeet/parakeet-v3.modelpack.json` |
| Qwen2.5 1.5B | `python3 scripts/fixtures/prepare_native_summary.py` | `LOCALMINUTES_QWEN_MODEL_PATH=$PWD/.agent-local/native-llm/qwen2.5-1.5b-instruct-q4_k_m.gguf` |
| Phi-3 mini | `python3 scripts/fixtures/prepare_phi3_fixture.py` | `LOCALMINUTES_PHI_MODEL_PATH=$PWD/.agent-local/phi3-fixtures/Phi-3-mini-4k-instruct-q4.gguf` |

Export the relevant environment variables in your shell before running tests. The Qwen and Phi helpers append their variables to `GITHUB_ENV` when it exists; they cannot export variables into a parent interactive shell.

For example, after preparing Parakeet v2 and exporting its two variables, provide the source identity used by the metrics tests (GitHub Actions sets it automatically):

```bash
export GITHUB_SHA="$(git rev-parse HEAD)"
swift test --filter 'CoreMLParakeetRecognizerTests|LiveTranscriptionSessionTests|RecoveredTranscriptionReplayTests|TranscriptionReplayCheckpointIntegrityTests'
```

After preparing Phi-3 and exporting its variable:

```bash
swift test --filter 'Phi3IntegrationTests|ActualSelectedModelIntelligenceTests|ActualResumedPhiIntelligenceTests'
```

Parakeet v3 tests also use the v2 fixture's licensed audio, so prepare both versions and export the v2 variables as well. See [ParakeetModelPackNativeTests.swift](./Tests/ASRTests/ParakeetModelPackNativeTests.swift) for the exact input checks. Run these baseline suites with `swift test --skip ActualCatalogAdapterIntegrationTests`; the catalogue suite requires a separate variant-specific fixture.

The all-tests workflow derives a twelve-variant matrix from the bundled catalogue. Each job downloads one artifact with [prepare_catalog_model.mjs](./scripts/fixtures/prepare_catalog_model.mjs), verifies its pinned size and checksum, and runs [ActualCatalogAdapterIntegrationTests](./Tests/IntelligenceTests/ActualCatalogAdapterIntegrationTests.swift) through the production loader. For a focused macOS run:

```bash
node scripts/fixtures/prepare_catalog_model.mjs --variant qwen3-0.6b-q8_0
export LOCALMINUTES_CATALOG_VARIANT_ID=qwen3-0.6b-q8_0
export LOCALMINUTES_CATALOG_MODEL_PATH="$PWD/.agent-local/catalog-fixtures/qwen3-0.6b-q8_0/Qwen3-0.6B-Q8_0.gguf"
swift test --filter ActualCatalogAdapterIntegrationTests
```

These integration checks exercise actual model loading, token counting, structured generation, and resource release. They do not substitute for iPhone memory, thermal, or meeting-quality evaluation.

### Speech quality checks

[ASRQualityCorpus.json](./Tests/Fixtures/ASRQualityCorpus.json) describes three public LibriSpeech clips: 45.85 seconds and 116 reference words. Run [prepare_asr_quality_corpus.py](./scripts/prepare_asr_quality_corpus.py), then export `LOCALMINUTES_ASR_CORPUS_DIRECTORY=$PWD/.agent-local/asr-quality-corpus`. Prepare the Parakeet v2 fixtures above and run the quality case in [ASRCorpusQualityTests.swift](./Tests/ASRTests/ASRCorpusQualityTests.swift).

Parakeet v2 processes all three clean clips and deterministic 15 dB SNR noise derivatives. Scoring lowercases Unicode, splits on non-letter/non-number characters, and computes Levenshtein word errors without synonym or number substitutions. Aggregate thresholds are 15% clean and 25% noisy WER. The test records per-clip results and noise-generation metadata even when a quality assertion fails.

The fixture metadata and audio retain their [OpenSLR LibriSpeech](https://www.openslr.org/12/) / [dataset publisher](https://huggingface.co/datasets/openslr/librispeech_asr) attribution and CC-BY-4.0 terms. These short audiobook samples do not establish accuracy for meetings, accents, overlapping speakers, or room acoustics.

### iOS tests and packaging

[project.yml](./project.yml) provides these schemes:

| Scheme | Coverage |
| --- | --- |
| `LocalMinutesFocusedValidation` | App-hosted integration tests, recording intents, service ownership, storage, and UI-facing controllers |
| `LocalMinutesUIValidation` | Simulator UI flows and accessibility |
| `LocalMinutes` | App/extension build and combined app-hosted/UI tests |

Use `xcodebuild test` with an available iPhone simulator destination and the same source-commit build setting used above. All retained tests can run on hosted macOS. Simulator results do not establish physical lock-state protection, microphone endurance, thermal behavior, or Action Button delivery.

For local packaging on a Mac, build the Release device app into `build/device` and the Debug simulator app into `build/simulator`, as shown in the [test workflow](./.github/workflows/tests.yml). Before installing a test runner into the simulator build, run:

```bash
node --test scripts/native-tests/*.test.mjs
node --input-type=module <<'JS'
import { execFileSync } from 'node:child_process';
import { createUnsignedIPA } from './scripts/package-ios.mjs';
console.log(await createUnsignedIPA({
  appPath: 'build/device/Build/Products/Release-iphoneos/LocalMinutes.app',
  outputDirectory: 'build/unsigned',
  sourceCommit: execFileSync('git', ['rev-parse', 'HEAD'], { encoding: 'utf8' }).trim()
}));
JS
```

The output directory must not already exist. [package-ios.mjs](./scripts/package-ios.mjs) exports a function; invoking that file alone does not create a package. It writes an IPA, SHA-256 sidecar, and build manifest after checking native architectures, bundle/source identity, unsigned state, and excluded private/model data.

## Data and dependencies

Recordings, transcripts, notes, and generated documents live in protected application storage. Backups are user-exported `.localminutesbackup` directory packages containing private meeting data; they are not encrypted by the app. Backup restore switches the active library while retaining the previous generation. Model files and diagnostics are separate from the meeting backup.

Keep real recordings, databases, downloaded weights, signing material, and generated build products out of Git. [THIRD_PARTY_NOTICES.txt](./Resources/THIRD_PARTY_NOTICES.txt) is a bundled legal resource and remains alongside the app's [privacy manifest](./Resources/PrivacyInfo.xcprivacy). Native dependency pins and their boundaries are documented in [ARCHITECTURE.md](./ARCHITECTURE.md#native-dependencies).
