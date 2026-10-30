# Windows and local sync implementation status

Updated 30 October 2026. Work remains on main. No GitHub Actions were started by this implementation.

## Current Windows implementation

Windows is a Python application with a thin PySide6 desktop window. It replaces the earlier .NET/WPF implementation. The distribution is one CUDA executable, with models, meetings, settings and runtime extraction under %APPDATA%/LocalMinutes.

Version 0.2.1 replaces the small Windows summary catalog with two quality-first Q8 choices: Qwen 3.8 27B and Gemma 4 31B. Both use automatic CUDA/system-RAM placement for the user's 16 GB GPU and 64 GB RAM. Settings exposes parameter counts, quantization, download sizes and runtime presets. The application caps context at 32K tokens including output, and preserves complete-prompt validation. The iOS catalog is unchanged.

The reported `Invalid sample rate [PaErrorCode -9997]` was reproduced: the Realtek input supports 44.1/48 kHz and the Bluetooth headset supports 8 kHz, while the old recorder forced 16 kHz. Recording now negotiates a supported hardware format and streams through SoXR to the shared 16 kHz mono format. Parakeet files passed checksum verification and actual synthetic speech recognition. Parakeet continues to run on CPU; summary/answer inference uses CUDA with CPU layers where necessary.

- [Python services and UI](../windows/localminutes/) implement SQLite meeting storage, notes, generated documents, microphone recording, original CAF playback, model downloads, summaries/Q&A, library import/export and local sync.
- [build-cuda.ps1](../windows/scripts/build-cuda.ps1) prepares pinned dependencies, packages the application as one EXE, checks its contents and runs an isolated self-check. Rebuilds replace one output instead of creating additional release folders and ZIPs.
- Bundled llama.cpp b11900 provides CUDA summaries/Q&A. Parakeet v3 / sherpa-onnx 2.0.1 provides speech recognition. The [Windows model catalog](../windows/localminutes/resources/SummaryCatalog.json) remains independent of iOS.
- The Apple-inspired layout uses a sidebar, a meeting list, a reading workspace, explicit pressed/focus feedback, and light/dark appearances.

## Sync and iOS

The iOS source, assets, tests and build helpers remain under [ios](../ios/). Sync controls, QR/code pairing, Keychain trust, TLS transport, schema-version-6 additions and generation-based merge are implemented in source.

The [shared protocol](./sync/PROTOCOL.md) uses sender-wins updates, retains receiver-only records, and excludes deletion propagation and model binaries. Transfers verify hashes, resume interrupted files and preserve immutable source/audio identities. Queued PC sends survive restart and remain bound to their original recipient. Windows advertises Bonjour; the phone verifies its paired TLS identity after discovery.

## Validation

| Check | Result |
| --- | --- |
| Python storage and real TLS tests | 22 passed, including device-disconnection cleanup and prompt TLS shutdown |
| Python UI interaction test | Passed note-draft persistence across selection/navigation and theme changes |
| Microphone format regression tests | 7 passed: supported format negotiation, 44.1/48/8/16 kHz conversion, anti-alias filtering, stereo mixing, tail draining and sample-aligned transcript ranges |
| Model preset regression tests | 5 passed: two large models only, no silent selection replacement, pinned files, prompt formatting, context/output budgeting and native CUDA/CPU argument application |
| Actual Python CUDA inference | Qwen 3.8 27B Q8_0 and Gemma 4 31B Q8_0 both passed synthetic summaries, grounded Q&A and 32K context allocation on RTX 5070 Ti with system-RAM offload |
| Actual Python speech inference | Parakeet correctly recognized the synthetic WAV, including simulated 44.1 kHz and 8 kHz microphone conversion |
| UI visual review | Light/dark meeting layouts, recording, sync, settings and smaller window rendered |
| Packaged Python app | Started with its bundled interpreter; copied single EXE also passed actual CUDA summary/Q&A and Parakeet inference |
| Single-EXE audit | Bundled Python/UI/CUDA checked; no model weights, meeting data or retired .NET application |
| Existing iOS JavaScript helpers | 127 passed after source relocation; unchanged by the Python rewrite |

The earlier portable profile was copied into %APPDATA%/LocalMinutes and verified byte-for-byte, including protected pairing compatibility. The old .NET source, its build scripts, CPU runtime and timestamped release folders/ZIPs were removed. The retained release output is LocalMinutes-CUDA.exe.

The current regression suite totals **35 passing tests**. The rebuilt 0.2.1 EXE passes its standalone Python/UI/CUDA startup check, Qwen 3.8 27B summary/Q&A, and actual Parakeet transcription after simulated 48 kHz microphone conversion. Hardware-format probes accept both user input devices without recording live microphone audio. No live microphone recording was made during validation.

At the full 32K allocation check, the runtime placed **31/66 Qwen layers** and **22/61 Gemma layers** on the GPU, keeping the remaining layers in system RAM. Placement varies with available VRAM and actual request length. The synthetic summary-plus-answer runs took approximately 140 seconds for Qwen and 183 seconds for Gemma, including checksum verification and repeated model loading; these are functional-test timings, not comparative quality benchmarks or long-meeting performance promises.

The release is `windows/dist/LocalMinutes-CUDA.exe`, **648,237,539 bytes**, SHA-256 `20d3d63b2c7ad32211fdd6ea01176c6a5f0486d35db1fe9f8a29d72b342d0c70`. Model weights remain separate downloads. Only that EXE is present in the release directory.

## Remaining validation and follow-up

Native Swift compilation, the added Swift tests and physical iPhone 17 Pro/iOS 27.2 interoperability require Mac/Xcode/signing access. Those results have not been established on this Windows machine.

Automatic cross-platform retranscription/versioning, configurable transfer/rollback retention, a receipt ledger surviving manual backup rollback, clean-machine qualification and signed Windows distribution remain follow-up work. Keep the Sync screen open on iPhone for transfers.

See [Windows usage and build instructions](../windows/README.md).
