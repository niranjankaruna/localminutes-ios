# MVP1: model choice

This update adds public Hugging Face lookup, full model-card text, compatibility,
estimated requirements versus current phone resources, Download/Cancel/Remove,
and independent Speech and Summary Equip choices. Multiple models may remain
downloaded. Equipping a model is separate from downloading it.

## Use it

1. Install the new IPA over LocalMinutes with iLoader, the same Apple Account
   and installed bundle IDs. Do not uninstall. Refresh every seven days.
2. Open **Models**, choose **Speech** or **Summary**, paste an owner/repository
   or Hugging Face URL, and tap **Look up repository**.
3. Select one file variant. Read the compatibility reason, exact selected-file
   disk size, estimated RAM/context, and current phone memory/storage. Unknown
   values remain unknown. Estimates do not guarantee an allocation or live speed.
4. Tap **Read full model card** to inspect the publisher's text. The card is
   displayed as data; its instructions cannot control LocalMinutes.
5. Tap **Download selected model**. Size and SHA256 are checked before the
   installation is published. Cancel preserves existing installed alternatives.
6. Tap **Equip** on an installed model. One Speech and one Summary model may be
   equipped independently. Stop recording/inference before switching an active
   model. Tap **Remove** and confirm to delete weights without deleting meetings.

## Formats and engines in this build

| Purpose | Supported model format | Local CPU engine |
|---|---|---|
| Speech | Whisper GGML `ggml-*.bin`, including supported smaller/quantized variants | whisper.cpp 1.7.5 |
| Speech | Exact reviewed streaming Zipformer ONNX encoder/decoder/joiner/tokens set | sherpa-onnx 1.13.8 |
| Summary/Q&A | Single root-level GGUF with reviewed Qwen2 or Phi3 chat template | llama.cpp b5046 |

Repository lookup is open to any public Hugging Face owner, rather than a
publisher allowlist. File format and actual adapter scope determine readiness.
The app currently transcribes English. Other languages, models/architectures,
split GGUFs and nested GGUF loading require further tested adapters.

`openai/whisper-large-v3` contains original model weights, not a directly runnable
Whisper GGML installation. The app reports conversion required; it does not run
PyTorch/Safetensors, MLX or arbitrary Core ML files. You may choose a compatible
conversion from its publisher's separate repository after checking its card.
`ggerganov/whisper.cpp` is one example with multiple sizes, not a required owner.

For the reviewed summary option, paste
`microsoft/Phi-3-mini-4k-instruct-gguf` and choose
`Phi-3-mini-4k-instruct-q4.gguf` (2,393,231,072bytes), then Download and Equip.
The app verifies the installed file/template again before use. On-phone memory
and speed remain to be measured. Larger files are not assumed better or faster.

Stop recording before opening a meeting's **Summary** or **Ask**. Keep the app
open during generation. Validated source links, unknown-owner/date handling,
original notes and saved answers remain separate from editable generated text.

## Evidence and limits

Actual selected Whisper live speech and selected Phi summary/Q&A passed on
hosted macOS. These are working-model checks, not measurements of your phone.
Broader accuracy, long-meeting recovery/download reliability and final release
checks continue in MVP2/MVP3. Lock Screen, Action Button, two125minute runs,
offline phone use, extension signing and renewal preservation require owner
device evidence in MVP4. See MODEL_CATALOG_AND_SUMMARY evidence and STATE.json
for the exact delivered SHA/run rather than assuming a pending build is ready.
