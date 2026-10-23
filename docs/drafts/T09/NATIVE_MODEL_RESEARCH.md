# Offline speech dependency research —23 October2026

Read-only preparation while T06 native tests run. T09/T10 remain unimplemented;
no manifest, native binary/weight hash verification, model load, inference, performance
or device result is claimed. Production still rejects missing real ASR.

## Model candidate

[Maintainer model](https://huggingface.co/csukuangfj/sherpa-onnx-streaming-zipformer-en-2023-06-26)
API reports immutable revision672fbf1b30579d6585301139bb363f42a0ad4a24.
Its pinned README identifies Apache2.0 and the upstream
[training model](https://huggingface.co/Zengwei/icefall-asr-librispeech-streaming-zipformer-2023-05-17).
The following are maintainer-reported LFS sizes/digests, not locally verified
downloads. Candidate uses one matching chunk16/left128 int8 set:

| File | Bytes | Reported SHA256 |
|---|---:|---|
| encoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx |71083163|563fde436d16cf7607cf408cd6b30909819d03162652ef389c2450ced3f45ac1|
| decoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx |1307236|98da299f471e38bb4e1a8df579b8cc9122d6039576a77e357b3c60f17dd83b02|
| joiner-epoch-99-avg-1-chunk-16-left-128.int8.onnx |259335|d944208d660d67c8d72cd2acaeac971fa5ceb8c80e76c1968148846fedd6e297|

tokens.txt was downloaded separately from that exact revision into ignored local
research storage:5048bytes, actual SHA256
49e3c2646595fd907228b3c6787069658f67b17377c60aeb8619c4551b2316fb.
This is token-file integrity evidence only; no weight/runtime/inference pass.
Include model
card/license/attribution in final installation metadata. Never mix left64/128
files or infer recognizer readiness from their presence. Existing test_wavs are
non-private literature speech, but exact fixture provenance/redistribution terms
must be documented before committing an evaluation fixture. No audio copied here.

## Runtime candidate, not a final dependency decision

Official tag[v1.13.8](https://github.com/k2-fsa/sherpa-onnx/tree/v1.13.8)
resolves via GitHub API to11afbd009a7f8c08f4bcf2fc1b265d0df4670fbf.
Its[Package.swift](https://github.com/k2-fsa/sherpa-onnx/blob/11afbd009a7f8c08f4bcf2fc1b265d0df4670fbf/Package.swift)
declares iOS15/macOS10.15, static SherpaOnnx products and exact
csukuangfj/onnxruntime-libs1.28.2. It reports these static binary hashes:

| Asset under official releases/download/xcframework | Reported package checksum |
|---|---|
| sherpa-onnx-v1.13.8-ios-static.xcframework.zip |6b8e769cb153343270fdccbe92e3b3db0d1c421d67fa0989ab01fdf5b2fcf2de|
| sherpa-onnx-v1.13.8-macos-static.xcframework.zip |93f7a064abe99e0d6185a88c5b36ce18c4bff35cd0d5e4e81f81151de8e3e7e5|

Do not resolve floating master/latest or execute downloaded code yet. Current
GitHub latest is v2.0.0, published today12:49:58UTC; its release API returned no
matching iOS/macOS XCFramework assets at observation. This is a changing upstream
release observation, not a compatibility verdict. Inspect pinned runtime/ONNX
licenses, headers, architecture slices, dependencies and actual downloaded bytes;
then prove actual CPU streaming output with licensed audio on the target build.
No GPU/ANE/background feasibility or two-hour endurance follows from this table.
