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

1. In Settings, download **Parakeet v3**, then download **Qwen 3.8 27B Q8_0** (recommended for quality) or **Gemma 4 31B Q8_0**, and select **Use model**.
2. In Record, select your microphone and start recording. Stop before generating a summary, asking a question or syncing.
3. Meetings provides Summary, Transcript, Notes and Ask views. Notes save automatically. Generated edits remain separate from original JSON. Sources verifies citations against the transcript; double-click a source to play its original audio.
4. Settings imports iPhone .localminutesbackup or .lmtransfer directory packages. Export includes saved meeting data and original audio, excluding models and credentials.

The window follows the [Figcraft layout](./Design/LocalMinutes-Windows-Plan.figcraft), with Apple-inspired spacing, system typography, clear focus/pressed states, and light/dark appearances. Standard Windows window controls remain available.

Original audio is 16 kHz mono signed 16-bit PCM CAF in segments of up to 60 seconds. Microphones are opened at a supported rate and channel count; a streaming SoXR converter mixes stereo to mono and converts 44.1/48 kHz microphones or 8 kHz headsets to 16 kHz. This fixes `Invalid sample rate [PaErrorCode -9997]` on devices that cannot capture directly at 16 kHz. The converter flushes its final samples before the recording finishes. Known system-audio loopback devices are excluded from the microphone list.

NVIDIA Parakeet v3 is the speech model; the bundled sherpa-onnx engine runs it on the **CPU**, independently of CUDA summary generation. Transcription uses five-second windows. Following a crash, validated closed segments remain playable and the meeting is marked interrupted; unfinished tails are retained. Automatic cross-platform transcription replay/versioning is not implemented.

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

On Windows 11 x64, install Python 3.12 or newer. Python **3.14.7** is the verified interpreter. From the repository root:

    powershell -NoProfile -ExecutionPolicy Bypass -File windows/scripts/build-cuda.ps1

For a specific interpreter, append -PythonPath with its full path on the first build. The script creates an isolated environment, installs pinned dependencies, prepares verified CUDA/app-local VC++ libraries, collects licenses, packages the application, audits its contents, and runs an isolated packaged-EXE self-check.

The output is always **windows/dist/LocalMinutes-CUDA.exe**. Rebuilding replaces that one output only after validation succeeds. No CPU edition, ZIP or timestamped release directory is created. The script prints SHA-256. The VC++ installer is never executed.

The repository includes the Python source and [PyInstaller specification](./LocalMinutes.spec), allowing rebuilding with modified compatible dependencies.

After preparing the environment, run from source or execute the tests:

    powershell -File windows/scripts/run-python.ps1 launch.py
    powershell -File windows/scripts/run-python.ps1 -m pytest

TLS tests use Windows DPAPI; restricted execution sandboxes can prevent access to Windows cryptographic keys. Tests use synthetic libraries and never record the microphone.

## Windows model catalog

The [Windows catalog](./localminutes/resources/SummaryCatalog.json) is independent of iOS. It now contains only large summary/answer models, chosen for quality on the user's **RTX 5070 Ti 16 GB + 64 GB system RAM**. Smaller summary models have been removed from the list. Existing downloaded files are not silently deleted, and a removed selection requires explicitly choosing one of the new models. Parakeet remains separate because it performs speech recognition.

| Model | Parameters | Quantization | Download | Purpose |
| --- | --- | --- | --- | --- |
| [Qwen 3.8 27B](https://huggingface.co/Qwen/Qwen3.8-27B) | 27.3 billion in the GGUF | Q8_0 | 29.05 GB | Recommended quality-first preset |
| [Gemma 4 31B](https://huggingface.co/google/gemma-4-31B-it) | 30.7 billion | Q8_0 | 32.64 GB | Large alternative for summaries and answers |

The GGUF weights work through the bundled llama.cpp **CUDA** backend on NVIDIA. They are not Apple-specific. Neither Q8 model fits completely into 16 GB VRAM. Automatic layer placement uses available GPU memory and keeps the remaining layers in system RAM; expect slower generation and additional model-loading time. Only one model is loaded per operation. These are curated choices, not a claim that one model wins every task.

Both presets use a **32,768-token application context cap**, including up to **4,096 output tokens**, Flash Attention, Q8 key/value cache, automatic GPU placement with a 1,536 MiB GPU reserve, batch 512 / microbatch 128, and eight CPU threads. Sampling uses temperature 0.2, min-p 0, repeat penalty 1 and presence penalty 0; Qwen uses top-k 20 / top-p 0.8, while Gemma uses top-k 64 / top-p 0.95. These conservative sampling settings are application choices for evidence-backed meeting JSON, not the publishers' general-chat defaults. Thinking is disabled with each publisher's direct-answer prompt format. Settings displays the selected preset; changing the model applies it automatically when the model is equipped.

The publishers advertise larger contexts; the application deliberately caps them for this hardware. The complete prompt is tokenized before inference. Input, reserved output and a margin must fit the application cap; oversized requests fail without truncation. The GPU reserve is a runtime fitting target, not a guarantee against other applications changing available memory. Runtime failures do not save incomplete documents.

Downloads pin the publisher repository revision, filename, byte count, SHA-256 and license. Qwen uses the [Unsloth Qwen 3.8 GGUF release](https://huggingface.co/unsloth/Qwen3.8-27B-GGUF/tree/4ca720788d1e01f1bff70c033e0d0028fd02e502); Gemma uses the [Unsloth Gemma 4 GGUF release](https://huggingface.co/unsloth/gemma-4-31B-it-GGUF/tree/c1ac76e99d5513b141e8adde7288b85c3f9c32ec). New prompt formats need an adapter in [intelligence.py](./localminutes/intelligence.py).

## Validation and limits

Python storage and real TLS tests cover sender-wins/no-delete exchange, original CAF media, import/deletion recovery, interrupted uploads, both data directions and persistent queued sends. Actual Qwen CUDA summaries/Q&A and Parakeet transcription passed with synthetic fixtures. Light and dark layouts were rendered and inspected.

The iOS sync source still needs Xcode compilation and a physical iPhone/Windows round trip. Clean-machine qualification, signed distribution, automatic retention and a receipt ledger surviving manual backup rollback remain follow-up work.

See [implementation status](../docs/IMPLEMENTATION_STATUS.md) and [dependency notices](./licenses/NOTICE.txt). GitHub Actions requires explicit authorization under the [repository rules](../AGENTS.md).
