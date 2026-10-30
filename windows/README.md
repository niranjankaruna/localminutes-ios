# LocalMinutes for Windows

Native Windows 11 x64 application with local meeting storage, microphone recording, Parakeet transcription, llama.cpp summaries/answers, and direct local-network copying to the iPhone app. The desktop layout follows the [Figcraft reference](./Design/LocalMinutes-Windows-Plan.figcraft).

## Portable application

Extract the complete release ZIP to a writable folder and launch **LocalMinutes.exe**. Keep its runtime libraries beside it. The folder contains the .NET desktop runtime, speech runtime and llama.cpp tools; there is no application server or separate engine installation. Model weights are downloaded separately in Settings and are not included in the release ZIP.

The default writable profile is **LocalMinutes.Data** beside the executable. It contains the SQLite library, original audio, models, model selections, device identity, pairing material and transfer staging. Use `--data-directory <absolute-path>` to select another profile. One process may write to a profile at a time. Each process has a new instance UUID; the device UUID persists across launches.

Move the entire folder, including its data, to keep recordings and models. Windows protects pairing credentials for the current user/machine; moving to another computer requires pairing again. An unwritable executable location opens a data-folder chooser.

## First use

1. Open Settings and download **Parakeet v3** for microphone transcription (about 670 MB).
2. Choose a summary model, download it, then select **Equip selected**. Downloading a summary model does not equip it automatically. Saved meeting content remains readable without models.
3. In Record, select your microphone and start recording. Stop to finish saving/transcription before generating a summary, asking a question, importing, or syncing.
4. Meetings has Summary, Transcript, Notes and Ask views. Notes save automatically. Generated edits remain separate from original JSON. Sources opens verified citations and can play the corresponding recording position.
5. Settings can import an iPhone `.localminutesbackup` directory package or a `.lmtransfer` exchange folder. Export creates a new `.lmtransfer` folder containing saved meeting data without models.

Windows currently uses five-second transcription windows. The original 16 kHz mono PCM CAF audio is retained in segments of at most 60 seconds. Following a crash, closed segments remain playable and the meeting is marked interrupted; unclosed tails remain preserved. Automatic cross-platform transcription replay/versioning is not implemented.

## Wi-Fi sync

The updated iPhone source must first be built and installed. Existing iPhone releases without this protocol cannot sync.

1. Open Sync on Windows and choose **Pair an iPhone**. Choose the PC's actual local Wi-Fi/Ethernet address if it has several adapters.
2. On iPhone, open Sync from Meetings or Settings and scan the invitation. Pasting the connection code is also supported. The invitation expires after five minutes. Never share a pairing invitation with another person.
3. Keep the iPhone **Sync screen open and the phone unlocked**. Windows listens on local TCP port 47835; allow the app through Windows Firewall on the Private profile if prompted. There is no automatic firewall modification or cloud relay.
4. Press Sync on iPhone to send its saved library to Windows. Press Sync on Windows to send the PC's saved library to the connected iPhone.

Matching editable records use the sender's values even when the receiver's timestamp is newer. Receiver-only meetings and generated documents remain. Deletions and model downloads do not propagate. Consequently, a deleted meeting can return when the other device sends it back.

Original audio/transcript identity collisions are rejected. Transfers verify hashes, resume staged files, skip identical available recordings and acknowledge only committed imports. The PC hosts the TLS listener; the foreground phone connection can either upload or receive a queued PC send. This keeps certificate provisioning on Windows while retaining both button directions. Trust is pinned to the invitation certificate; an ID or a Wi-Fi name alone does not authorize a transfer.

Pairing uses a QR invitation or pasted code. On reconnect, the phone looks for the paired PC through Bonjour/DNS-SD, so an address change does not normally require pairing again; it falls back to the invitation's address if discovery is unavailable. The phone discovery code still requires native device validation. Guest Wi-Fi isolation and VPN policies can prevent local connectivity. Windows advertises on UDP 5353 and accepts the authenticated sync connection on TCP 47835.

A queued Windows send survives an app restart and stays bound to its original recipient. Reopen the iPhone Sync screen to resume. **Cancel PC send** clears the pending send, including a snapshot still being prepared; it cannot undo a transfer the iPhone has already committed.

## Build and test

Development needs Windows 11 x64, .NET SDK **10.0.403**, PowerShell and Node.js for the package audit. The SDK and runtime preparation scripts use pinned downloads and verified checksums. These requirements apply to developers, not users of the self-contained release folder.

From the repository root:

```powershell
powershell -File windows/scripts/setup-sdk.ps1
powershell -File windows/scripts/prepare-native.ps1
powershell -File windows/scripts/dotnet.ps1 build LocalMinutes.sln
powershell -File windows/scripts/dotnet.ps1 test tests/LocalMinutes.Tests/LocalMinutes.Tests.csproj
powershell -File windows/scripts/publish.ps1
```

The wrapper uses the repository-local SDK when present and puts NuGet/CLI caches under the ignored repository cache. Existing VS Code tasks build the app and run the xUnit/VSTest suite. Windows TLS tests need permission to use Schannel's temporary user key container; a restrictive filesystem sandbox can prevent those tests from starting.

The primary build for this machine is CUDA based. Prepare it with `prepare-native.ps1 -Backend cuda` and publish it with `publish.ps1 -Backend cuda`. CUDA is enabled initially and can be switched off in Settings. The engine has passed real summary/Q&A smoke tests on the reported RTX 5070 Ti, driver 617.42 / CUDA 13.4. It requires a compatible NVIDIA driver. A smaller CPU-only package can be published with the default script arguments; CPU inference has also passed real-model tests.

### Expanding only the Windows model list

Windows uses the widely adopted [llama.cpp engine](https://github.com/ggml-org/llama.cpp) for GGUF inference. Its [Windows catalog](./src/LocalMinutes.Core/Resources/SummaryCatalog.json) is an independent file, not generated from or linked to the iPhone catalog. Add larger reviewed GGUF variants here without changing iOS. Pin the publisher revision, filename, byte count, SHA-256, license, context limit and output budget. Existing supported families reuse [ChatFormat](./src/LocalMinutes.Core/LocalIntelligence.cs); a new architecture/template needs a reviewed adapter and possibly a newer pinned llama.cpp runtime. Downloading a bigger model does not mean its maximum published context fits in GPU memory; the actual prompt is tokenized and checked before inference, and runtime memory failures do not save partial documents.

The [native smoke program](./tests/LocalMinutes.NativeSmoke/Program.cs) supports real-model summary/Q&A tests and synthetic-WAV speech tests. It does not use the microphone. Debug builds also support an isolated `--preview --data-directory <empty-folder>` UI rendering check; this seeds synthetic data and does not start the sync listener. Preview mode is excluded from release builds.

## Validation and remaining limits

- Windows app and core compile with warnings treated as errors.
- All 26 automated Windows cases passed locally, including storage, CAF, sender-wins import, corruption rejection, device identity, interrupted-recording reconciliation, deletion recovery, real TLS transfers, and queued-send recovery/cancellation across restarts. A real multicast DNS-SD query also found the Windows advertisement.
- Actual pinned Qwen 2.5 0.5B inference has passed CPU and RTX 5070 Ti/CUDA summary-and-answer smoke tests. Parakeet v3 has passed a synthetic-WAV transcription test.
- Light, dark and 1280x800 layouts have been rendered and visually inspected.
- The actual packaged EXE passed its isolated self-check, loading the bundled .NET 10.0.14 runtime, WPF layout, ONNX/sherpa libraries and pinned llama.cpp binary. Package audits found no meeting/model data or missing imported C++/inference runtime DLLs. This does not replace testing on a clean Windows installation.
- All 127 existing iOS JavaScript build/helper tests passed after the directory migration. These are not Swift compilation or physical-device tests.
- iOS schema version 6, SwiftUI controls, camera pairing, Network-framework TLS, and generation-based import are implemented in source. They have **not been compiled in Xcode or validated on the physical iPhone** in this Windows environment. Local Swift tests were added for migration/import behavior.
- This is an initial implementation, not a claim of full production parity. Automatic cross-platform retranscription, configurable staging/rollback retention, full clean-machine validation, and signed Windows distribution remain follow-up work. Saved transfer/rollback directories can use significant extra disk space.

No GitHub Actions have been run or created. Existing workflow changes only account for the `ios/` directory move. See [repository rules](../AGENTS.md) before any push or hosted verification.

See [the architecture plan](../docs/WINDOWS_AND_SYNC_PLAN.md) and [wire protocol](../docs/sync/PROTOCOL.md) for the intended implementation and interoperability contract. Dependency notices are in [licenses](./licenses/).
