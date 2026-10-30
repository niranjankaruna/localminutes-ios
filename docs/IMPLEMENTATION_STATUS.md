# Windows and local sync implementation status

Updated 30 October 2026. Work remains on main. No GitHub Actions were started.

## Windows 0.3.0

Windows remains a Python application with a PySide6 desktop wrapper and one portable CUDA EXE. Models, meetings, configuration and runtime extraction use %APPDATA%/LocalMinutes.

The model selector has four groups with eight pinned variants:

| Group | Qwen | Gemma | Placement |
| --- | --- | --- | --- |
| Current larger | 3.8 27B Q8_0 | 4 31B Q8_0 | GPU + CPU/system RAM permitted |
| Large | 3.8 27B UD-Q3_K_XL | 4 31B Q3_K_S | GPU only |
| Medium | 3.5 9B Q8_0 | 4 12B Q6_K | GPU only |
| Small | 3.5 4B Q8_0 | 4 E2B QAT Q4_0 | GPU only |

Thinking is enabled. The fixed 32K context, 4K output and one-hour generation limits have been removed. GPU-only inference requires every model tensor and KV cache allocation on CUDA, verifies zero host model/KV allocation, then disables runtime refitting. Only the current Q8 group permits CPU layer offloading. The model's native context and available memory remain physical constraints; complete input is checked and never silently truncated. Thinking and final JSON are separated, and only validated final documents are saved.

Parakeet uses its 2.55 GB floating-point CUDA pack and a private stdio worker. Its three neural graphs execute on CUDA. The pinned ONNX export requires CPU shape/index bookkeeping: the worker audits every CPU-assigned node against the [verified metadata-node policy](../windows/localminutes/resources/SpeechCudaPlacement.json), and refuses neural CPU fallback. Native speech failures do not crash the UI. The prior microphone-rate fix remains: supported device rates are converted to 16 kHz mono before saving and transcription.

The verified CUDA speech pack has also been copied into the user's application model directory. Existing meetings, settings, pairing and older model files were preserved.

## Validation

- **49 regression tests passed**, covering storage/sync, microphone conversion and recovery, four-group selection, context budgeting, GPU-only placement refusal, thinking/final-output separation and CUDA speech safeguards.
- All six GPU-only variants passed actual thinking-enabled summaries and source-backed answers on the RTX 5070 Ti, with zero estimated host model/KV allocation.
- Qwen 4B/9B and Gemma 12B allocated their full 262,144-token context; Gemma E2B allocated 131,072. The large GPU-only Qwen allocated about 65K and Gemma about 29K in the tested memory conditions. These are observed capacities, not fixed application caps or guarantees under other GPU workloads.
- Both retained Q8 models ran with their full 262,144-token context and permitted CPU/RAM offloading.
- Parakeet correctly transcribed synthetic speech on CUDA. Auditing confirmed **3 CUDA graphs, 1,538 CUDA nodes and 482 CPU metadata nodes**, with no neural CPU fallback.
- The single EXE passed its isolated startup, full-GPU Qwen thinking/summary/Q&A, CUDA speech-worker and resampled-speech checks. Its bundled model catalog contains all eight variants.
- Light/dark application previews and the four-group settings layout were rendered. No live microphone audio was recorded for validation.
- The release archive audit verifies bundled Python, UI, both CUDA runtime sets, cuDNN, speech provider, memory planner and dependency notices. It excludes model weights, personal meeting data, server executables and retired .NET code.

The release is [LocalMinutes-CUDA.exe](../windows/dist/LocalMinutes-CUDA.exe), **2,353,482,338 bytes** (about 2.35 GB), SHA-256 `cb7219ee95e960cd6b4fa9d59443f7f9ad0bf47ebc015d6a250db7ea7f979d21`. It is larger because it now bundles the CUDA/cuDNN speech runtime as well as the llama.cpp CUDA runtime. The distribution directory contains one EXE.

The currently running older app holds its renamed backup open in the build cache. The verified new release was promoted successfully; old-build cleanup is deferred until that process exits. The build script now treats this cleanup condition as a warning after successful promotion.

## iOS and sync

The iOS source, assets, tests and helpers remain under [ios](../ios/). This Windows update does not change the iOS catalog or shared protocol.

The [sync protocol](./sync/PROTOCOL.md) uses sender-wins updates, retains receiver-only records, and excludes deletion propagation and model binaries. Transfers verify hashes, resume staged files and preserve original audio/transcript identities. Queued PC sends survive restart and remain bound to their recipient.

Native Swift compilation, the added Swift tests and a physical iPhone 17 Pro/iOS 27.2 round trip still require Mac/Xcode/signing access. The earlier 127 JavaScript helper tests do not establish native iOS validation.

Automatic cross-platform retranscription/versioning, retention cleanup, a receipt ledger surviving manual rollback, clean-machine qualification and signing remain follow-up work.

See [Windows usage and build instructions](../windows/README.md).
