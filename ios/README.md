# LocalMinutes

LocalMinutes is an iPhone app for recording meetings, transcribing audio on the device, and generating summaries and answers from a selected meeting. Meeting data stays in the app unless the user explicitly exports it or syncs with a paired device. There is no hosted application server, account system, or cloud transcription service.

The app has three tabs:

- **Meetings:** history and search, with focused Summary, Transcript, Notes, and Ask views. Meeting actions provide rename, recovery, export, and deletion.
- **Record:** a single start/stop control, live transcript and notes, recording status, and a Live Activity. The three shortcuts open Recording, Meetings, or the last meeting; none starts recording.
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

The iOS source and build helpers now live in `ios/`. Run the commands below from this directory, not the repository root.

Run commands from this iOS directory. [Package.swift](./Package.swift) defines the Swift modules and macOS tests; [project.yml](./project.yml) defines the iOS app, extension, and native test targets. Generated Xcode projects and downloaded artifacts are ignored by Git.

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
2. In **Settings → Summaries & answers**, choose a family and variant, download it, and equip it. The catalogue includes Qwen 2.5 (0.5B/1.5B), Qwen 3 (0.6B/1.7B/4B/4B Instruct 2507), Phi-3 mini 4K, Phi-4 mini, Gemma 3 (1B/4B IT QAT), and Gemma 4 (E2B/E4B IT QAT). Each variant card shows its maximum context in tokens. Summaries use a bounded working window within that limit; answers retain their own evidence budget. There is no repository search or arbitrary model import. Qwen 2.5 3B is excluded.
3. Open **Settings → Recording permissions** (also available from the gear button in **Record**) to check microphone access and Live Activities. Tap **Allow microphone** for first-time setup. This works before a speech model is installed and does not start recording. iPhone Settings may not show a microphone switch until you respond to the system prompt. If access was denied, enable it in **iPhone Settings → Apps → LocalMinutes** or **Privacy & Security → Microphone**.
4. Assign the iPhone Action Button to **Open Recording**, **Open Meetings**, or **Open Last Meeting**. All three open LocalMinutes and require device unlock; none starts or toggles recording. **Open Meetings** opens the history list, and **Open Last Meeting** opens the newest saved meeting, falling back to the list if it is empty or unavailable. Existing Start/Stop/Toggle shortcut assignments must be replaced with one of these navigation actions. To record, tap **Record** inside the app after completing microphone permission and speech-model setup. Wait until **Recording** appears, then you can lock the phone or switch apps while capture continues. The Live Activity retains its session-specific Stop control. Recording becomes active only after the audio session, microphone buffer, and Live Activity are ready; there is no recording-only fallback when speech preparation fails. Calls, audio interruptions, and system resource limits can still interrupt capture. Physical lock-screen continuation and Action Button delivery require device validation.
5. Stop recording before requesting a summary or asking a question. Review generated content and its citations. Editable generated text is kept separately from the original output and transcript.
6. To remove a generated summary, open **Summary options → Delete summary…** and confirm. This removes the meeting's summary versions and summary edits while keeping its recording, transcript, notes, saved answers, and any unfinished generation progress.

Recording, playback, inference, and library maintenance share admission controls. A pending cleanup can temporarily block another operation until its resources are released. Interrupted audio remains available for recovery; recovery needs the exact speech-model installation originally pinned to the meeting.

Recording starts inside the app because iOS can reject a new audio session activated from the background. Continuing an already-started recording after screen lock uses the configured `audio` background mode, as described in Apple's [audio-session documentation](https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/record). If capture fails, **Record → Recording error details** shows the failed hardware setup step and native error domain/code when available. These details remain in memory after cleanup and belong only to that recording attempt; they do not include audio, transcript text, paths, or the error's user-info dictionary.

Summary and Q&A generation request iOS background execution when you start them. On iOS 26+, continued-processing tasks keep generation attached to system-managed execution after switching apps or locking the screen, with generic progress and cancellation controls. Busy systems can queue the request; the app waits for its launch instead of cancelling it after five seconds or starting inference under a short fallback allowance. Installed models report progress during file verification, prompt processing, and response generation, and during local response validation. Locking the screen and leaving the detail view do not cancel generation; reopening a meeting rejoins its active controller. Earlier iOS versions, or devices where the scheduler rejects a continued task, use UIKit's limited background allowance. iOS can still expire work under resource pressure or stop it when the app is force-quit; interrupted summaries show an explanation and can be generated again from the full transcript. Physical-device execution time and locked-screen behavior require device testing.

**Remove** deletes installed model files and retained partial-download bytes; it also clears the equipped selection when necessary. Meetings and notes remain. A model in active use cannot be removed until its inference work finishes. Downloading does not automatically equip a model. Apple Intelligence is no longer offered. A previously saved Apple selection is treated as explicitly unequipped, so choose a downloaded model; existing saved summaries remain in the library.

During summary or answer generation, the detail screen shows progress and elapsed time. Summary generation prepares the complete transcript, writes the overview and minutes in one model call, validates the returned JSON and source references locally, and saves the result. Native prompt and response token counters advance within the generation step. Percentage reaches 100 only after the document is saved. Failure messages include the stopped step and a diagnostic code. An interrupted attempt starts over only when the user asks to generate again.

Summaries display two sections: **Overview** and **Minutes of Meetings**, both with bullet points and justified text. Overview includes the saved meeting date and time, followed by short points describing what the meeting was about. Minutes of Meetings contains the substantive discussion points. The writer paraphrases supported ideas; it does not create separate Decisions or Actions sections. Exact transcript excerpts remain behind the prose as citations. Newly generated saved/exported text uses the same headings and bullets. Older unedited summaries are grouped into the two sections for reading; user-edited text remains intact and is also displayed with justified alignment. The reader supports text selection and Dynamic Type.

[AdaptiveSummaryPipeline](./Summaries/AdaptiveSummaryPipeline.swift) makes one request containing the full selected meeting transcript and its notes. It does not truncate, chunk, retry, repair, switch models, or substitute transcript excerpts. If the input and expected output do not fit together, it fails before inference. Invalid or incomplete output and runtime failures end the attempt without saving a partial summary.

[NarrativeSummaryWriter](./Summaries/NarrativeSummaryWriter.swift) asks for concise discussion bullets and a short overview, preserving conditions, attribution and explicit corrections. Citation IDs are constrained by the JSON schema and checked against original source units before saving. These local checks establish valid format and citation membership; they do not prove factual accuracy. There are no additional model-based review calls.

[NarrativeSummaryBudget](./Summaries/NarrativeSummaryBudget.swift) uses the selected runtime's full context limit and output ceiling. The tokenizer counts the actual prompt including system instructions, notes, source labels and chat formatting. The expected response allowance is `min(modelOutputLimit, max(512, inputTokens / 4))`, with 64 extra tokens of headroom. This allowance scales with the input; it is a maximum, not a target length. The whole request must fit without reducing that allowance to force admission. The earlier 8,192-token working cap and 24-source-unit draft gate have been removed.

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

The selected variant supplies the hard runtime limit, including for existing installations with matching pinned weights. Qwen 3 4B enables the publisher's [YaRN settings](https://qwen.readthedocs.io/en/latest/run_locally/llama.cpp.html) to extend its native 32,768-token window by a factor of four. Context memory grows to fit actual requests up to the selected maximum; a short request does not preallocate the entire maximum window. Full-window requests still require sufficient device memory. Output and citation bounds remain separate from the context capacity. New summaries always start from the complete transcript. Legacy checkpoint files are ignored during generation and removed after a successful save; completed documents remain readable.

Output caps are ceilings, not target lengths, and are reserved inside the total context window. Qwen 2.5 uses its published 8,192-token generation limit; Qwen 3 uses its [16,384-token non-thinking/instruct limit](https://qwen.readthedocs.io/en/latest/getting_started/concepts.html). Gemma 3 uses the 8,192-token output limit reported in its [model card](https://huggingface.co/google/gemma-3-1b-it). Phi and Gemma 4 caps are app policies within their published context windows, not claims of separate vendor output limits. Q&A still returns a bounded evidence quote using its separate 192-token response budget.

The native decoder checks whether the greedy candidate fits the JSON grammar before filtering the whole vocabulary, matching llama.cpp's rejection-sampling fast path. Forbidden candidates still use full grammar filtering, and each accepted token advances the grammar exactly once.

## GitHub workflows from Windows

There are three manually triggered workflows. None publishes releases or uses persistent build caches:

- [Run all tests](./.github/workflows/tests.yml) runs every retained SwiftPM test, including actual model inference and speech-quality tests, plus Node tests, iOS app-hosted/UI tests, native packaging tests. Its macOS runners discard build outputs when the jobs end. No physical iPhone or self-hosted Mac is needed.
- [Build IPA for local download](./.github/workflows/build-ipa.yml) builds an unsigned IPA for the local transfer script. It uploads only a temporary transfer artifact, not a release.
- [Capture app UI for local download](./.github/workflows/app-screenshots.yml) runs the real app in an iPhone simulator, captures light/dark screenshots with sample data, and transfers them to the local project.

After committing and pushing these files to GitHub, run all tests from the Actions page or with GitHub CLI:

```powershell
gh workflow run tests.yml
```

For focused validation of single-pass summaries, fail-fast limits, real SQLite saving/reopening, the iOS build, and short/hour-length synthetic transcripts using Qwen 2.5 0.5B and Qwen 3 0.6B:

```powershell
gh workflow run tests.yml -f scope=summaries
```

The native tests run the actual Swift pipeline and selected weights, with no canned review verdicts. They log stage timings, completion and excerpt counts; JSON-format-only smoke tests are not substitutes for this suite.

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

# All transcript and summary screens, dark mode only (22 screenshots).
node scripts/download-screenshots.mjs --appearance dark --categories transcript,summary

# Just these two screens, in both appearances (4 screenshots).
node scripts/download-screenshots.mjs --screens meeting_transcript,meeting_share_sheet

# A screen and its category's related states, in both appearances (10 screenshots).
node scripts/download-screenshots.mjs --screens meeting_transcript --related

# Preview any selection by adding --list; this makes no GitHub requests.
node scripts/download-screenshots.mjs --appearance light --categories parakeet --list
```

`--appearance` accepts `both` (default), `light`, or `dark`. `--categories` and `--screens` accept comma-separated names; when both are supplied, their selections are combined without duplicates. `--related` requires `--screens` and adds every scene in each named screen's category. With neither category nor screen filters, all scenes are selected. Unknown names fail before dispatch. The workflow's manual inputs expose the same `appearance`, `categories`, `screens`, and `related` choices; the local command handles download and remote cleanup.

The [shared capture catalog](./Shared/AppScreenshotScene.swift) defines **118 screen, section, sheet, and state captures (236 PNGs in both appearances)**. It supplies categories, navigation actions, required visible elements, expected state text, and confirmation titles to both the native runner and [app-screenshots.mjs](./scripts/app-screenshots.mjs). There is no separate JavaScript screen list. Counts are per appearance:

| Category | Scenes | Included views |
| --- | ---: | --- |
| `recording` | 13 | Idle/setup, active transcript/notes, preparing/stopping/listening/backlog, microphone/capture/storage errors, model setup sheet |
| `library` | 20 | History/search/empty/loading/error, menus, rename, backup progress/ready/error, restore picker/confirmation/error/progress, report, both meeting-deletion entry points |
| `notes` | 4 | Saved/empty notes, editor, save failure |
| `transcript` | 5 | Transcript, search/no matches, unavailable, recovery |
| `summary` | 17 | Plain/structured/edited/empty summaries, sources/details/editor, model requirement/setup sheet, generation/cancellation/paused/error, edit conflict, reset/delete/replace confirmations |
| `questions` | 9 | Saved/empty answers, keyboard composer, editor/sources, generation/error, edit conflict/replace confirmation |
| `sharing` | 5 | Text/Markdown export, native share sheet, pending edits, export failure |
| `models` | 8 | Speech/summary lists and expanded variant cards, summary details/context, insufficient storage, error |
| `parakeet` | 5 | Overview, source/license, download/storage, expanded attribution, expanded revision/files |
| `downloads` | 9 | Preparing/downloading/verifying/installing/completed/paused/failed, transfer details, no transfer |
| `installed-models` | 4 | Installed models, details, removal confirmation, selected model |
| `settings` | 8 | Root, privacy, permissions, About/device, storage ready/preparing/error |
| `permissions` | 7 | Unrequested/allowed/denied microphone, disabled Live Activities, native microphone prompt, privacy sheet and details |
| `live-activity` | 3 | Recording/saved/interrupted shared controls in an app-hosted fixture |
| `launch` | 1 | The real launch storyboard in an app-hosted fixture |

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

A successful partial run replaces only its selected images and preserves the rest. Each image retains its commit, capture time, simulator, dimensions, and checksum. New version-3 entries also retain the native visibility receipt and that build's capture contract. Older 74/82-image galleries remain readable and are preserved during partial updates; they do not gain validation evidence retroactively. A full run replaces the whole set, removing obsolete filenames. An incomplete or invalid download leaves the previous gallery in place. Progress is numbered against the selected total.

The folder is ignored by Git; screenshots are not committed or published. Temporary GitHub artifacts and the screenshot workflow run are deleted after the local transfer. The same 15-minute cleanup and one-day retention fallback described above apply. If final folder replacement fails, the command reports where the new and previous sets remain without restoring files automatically.

The [capture tests](./Tests/NativeUITests/AppScreenshotsUITests.swift) launch a fresh app and isolated sample library for every scene. They wait for data readiness, perform the declared presentation actions, and reveal the required content using bounded drags based on measured clipping. Required elements must fit entirely within their content or chrome region, above the tab bar/keyboard and clear of pinned controls. A group that cannot fit fails with a request to split the scene into section captures. Three stable layout samples are required before capture.

All eight confirmation presentations check their expected dialog title, primary action, and visible Cancel button. Sheets check their relevant editor/share/setup controls and dismissal actions. Expanded model-variant captures additionally require visible Download text inside a button at least 44 points in both dimensions and no more than 80 points high at standard text size. The [native regression](./Tests/NativeUITests/ModelBrowserAccessibilityUITests.swift) also exercises these controls at the largest accessibility text size.

Every successful image has an accompanying XCTest JSON attachment containing its scene/appearance, pixel dimensions, checked frames, chrome/content bounds, keyboard state, and capture contract. Collection validates this evidence and stores it in the manifest. Missing or invalid evidence makes the image diagnostic rather than publishable. A failed scene records its screenshot and accessibility tree and does not stop the remaining scenes; the incomplete set cannot replace the current gallery.

The workflow selects an installed simulator runtime matching Xcode's iOS SDK. Simulator startup has a separate five-minute limit; a startup failure stops capture and reports the available devices. Screenshots retain the simulator's normal status bar, so its clock and indicators can vary between runs.

Long pages have separate section captures. The runner uses production SwiftUI views with DEBUG-only sample meetings and frozen display states; it never executes deletion, restoration, model download, or inference. The native microphone-prompt scene resets the simulator app's microphone authorization and opens the real OS prompt without starting a recording. Launch and Live Activity captures are explicitly marked as hosted fixtures; they do not prove OS launch timing, Lock Screen delivery, or Dynamic Island rendering. Those surfaces still need device checks. Removed import/pack-picker routes are not reintroduced. Screenshots use [XCTest screenshot attachments](https://developer.apple.com/documentation/xcuiautomation/xcuiscreenshot).

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

Local synthetic prompt/schema smoke checks for the narrative redesign on Qwen 2.5 0.5B and 1.5B found remaining factual-quality limits: superseded dates or conditional language could be misrepresented, and model review sometimes approved those errors. The 0.5B model also produced an empty bullet list for one conditional example, which the application rejects. These checks used the pinned Windows CPU inference runtime, not the Swift application. They do not establish a quality score; the macOS/iOS integration suite and representative meeting evaluation remain necessary.

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
