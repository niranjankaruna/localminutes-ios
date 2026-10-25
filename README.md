# LocalMinutes

LocalMinutes is an iPhone app for recording meetings, transcribing audio on the device, and generating summaries and answers from a selected meeting. Meeting data stays in the app unless the user explicitly exports it. There is no application server, account system, or cloud transcription service.

The app has three tabs:

- **Record:** microphone recording, live transcript, notes, recording status, and a Live Activity. Shortcuts support starting, stopping, and toggling a recording.
- **Meetings:** history, rename, notes, transcript search and playback, summaries, cited answers, text/Markdown export, backup, and recovery of interrupted recordings.
- **Models:** inspect public Hugging Face repositories, download or import supported model files, verify installations, and select speech and summary models.

See [ARCHITECTURE.md](./ARCHITECTURE.md) for ownership, data flow, storage, recovery, and inference contracts.

## Requirements

| Item | Requirement |
| --- | --- |
| App | iPhone, iOS 18 or later; microphone permission and a verified speech model |
| Development | macOS 15 or later, Xcode 26.2 / Swift 6.2 toolchain |
| Project generation | XcodeGen 2.46.0 or later; CI pins 2.46.0 |
| Build helpers | Python 3 with its standard library, CMake, Git, and Node.js 22 |
| Optional system summaries | iOS 26 or later, supported Apple Intelligence hardware, and system model availability |

Internet access is needed to fetch native libraries, Swift packages, and model weights. Installed local models process recordings without a network service. Storage and RAM estimates in the model browser are advisory; installation verification does not establish inference speed or accuracy on a particular phone.

## Build

Run commands from the repository root. [Package.swift](./Package.swift) defines the Swift modules and macOS tests; [project.yml](./project.yml) defines the iOS app, extension, and native test targets. Generated Xcode projects and downloaded artifacts are ignored by Git.

Prepare the native libraries **before** resolving Swift packages or generating the Xcode project:

```bash
export DEVELOPER_DIR=/Applications/Xcode_26.2.app/Contents/Developer
python3 scripts/prepare_asr_only.py --platform all
python3 scripts/fixtures/prepare_native_summary.py --framework-only
xcodegen generate --spec project.yml
export LOCALMINUTES_SOURCE_COMMIT="$(git rev-parse HEAD)"

xcodebuild -project LocalMinutes.xcodeproj -scheme LocalMinutes \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/simulator CODE_SIGNING_ALLOWED=NO \
  LOCALMINUTES_SOURCE_COMMIT="$LOCALMINUTES_SOURCE_COMMIT" build
```

The summary helper also prepares the Whisper framework. `--framework-only` downloads no model weights. The ASR helper accepts `macos`, `ios`, or `all`; each invocation replaces its generated framework with the requested platform slices. Use `all` when running both SwiftPM tests and iOS builds from one checkout.

The app requires a valid 40-character source commit stamp and numeric build number when initializing services. If building in Xcode's UI, set `LOCALMINUTES_SOURCE_COMMIT` in the app and extension build settings to the checkout's commit. A missing stamp can leave recording services unavailable.

Signing is disabled in the checked-in project configuration. Running on a physical iPhone requires configuring signing for both the app and its Live Activity extension. An unsigned IPA is a packaging output, not an installable signed app.

## Use the app

1. Open **Models**, install a supported speech model, and select it for speech recognition. The built-in streaming English Zipformer download is about 73 MB. Whisper and complete reviewed Parakeet Core ML packs are also supported.
2. Optionally select a local GGUF summary model or an available Apple Intelligence provider. The local runtime supports reviewed Qwen2 and Phi3 architectures. A file being GGUF alone does not make it compatible.
3. Start recording from **Record** or a recording Shortcut. Recording becomes active only after the audio session, microphone buffer, and Live Activity are ready. There is no recording-only fallback when speech preparation fails.
4. Stop recording before requesting a summary or asking a question. Review generated content and its citations. Editable generated text is kept separately from the original output and transcript.

Recording, playback, inference, and library maintenance share admission controls. A pending cleanup can temporarily block another operation until its resources are released. Interrupted audio remains available for recovery; recovery needs the exact speech-model installation originally pinned to the meeting.

## GitHub workflows from Windows

There are two manually triggered workflows. Neither publishes releases or uses persistent build caches:

- [Run all tests](./.github/workflows/tests.yml) runs every retained SwiftPM test, including actual model inference and speech-quality tests, plus Node tests, iOS app-hosted/UI tests, native packaging tests, and the IPA symbol audit. Its macOS runners discard build outputs when the jobs end. No physical iPhone or self-hosted Mac is needed.
- [Build IPA for local download](./.github/workflows/build-ipa.yml) builds an unsigned IPA for the local transfer script. It uploads only a temporary transfer artifact, not a release.

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
| Zipformer | `python3 scripts/fixtures/prepare_native_fixture.py` | `LOCALMINUTES_ASR_MODEL_DIRECTORY=$PWD/.agent-local/asr-evaluation/native-fixtures/model`; `LOCALMINUTES_ASR_FIXTURE_PATH=$PWD/.agent-local/asr-evaluation/native-fixtures/6930-75918-0000.flac` |
| Whisper tiny.en | `python3 scripts/fixtures/prepare_whisper_fixture.py` | `LOCALMINUTES_WHISPER_MODEL_PATH=$PWD/.agent-local/whisper-fixtures/ggml-tiny.en.bin`; `LOCALMINUTES_WHISPER_FIXTURE_PATH=$PWD/.agent-local/whisper-fixtures/6930-75918-0000.flac` |
| Parakeet v2 | `python3 scripts/fixtures/prepare_native_parakeet_fixture.py` | `LOCALMINUTES_PARAKEET_COREML_MODEL_DIRECTORY=$PWD/.agent-local/parakeet-coreml-fixtures/model`; `LOCALMINUTES_PARAKEET_COREML_FIXTURE_PATH=$PWD/.agent-local/parakeet-coreml-fixtures/6930-75918-0000.flac` |
| Parakeet v3 | `python3 scripts/fixtures/prepare_native_parakeet_fixture.py --version v3` | `LOCALMINUTES_PARAKEET_V3_DIRECTORY=$PWD/.agent-local/parakeet-v3-fixtures/model`; `LOCALMINUTES_PARAKEET_V3_PACK=$PWD/Tests/Fixtures/Parakeet/parakeet-v3.modelpack.json` |
| Qwen2.5 1.5B | `python3 scripts/fixtures/prepare_native_summary.py` | `LOCALMINUTES_QWEN_MODEL_PATH=$PWD/.agent-local/native-llm/qwen2.5-1.5b-instruct-q4_k_m.gguf` |
| Phi-3 mini | `python3 scripts/fixtures/prepare_phi3_fixture.py` | `LOCALMINUTES_PHI_MODEL_PATH=$PWD/.agent-local/phi3-fixtures/Phi-3-mini-4k-instruct-q4.gguf` |

Export the relevant environment variables in your shell before running tests. The Whisper, Qwen, and Phi helpers append their variables to `GITHUB_ENV` when it exists; they cannot export variables into a parent interactive shell.

For example, after preparing Zipformer and exporting its two variables:

```bash
swift test --filter 'CPUStreamingRecognizerTests|LiveTranscriptionSessionTests|RecoveredTranscriptionReplayTests|TranscriptionReplayCheckpointIntegrityTests'
```

After preparing Phi-3 and exporting its variable:

```bash
swift test --filter 'Phi3IntegrationTests|ActualSelectedModelIntelligenceTests|ActualResumedPhiIntelligenceTests'
```

Parakeet v3 tests also use the v2 fixture's licensed audio, so prepare both versions and export the v2 variables as well. See [ParakeetModelPackNativeTests.swift](./Tests/ASRTests/ParakeetModelPackNativeTests.swift) for the exact input checks. Once every fixture and environment variable is ready, `swift test` runs the complete SwiftPM suite without filters.

### Speech quality checks

[ASRQualityCorpus.json](./Tests/Fixtures/ASRQualityCorpus.json) describes three public LibriSpeech clips: 45.85 seconds and 116 reference words. Run [prepare_asr_quality_corpus.py](./scripts/prepare_asr_quality_corpus.py), then export `LOCALMINUTES_ASR_CORPUS_DIRECTORY=$PWD/.agent-local/asr-quality-corpus`. Prepare the relevant Zipformer or Parakeet v2 fixtures above and run the corresponding case in [ASRCorpusQualityTests.swift](./Tests/ASRTests/ASRCorpusQualityTests.swift).

Each model processes all three clean clips and deterministic 15 dB SNR noise derivatives. Scoring lowercases Unicode, splits on non-letter/non-number characters, and computes Levenshtein word errors without synonym or number substitutions. Aggregate thresholds are 15% clean and 25% noisy WER. The test records per-clip results and noise-generation metadata even when a quality assertion fails.

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

The [native symbol audit](./scripts/native-hygiene-tests/test_no_unused_tts.py) reads the resulting IPA without extraction. Set `LOCALMINUTES_AUDIT_IPA`, `LOCALMINUTES_AUDIT_SOURCE_COMMIT`, and `LOCALMINUTES_AUDIT_IPA_SHA256` from the package receipt, then run:

```bash
python3 -m unittest discover -s scripts/native-hygiene-tests -p 'test_*.py' -v
```

## Data and dependencies

Recordings, transcripts, notes, and generated documents live in protected application storage. Backups are user-exported `.localminutesbackup` directory packages containing private meeting data; they are not encrypted by the app. Backup restore switches the active library while retaining the previous generation. Model files and diagnostics are separate from the meeting backup.

Keep real recordings, databases, downloaded weights, signing material, and generated build products out of Git. [THIRD_PARTY_NOTICES.txt](./Resources/THIRD_PARTY_NOTICES.txt) is a bundled legal resource and remains alongside the app's [privacy manifest](./Resources/PrivacyInfo.xcprivacy). Native dependency pins and their boundaries are documented in [ARCHITECTURE.md](./ARCHITECTURE.md#native-dependencies).
