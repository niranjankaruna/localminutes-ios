# LocalMinutes MVP2 guide

**MVP2 delivered for sideloading, including native Parakeet.** Exact source below passed [run40132528745](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40132528745): 281 portable, 8 actual native Parakeet, 10 actual speech-recovery and 10 app integration checks passed, with zero failures/skips. Release iPhone app plus Live Activity packaging passed. Windows independently verified the IPA checksum, ZIP CRC, source stamps, arm64 iPhoneOS executables, identifiers and absence of model weights/private fixtures. Physical-device gates remain **NOT_RUN**; this is an MVP delivery, not final baseline acceptance.

| Delivery item | Current value |
|---|---|
| Unsigned IPA | `build/delivery/MVP2-Parakeet-40132528745/LocalMinutes-1.0-35c7cefb946af188f5cc09858dca4ab180d72eab-unsigned.ipa` |
| Exact packaged source | `35c7cefb946af188f5cc09858dca4ab180d72eab` |
| IPA SHA-256 | `21b6feaf59824a2eb6ab92de68fdb07fc9eb36449ba58337b41771ad986ac7f6` |
| Version / build / size | 1.0 / 3 / 15,779,005 bytes |
| Build manifest | `build-manifest.json` beside the IPA; Xcode26.2, SDK26.2, runner image20260907.0337.1 |
| Retained remote copy | Owner-only unpublished draft `mvp-preview-35c7cefb946a`; no public release published |

Use the [verification record](VERIFICATION.md), [MVP2 evidence](evidence/MVP2_RELIABILITY_2026_10_24.md) and final handoff for results. An earlier IPA is a separate build.

## Install or update from Windows

Use the [Windows installation and renewal guide](WINDOWS_INSTALL.md) and [iLoader's official site](https://iloader.app/). You need Windows 11, an iPhone, USB and a free Apple Account. Builds use hosted macOS; you do not need a Mac, local Xcode or paid Apple Developer membership.

When a candidate is actually delivered, compare the IPA checksum with its supplied SHA-256 file, then install **over the existing app** through iLoader. Keep the same Apple Account and installed bundle-ID settings, and preserve the embedded Live Activity extension. The build identifiers are `com.niranjankaruna.localminutes` and `com.niranjankaruna.localminutes.LiveActivity`; keep the settings that produced your existing installation. Handle sign-in, 2FA and phone trust locally, never in chat.

Refresh using iLoader every seven days. Do not uninstall to renew. Export important data first; in-place renewal and preservation still require checks on your phone. The owner's earlier successful main-app installation does not verify this candidate or its extension.

**Database compatibility:** MVP2 uses schema 5 for captured speech-model pins. Older apps that support only schema 4 or earlier deliberately refuse the upgraded database. Installing an older IPA is not a supported downgrade or restore method.

## Native Parakeet setup

1. Open **Models → Speech**, enter [`nvidia/parakeet-tdt-0.6b-v2`](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2), and choose **Look up repository**. Read its model card and conversion explanation. The original NeMo model is not the installable iPhone resource set.
2. Tap **Look up FluidInference/parakeet-tdt-0.6b-v2-coreml** in the compatibility section. This opens the [reviewed Core ML conversion](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml/tree/ee09c569f73759e6d44c9bd16766f477b2b36d39).
3. Check that the supported selection lists **21 files, 464,413,247 bytes** (about 464 MB), pinned to `ee09c569f73759e6d44c9bd16766f477b2b36d39`. Use **Download selected model**, then **Equip**. This selection downloads the reviewed subset, not every variant in the repository.
4. Alternatively, use **Import from Files** and select one folder containing `Decoder.mlmodelc`, `Encoder.mlmodelc`, `JointDecision.mlmodelc`, `Preprocessor.mlmodelc` and `parakeet_vocab.json`, with all nested files intact. Selecting one bundle, a `.nemo` file or unrelated Core ML assets does not install this set.

The native engine combines Core ML models with the Swift TDT decoder from [FluidAudio's pinned source](https://github.com/FluidInference/FluidAudio/tree/c79c4106b954f81205113c3343e5a7e59a1089b5). Its configured compute policy allows **CPU and Neural Engine, with no GPU**. Actual device scheduling, speed and locked-screen performance remain to be measured.

Parakeet processes completed audio chunks of roughly five seconds and then publishes text; decoding adds time. **This is chunked progress, not native frame-by-frame streaming.** Its presence in the candidate does not establish a successful two-hour meeting. Model attribution is NVIDIA/FluidInference, CC-BY-4.0; the pinned Swift decoder source is Apache-2.0.

## Other model choices

| Purpose | Supported scope |
|---|---|
| Speech: Whisper | Compatible GGML `ggml-*.bin` files through whisper.cpp 1.7.5; rolling chunk processing on CPU. [`ggerganov/whisper.cpp`](https://huggingface.co/ggerganov/whisper.cpp) offers conversions. |
| Speech: streaming Zipformer | The exact reviewed matching encoder, decoder, joiner and tokens set through sherpa-onnx 1.13.8 on CPU. |
| Summary and questions: Phi | [`microsoft/Phi-3-mini-4k-instruct-gguf`](https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-gguf), `Phi-3-mini-4k-instruct-q4.gguf`, about 2.39 GB. |
| Summary and questions: other GGUF | One compatible root-level GGUF using the supported Qwen2 or Phi3 architecture/chat template. Arbitrary architectures, split files and model-card promises do not establish compatibility. |

[`openai/whisper-large-v3`](https://huggingface.co/openai/whisper-large-v3) contains original weights; choose a compatible GGML conversion instead of importing PyTorch/Safetensors. Parakeet support is the exact reviewed conversion above, not arbitrary Core ML models. English is the baseline language.

Download and Equip are separate. Keep multiple installed alternatives if space permits, then choose one Speech model and one Summary model. Stop active work before switching or removing a model. **Remove** deletes the selected installation; it does not delete meetings. Keep the speech model used by unfinished meetings installed: recovery uses the captured pin and cannot guess today's equipped alternative. See [model-choice instructions](MVP1_MODELS.md); the Parakeet steps above extend that earlier guide.

## Meetings, recovery and summaries

- Start and stop from **Record**, then open the saved meeting under **Meetings**. Original notes, transcript, playback and generated content remain separate.
- Choose **Resume transcript from saved audio** to continue eligible unfinished processing. **Cancel transcript recovery** stops further work while retaining saved progress. Missing original model pins or damaged audio require review; skipped audio is not silently declared transcribed.
- After recording stops, use **Generate or resume summary**. Keep the app open. Validated chunk results can be retained after cancellation and reused only when the source, model, prompt, plan and budgets still match.
- If progress is stale, explicitly choose **Start a fresh summary…** and confirm. This discards unfinished summary progress before retrying; it does not silently relabel old results. A completed summary is saved before its processing checkpoint is removed.
- Edit generated text separately, use **Save summary** if needed, and review summaries and answers against their cited transcript/audio. Local generation can reject unsupported output or reach processing limits. Representative long-meeting quality is not established by one fixture.

## Delete, back up and restore

Swipe a meeting or use its context menu, or open its detail screen and choose **Delete meeting**. Confirm deletion of that meeting's current-library audio, transcript, original notes, summaries, answers and processing cache. Stop playback or processing if deletion is refused.

In **Meetings → Library actions**, choose **Create library backup**, then **Save or share library backup**. The backup folder contains private meeting data, including audio. Save it somewhere you control; models and credentials are not backup payloads.

To restore, choose **Restore library backup…**, select the complete backup folder, and confirm replacement after saving edits and stopping other work. The restored library becomes active. The previous library is retained, and installed model storage remains separate. Do not manually overwrite a live database or merge backup folders.

**Exported backups, retained previous libraries and shared copies are separate snapshots.** Deleting a meeting from the active library does not erase those copies; manage them separately when you intend to remove every copy.

## Recording report and phone checks

Use **Meetings → Library actions → Prepare recording report**, then **Share sampled recording report**. The typed report contains sampled counters, backlog, memory, thermal/battery and route categories; unavailable measurements remain unknown. It excludes meeting text/audio and device-route names. Samples and hosted tests do **not** prove that the screen was locked or that a two-hour meeting passed.

The owner will perform the physical checks: offline use, embedded extension and Live Activity Stop, Action Button shortcut, locked continuation, locked cold start, **two 125-minute runs**, and seven-day renewal preservation. Action Button assignment is **Settings → Action Button → Shortcut → Toggle LocalMinutes Recording**. An unlock-required cold start remains an explicit limitation until observed otherwise. Record real results in the [device report](templates/DEVICE_TEST_REPORT.md); none of those results is claimed here.
