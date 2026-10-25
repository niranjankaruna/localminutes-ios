# Models

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
| Chunked speech | Reviewed Parakeet v2 Core ML set | CPU Core ML and Swift TDT decoder |
| Summaries and questions | Supported Qwen2/Phi3-family GGUF and chat template | CPU llama.cpp b5046 |

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

See [dependency pins and licenses](DEPENDENCIES.md), the [current build guide](MVP4_GUIDE.md),
and [phone checklist](MVP4_DEVICE_CHECKLIST.md). Keep downloaded weights out of Git.
