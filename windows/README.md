# LocalMinutes for Windows

A Python application with a thin PySide6 desktop window, packaged as one CUDA executable. It records the microphone, transcribes locally with Parakeet, generates summaries and answers with llama.cpp, and copies meeting data directly between Windows and iPhone.

## Run the app

Use **LocalMinutes-CUDA.exe**. No ZIP extraction, Python installation, .NET installation or inference-engine installation is needed. NVIDIA inference requires a compatible driver; the pinned CUDA 13.4 runtime was tested on the RTX 5070 Ti with driver 617.42.

The EXE includes Python, the desktop UI, speech libraries, llama.cpp, CUDA libraries and dependency notices. Download model weights from Settings. Keeping weights separate lets you change models without replacing the app.

All writable application state lives under **%APPDATA%/LocalMinutes**:

| Directory | Contents |
| --- | --- |
| library | SQLite meeting metadata, notes, generated documents and original audio |
| models | Downloaded speech and summary models |
| identity | Persistent device ID and Windows-protected pairing credentials |
| runtime | Automatically extracted runtime files and temporary work |
| sync-incoming, sync-outgoing | Resumable, verified transfer snapshots |
| rollback, imports, deletions | Library recovery and maintenance state |

Settings and model selections are small JSON files in the same application directory. Each profile keeps its device UUID; each process receives a new instance UUID. A second process cannot write to the same profile. Replacing the EXE preserves meetings and models. Copy the data directory separately when moving your library to another machine; Windows-protected pairing must be renewed.

The [PyInstaller bootloader](https://pyinstaller.org/en/stable/operating-mode.html) unpacks native dependencies automatically beneath the app's runtime directory at launch and removes that run's extraction directory on normal exit. Initial startup is slower than a folder-based application. Crash leftovers and transfer/rollback retention are not automatically pruned yet.

## First use

1. In **Settings → Models**, download the **Parakeet v3** speech model. Under **Summaries & answers**, choose a model size and model, download it, then select **Use model**. The page shows the model in use separately from the model you are browsing. Downloaded alternatives are labeled in the model list; sampling and context information is under **Show technical details**.
2. In Record, select your microphone and start recording. Stop before generating a summary, asking a question or syncing.
3. Meetings provides Summary, Transcript, Notes and Ask views. Notes save automatically. Generated edits remain separate from original JSON. Sources verifies citations against the transcript; double-click a source to play its original audio.
4. **Settings → Library & storage** imports iPhone .localminutesbackup or .lmtransfer directory packages. Export includes saved meeting data and original audio, excluding models and credentials. This tab also opens the application data folder. **Settings → Appearance** changes the light/dark appearance and provides dependency licenses.

Model downloads show progress and cancellation within Settings. After downloading a summary model, select **Use model** to activate it. Removing a model asks for confirmation and preserves your meetings. Model changes and library transfers are disabled while recording or another operation is running.

The window follows the [Figcraft layout](./Design/LocalMinutes-Windows-Plan.figcraft), with Apple-inspired spacing, system typography, clear focus/pressed states, and light/dark appearances. Standard Windows window controls remain available.

Original audio is 16 kHz mono signed 16-bit PCM CAF in segments of up to 60 seconds. Microphones are opened at a supported rate and channel count; a streaming SoXR converter mixes stereo to mono and converts 44.1/48 kHz microphones or 8 kHz headsets to 16 kHz. This fixes `Invalid sample rate [PaErrorCode -9997]` on devices that cannot capture directly at 16 kHz. The converter flushes its final samples before the recording finishes. Known system-audio loopback devices are excluded from the microphone list.

NVIDIA Parakeet v3 runs its encoder, decoder and joiner neural graphs on **CUDA** in a private worker process. Download the new **2.55 GB floating-point CUDA pack** in Settings; the former INT8 CPU pack is not used. CUDA startup checks refuse neural CPU fallback. ONNX retains audited shape/index bookkeeping on CPU; all neural layers run on the GPU. Audio input, resampling, tokenization and UI coordination also use the CPU. Transcription uses five-second windows. Following a crash, validated closed segments remain playable and the meeting is marked interrupted; unfinished tails are retained. Automatic cross-platform transcription replay/versioning is not implemented.

## Wi-Fi sync

The updated iPhone source must first be built and installed. Existing releases without this protocol cannot sync.

1. Open Sync on Windows and choose **Pair an iPhone**. Select the PC's actual local address.
2. On iPhone, open Sync and scan the invitation or paste the connection code. Invitations expire after five minutes.
3. Keep the iPhone Sync screen open and the phone unlocked. Windows uses TCP 47835 and Bonjour discovery on UDP 5353. Allow the app through Windows Firewall on the Private profile if prompted.
4. Press Sync on iPhone to send its library to Windows. Press **Sync to iPhone** on Windows to send the PC library.

The sender replaces matching editable versions even when the receiver timestamp is newer. Receiver-only records remain. Deletions and models do not propagate; a deleted meeting can return when another device sends it back. Original audio/transcript identity conflicts are rejected.

Transfers verify hashes, resume staged files, skip identical recordings and acknowledge committed imports. Queued PC sends survive restart and stay bound to their recipient. Cancel PC send cannot undo data already committed by the phone.

There is no hosted service or account system. Windows owns the TLS listener; a foreground phone connection carries either direction. Trust uses the QR certificate and a random secret. Bonjour supplies routing hints without replacing authentication. See the [protocol](../docs/sync/PROTOCOL.md).

## Build the single CUDA EXE

On Windows 11 x64, install Python 3.12 or newer. Python **3.14.7** is the verified interpreter. CUDA speech wheels are pinned for Python 3.12–3.15. From the repository root:

    powershell -NoProfile -ExecutionPolicy Bypass -File windows/scripts/build-cuda.ps1

For a specific interpreter, append -PythonPath with its full path on the first build. The script creates an isolated environment, installs pinned dependencies, prepares verified CUDA/app-local VC++ libraries, collects licenses, packages the application, audits its contents, and runs an isolated packaged-EXE self-check.

The output is always **windows/dist/LocalMinutes-CUDA.exe**. Rebuilding replaces that one output only after validation succeeds. No CPU edition, ZIP or timestamped release directory is created. The script prints SHA-256. The VC++ installer is never executed.

The repository includes the Python source and [PyInstaller specification](./LocalMinutes.spec), allowing rebuilding with modified compatible dependencies.

After preparing the environment, run from source or execute the tests:

    powershell -File windows/scripts/run-python.ps1 launch.py
    powershell -File windows/scripts/run-python.ps1 -m pytest

TLS tests use Windows DPAPI; restricted execution sandboxes can prevent access to Windows cryptographic keys. Tests use synthetic libraries and never record the microphone.

## Windows model catalog

The [Windows catalog](./localminutes/resources/SummaryCatalog.json) contains four selectable groups, with separate Qwen and Gemma choices:

| Group | Qwen | Gemma | Execution |
| --- | --- | --- | --- |
| Current larger models | Qwen 3.8 27B Q8_0 · 29.05 GB | Gemma 4 31B Q8_0 · 32.64 GB | CUDA plus CPU/system-RAM offload allowed |
| Large | Qwen 3.8 27B UD-Q3_K_XL · 13.15 GB | Gemma 4 31B Q3_K_S · 13.21 GB | GPU only |
| Medium | Qwen 3.5 9B Q8_0 · 9.53 GB | Gemma 4 12B Q6_K · 9.79 GB | GPU only |
| Small | Qwen 3.5 4B Q8_0 · 4.48 GB | Gemma 4 E2B QAT Q4_0 · 3.35 GB | GPU only |

The large GPU-only variants retain the larger parameter counts with lower weight precision. Medium models offer higher precision and more room for context. These are tradeoffs, not a universal quality ranking. GGUF works with the bundled NVIDIA CUDA engine and is not Apple-specific. Existing downloaded files and model selections are preserved.

**Thinking is enabled. There is no fixed 32K application context cap, 4K output cap, thinking-token cap, or generation timeout.** A grammar allows unrestricted thinking tokens until the model's reasoning-end marker, then structures the final JSON. Only the verified final answer is saved; reasoning is not mistaken for meeting content. Cancellation remains available.

The native memory planner starts from the model's supported context (262,144 tokens, or 131,072 for Gemma E2B). For GPU-only models it allocates the largest context that fits current VRAM with every model tensor and the KV cache on CUDA. It verifies zero host model/KV allocation, then runs with fitting disabled so placement cannot change silently. There is no fixed VRAM reserve. The original Q8 group retains the full native context and may place layers in CPU/system RAM.

Physical memory and the model's architecture still impose limits. If the complete prompt cannot fit, the app reports an error without truncating the meeting or falling back to CPU. Generation stops at the model's end token or when the available context is full; incomplete results are rejected. Context capacity includes input, thinking and the final answer, and varies with other GPU applications.

All variants use Flash Attention, Q8 KV cache, batch 2048 / microbatch 512 and eight host coordination threads. Thinking sampling uses temperature 1.0, top-p 0.95, min-p 0 and repeat penalty 1. Qwen uses top-k 20 / presence penalty 1.5; Gemma uses top-k 64 / presence penalty 0. Settings shows these parameters and the selected execution policy. GPU-only is not a promise of zero CPU usage for loading, tokenization, I/O or UI work.

Publisher references: [Qwen 3.8](https://huggingface.co/Qwen/Qwen3.8-27B), [Qwen 3.5](https://huggingface.co/Qwen/Qwen3.5-9B), [Gemma 4](https://huggingface.co/google/gemma-4-31B-it). Downloads pin exact GGUF revisions, filenames, sizes, SHA-256 and licenses. The iOS catalog is unchanged.

## Validation and limits

Python storage and real TLS tests cover sender-wins/no-delete exchange, original CAF media, import/deletion recovery, interrupted uploads, both data directions and persistent queued sends. Actual Qwen CUDA summaries/Q&A and Parakeet transcription passed with synthetic fixtures. Light and dark layouts were rendered and inspected.

The iOS sync source still needs Xcode compilation and a physical iPhone/Windows round trip. Clean-machine qualification, signed distribution, automatic retention and a receipt ledger surviving manual backup rollback remain follow-up work.

See [implementation status](../docs/IMPLEMENTATION_STATUS.md) and [dependency notices](./licenses/NOTICE.txt). GitHub Actions requires explicit authorization under the [repository rules](../AGENTS.md).
