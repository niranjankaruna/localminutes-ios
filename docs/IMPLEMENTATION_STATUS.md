# Windows and local sync implementation status

Updated 30 October 2026. All work remains on `main`; no push or GitHub Actions execution has occurred.

## Implemented

- Existing application code, assets, tests and build helpers moved under [ios](../ios/), with no missing tracked source files. Existing workflow definitions retain their root location and use the corrected working directories.
- Native [.NET 10/WPF Windows application](../windows/src/LocalMinutes.Desktop/) following the desktop Figcraft structure, with local SQLite, persistent device and process IDs, meeting history/search, notes, original audio playback, generated content edits/citations, export/import, model downloads and microphone recording.
- Bundled llama.cpp `b11900` summaries/Q&A with full-input token counting and validated citation membership; sherpa-onnx `2.0.1` / Parakeet v3 speech inference. NVIDIA CUDA 13.4 and CPU distributions are supported. The [Windows model catalog](../windows/src/LocalMinutes.Core/Resources/SummaryCatalog.json) can be expanded independently of iOS.
- Sender-wins logical exchange, no propagated deletions or model transfers, TLS pairing and resumed file transfers. [Protocol details](./sync/PROTOCOL.md) describe the actual PC-listener/foreground-phone implementation.
- Bonjour/DNS-SD advertisement on Windows and paired-PC discovery on iPhone. Queued PC sends persist across Windows restarts, remain bound to the selected phone and can be cancelled.
- iPhone Sync controls, camera/code pairing, Keychain trust, Network-framework TLS client, version-6 persistence additions and generation-based library merge, implemented in source.
- Self-contained portable packaging with app-local Visual C++ runtime files, notices, SHA-256 receipt and package/dependency audits.

## Verified locally

| Check | Result |
| --- | --- |
| Windows build | Passed with warnings treated as errors |
| Windows automated tests | 26 passed, including real loopback TLS, interruption/resume, persistent queued sends/cancellation, both data directions and sender-wins/no-delete behavior |
| Windows discovery | Actual multicast DNS-SD query found the advertised instance |
| Existing iOS JavaScript helpers | 127 passed after source relocation |
| Actual llama.cpp CPU inference | Synthetic summary and grounded Q&A passed using the pinned Qwen 2.5 0.5B model |
| Actual llama.cpp CUDA inference | The same synthetic flow passed on NVIDIA RTX 5070 Ti, driver 617.42 / CUDA 13.4 |
| Actual Parakeet inference | Correctly transcribed a synthetic 16 kHz mono speech WAV; no microphone recording was performed for this test |
| WPF visual verification | Light, dark and 1280x800 window layouts rendered and inspected |
| Packaged EXE self-check | Loaded its own .NET 10.0.14 runtime, WPF layout and bundled native engines successfully |
| Package audit | No model/meeting data; required native dependencies and notices present |

## Not yet verified or completed

Native Swift compilation, the added Swift tests and physical iPhone 17 Pro/iOS 27.2 interoperability require Mac/Xcode/signing access. The Windows environment cannot establish those results. No GitHub-hosted verification has been substituted.

Cross-platform retranscription/versioning, configurable transfer/rollback retention and a receipt ledger surviving manual backup rollback remain follow-up work. This first implementation uses a QR/address pairing flow and requires the Sync screen to stay open on iPhone. The phone-side Bonjour discovery code still needs native validation alongside the rest of the iOS integration. See the [Windows usage and limitation notes](../windows/README.md).

The portable build is unsigned and has not been qualified on a completely clean Windows installation. The native-import audit and real EXE/inference checks provide useful evidence, but are not a replacement for that final deployment test.
