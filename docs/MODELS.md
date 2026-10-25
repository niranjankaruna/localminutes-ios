# Models

The model upgrades on `codex/parakeet-downloads` are being verified. The previously
delivered build 6 still has the original v2-only adapter and expanded file list.
Consult `STATE.json` for the exact tested source and latest delivered package.

Open **Models**, choose **Speech** or **Summary**, paste a public Hugging Face
repository or URL, and select **Look up repository**. Review the full model card,
compatibility explanation, selected files, disk size, and resource estimates.
Unknown values remain unknown; estimates do not establish phone speed or memory.

Use **Download selected model** or **Import selected model from Files**. Required
files, sizes, and SHA-256 are checked before installation becomes available.
Choose **Equip** after installation: one speech model and one summary model can
be equipped independently, while alternatives remain installed. Stop active work
before changing an in-use model. **Remove** deletes model files after confirmation
without deleting meetings. Setup needs connectivity; inference uses local engines.

## Supported formats

| Purpose | Reviewed format | Engine |
| --- | --- | --- |
| Streaming speech | Matching Zipformer ONNX encoder, decoder, joiner, and tokens | CPU sherpa-onnx 1.13.8 |
| Chunked speech | Compatible Whisper GGML `ggml-*.bin` | CPU whisper.cpp 1.7.5 |
| Chunked speech | Validated Parakeet TDT v2/v3 Core ML model pack | CPU Core ML and Swift TDT decoder |
| Summaries and questions | Supported Qwen2/Phi3-family GGUF and chat template | CPU llama.cpp b5046 |
| Summaries and questions | Apple Intelligence system model, when available | Apple's on-device FoundationModels framework |

Repository lookup accepts public publishers; an arbitrary file is not necessarily
compatible. Original PyTorch/Safetensors, NeMo, MLX, split GGUFs, and unrelated
ONNX/Core ML assets require supported conversions or additional adapters. English
is the baseline. The owner chooses models and assesses their output manually;
Phi-3 is not required. Historical candidate tests do not endorse a model for the phone.

## Reviewed Parakeet import

The source repository `nvidia/parakeet-tdt-0.6b-v2` links to the reviewed conversion
`FluidInference/parakeet-tdt-0.6b-v2-coreml`, revision
`ee09c569f73759e6d44c9bd16766f477b2b36d39`. The supported subset contains
**21 files, 464,413,247 bytes**. Select that compatible set, download, then Equip.

For Files import, select a folder containing `Decoder.mlmodelc`, `Encoder.mlmodelc`,
`JointDecision.mlmodelc`, `Preprocessor.mlmodelc`, and `parakeet_vocab.json`, retaining
their nested files. One bundle or a `.nemo` file is insufficient.
Parakeet publishes completed chunks of roughly five seconds plus decoding time;
it does not provide frame-by-frame streaming. Current policy is CPU-only.
Actual phone throughput and locked operation remain unverified.

## Parakeet upgrades

The new adapter selects a decoder from the pack's `parakeetConfiguration`, rather
than from its Hugging Face publisher or model name. The complete legacy v2 set
remains compatible. **Browse Parakeet TDT v3** loads a bundled descriptor for
`FluidInference/parakeet-tdt-0.6b-v3-coreml` at immutable revision
`7dd20fe6b1797d35f5e3307e8b1732d9a178edfe`: 21 files, 483,105,645 bytes.
The v3 joint bundle is `JointDecisionv3.mlmodelc`; its vocabulary and decoder
contract differ from v2. A Core ML filename extension alone does not establish
compatibility.

**Open a model pack…** imports a small JSON descriptor, not weights. Compatible
future conversions can declare their own repository, exact revision, required
bundles, sizes, SHA-256 values and license without a new publisher allowlist.
All weight files still undergo verification and atomic installation. Declared
metadata is not a successful inference result. Unknown decoder contracts require
an adapter update; a future v4 with changed inputs/decoding cannot be assumed to
work automatically. Raw NVIDIA NeMo/Safetensors and speech GGUF weights do not
run through this Core ML adapter.

An installed `.mlmodelc` is a directory containing model metadata and weights.
The installed list shows one model row; **Model details** reveals all bundle
files, runtime and revision. Capture and replay retain the exact selected pack,
so changing today's selection does not replace a saved meeting's original pin.

## Apple Intelligence summaries

**Summary → Apple Intelligence → Equip** selects the system's on-device language
model for summaries and meeting questions. The list reports actual framework
availability: OS support, eligible hardware, enabled Apple Intelligence and model
readiness. iOS manages that model's installation; the app does not offer a
downloaded weight file or pretend it knows an exact weight checksum. The choice
persists independently of the speech model and can switch back to an installed
GGUF while idle.

Generated documents record `apple-system-ios-MAJOR.MINOR.PATCH` as provider/OS
provenance, not a pinned model revision. Apple may change its system model without
an OS version change. To avoid reusing maps from an unknown model version, Apple
summaries do not use the downloaded-model resume cache. They still use the same
evidence validation, local database, cancellation and recording/inference gate.
There is no cloud fallback. Real Apple inference on the owner's phone is pending.

The pinned Xcode 26.2 SDK lacks Apple's newer token-count API. This build budgets
Apple input conservatively by UTF-8 size and reserves response space; that is not
a measured native token count. A framework context-limit error is recoverable.

## Download status

The screen reports percentage, transferred/total bytes, current file, file count,
observed speed, estimated remaining time and resumed bytes. Verification and
installation have separate stages; their screen does not keep a stale download
speed or ETA. Network and file operations use bounded chunks. The 512 MiB Darwin
regression is evidence about transfer memory, not a phone termination diagnosis
or model inference memory measurement. See the [T26 record](evidence/T26_MODEL_ADAPTERS_TRANSFERS.md).

See [dependency pins and licenses](DEPENDENCIES.md), the [current build guide](MVP4_GUIDE.md),
and [phone checklist](MVP4_DEVICE_CHECKLIST.md). Keep downloaded weights out of Git.
