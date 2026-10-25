# LocalMinutes MVP4

**Development candidate: one focused answer-screen retry is running.** The IPA
is downloaded and byte-verified. Run40190643613 passed76 portable,46 script,
116 app-hosted and7 screen checks plus package/hygiene checks, but failed the
answer screen's navigation to original notes/transcript. It remains FAILURE.
The harness-only retry [run40193408469](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40193408469)
retains every assertion and verifies unchanged app source. This page will record
development delivery after that actual result; the IPA is unchanged.

| Item | Value |
|---|---|
| Version | 1.0, build6; database schema5 |
| Source | `36bf6f4c8726fbc5d2efbfa4f740ef4031457233` |
| CI | [run40190643613](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40190643613) |
| Directory | `build/delivery/MVP4-Final-40190643613` |
| IPA | `LocalMinutes-1.0-36bf6f4c8726fbc5d2efbfa4f740ef4031457233-unsigned.ipa` |
| SHA256 | `08c00c22c0edd446ec0656a5695d9b05e20b7d1cc497f9186f57ec99cf00f2e0` |
| Size | 14,982,180 bytes |

## Install and choose models

Follow [Windows installation](WINDOWS_INSTALL.md). Use iLoader and your free
Apple Account. Back up first; install over the existing app with the same account
and installed bundle IDs, preserving its Live Activity extension. Do not delete
the app or update it during a recording. **Models → About LocalMinutes** should
show build6. Main/extension IDs remain `com.niranjankaruna.localminutes` and
`com.niranjankaruna.localminutes.LiveActivity` before owner signing adjustments.

In **Models**, select Speech or Summary, paste your Hugging Face repository,
review its card/compatibility/resources, then download/import and Equip. Multiple
models can stay installed; one per purpose is equipped. Phi-3 is not required.

| Purpose/format | Local engine |
|---|---|
| Reviewed streaming Zipformer ONNX set | CPU sherpa-onnx |
| Compatible Whisper GGML `.bin` | CPU whisper.cpp |
| Reviewed converted Parakeet v2 Core ML set | Native Core ML plus Swift TDT; CPU-only default |
| Supported Qwen2/Phi3-family GGUF | CPU llama.cpp for summaries and questions |

Original PyTorch/NeMo or arbitrary ONNX/Core ML files need a compatible
conversion/profile. The app explains support rather than treating every model
file as interchangeable. Assess your selected model's output manually.

## What changed

- **History/search:** Load more meetings reaches older pages; title search
  queries the entire library. Loading has its own state. Transcript search also
  exposes Load more matches beyond its first50 results.
- **Saved answers:** Edit the displayed answer and tap Save answer. Edits remain
  separate from immutable evidence, the source transcript and manual notes.
  Leaving the meeting flushes edits. A revision conflict preserves your draft;
  copy it before choosing Reopen saved answer.
- **Memory cleanup:** OS memory warnings request cancellation/drain/unload of
  active summary/Q&A work without cancelling the streaming-ASR resource claim.
- **Storage check:** Finish recording/playback/local processing, then open
  Models → Prepare storage check → Share storage check. The snapshot contains
  actual protection/backup flags and counts, source/build and environment; it
  contains no paths, meeting content or model output. Incomplete/unknown facts
  stay explicit. It does not prove locked access or renewal.

## Your phone checks

Owner-reported device: **iPhone17Pro, iOS27.0.1**. Hosted simulator checks use
iOS26.2 and do not establish behavior on that phone.

Use [the phone checklist](MVP4_DEVICE_CHECKLIST.md) and separate
[device reports](templates/DEVICE_TEST_REPORT.md). Verify installation/extension,
short recording and Live Activity Stop, offline chosen models, Action Button
warm/locked continuation/cold-start, two separate125-minute runs, actual storage
facts and in-place signing refresh. Report any unlock requirement explicitly.
All phone results are currently **NOT_RUN**; model/OS facts alone are not passes.
Keep real audio, transcripts, backups and account details private.
