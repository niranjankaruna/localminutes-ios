# Windows and local sync implementation status

Updated 30 October 2026. Work remains on main. No GitHub Actions were started by this implementation.

## Current Windows implementation

Windows is a Python application with a thin PySide6 desktop window. It replaces the earlier .NET/WPF implementation. The distribution is one CUDA executable, with models, meetings, settings and runtime extraction under %APPDATA%/LocalMinutes.

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
| Actual Python CUDA inference | Synthetic summary and grounded Q&A passed on RTX 5070 Ti |
| Actual Python speech inference | Parakeet correctly recognized the synthetic WAV |
| UI visual review | Light/dark meeting layouts, recording, sync, settings and smaller window rendered |
| Packaged Python app | Started with its bundled interpreter; copied single EXE also passed actual CUDA summary/Q&A and Parakeet inference |
| Single-EXE audit | Bundled Python/UI/CUDA checked; no model weights, meeting data or retired .NET application |
| Existing iOS JavaScript helpers | 127 passed after source relocation; unchanged by the Python rewrite |

The earlier portable profile was copied into %APPDATA%/LocalMinutes and verified byte-for-byte, including protected pairing compatibility. The old .NET source, its build scripts, CPU runtime and timestamped release folders/ZIPs were removed. The retained release output is LocalMinutes-CUDA.exe.

## Remaining validation and follow-up

Native Swift compilation, the added Swift tests and physical iPhone 17 Pro/iOS 27.2 interoperability require Mac/Xcode/signing access. Those results have not been established on this Windows machine.

Automatic cross-platform retranscription/versioning, configurable transfer/rollback retention, a receipt ledger surviving manual backup rollback, clean-machine qualification and signed Windows distribution remain follow-up work. Keep the Sync screen open on iPhone for transfers.

See [Windows usage and build instructions](../windows/README.md).
