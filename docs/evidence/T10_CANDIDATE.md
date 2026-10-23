# T10 candidate: actual Windows CPU streaming experiment

Observed 23 October 2026 during the one-hour capability/integration preparation.
This is an actual upstream-runtime experiment, not T10 app implementation or
hosted Swift RED/GREEN. No iPhone, locked operation, signing, endurance or
production live-transcription readiness is established. T10 remains unfinished.

## Actual result

Official PyPI `sherpa-onnx==1.13.8` and `sherpa-onnx-core==1.13.8` were installed
offline from SHA256-verified wheels into ignored workspace storage only. Python
3.12.14 and bundled NumPy 2.3.5 ran the actual CPU streaming transducer with
two threads, 16,000 Hz, 80 feature dimensions, greedy search and 3,200-frame
(200 ms) chunks. No global package installation or cloud inference was used.

The original non-sensitive reference text was:

> The project review starts at nine. We agreed to ship the update on Friday.
> The next meeting is on Monday morning.

Windows' installed Microsoft Zira Desktop English (United States) SAPI voice
synthesized it locally into a real mono 16-bit PCM WAV: 134,320 samples,
8.395 seconds, 268,686 bytes, SHA256
`e06b5689e31ec54641dc68f8bb4be69ce81ac9abbdad1d213e36edfe8bca4b71`.
The generated audio remains ignored, with no redistribution license asserted;
the original reference text may be reused for this project's generated tests.
No microphone, private recording or third-party speech service was involved.

Actual final output:

> THE PROJECT REVIEW STARTS AT NINE WE AGREED TO SHIP THE UP DATE ON FRIDAY THE
> NEXT MEETING IS ON MONDAY MORNING

Measured normalized word error: **2 / 21 = 9.5238%** (`update` became `up date`).
The evaluator did not collapse those words to improve the score. It observed
21 evolving nonempty partial hypotheses, 30 decode steps and a real trailing-
silence endpoint. Reset after the endpoint produced the same next-utterance
content without duplication. Abandoning a half-fed stream and creating a new
stream also reproduced the full result without prior-stream contamination.
All evaluator assertions passed in the completed run.

One observed run loaded the model in 1.1983 seconds and decoded in 0.2806
seconds, desktop real-time factor 0.03342. Input was supplied faster than
wall-clock audio; these are capability measurements, not live latency, phone
performance, benchmark-corpus accuracy or two-hour stability evidence.

Inference used only local paths in the normal network-restricted tool sandbox,
with Python socket/DNS APIs explicitly disabled. No download occurred during
recognition. This is limited offline evidence, not an OS-wide firewall proof.

## Independently downloaded file integrity

Model source: publisher's immutable Hugging Face revision
[`672fbf1b30579d6585301139bb363f42a0ad4a24`](https://huggingface.co/csukuangfj/sherpa-onnx-streaming-zipformer-en-2023-06-26/tree/672fbf1b30579d6585301139bb363f42a0ad4a24).
The following actual local lengths and SHA256 digests matched the reported
candidate values. They are no longer merely unverified reported hashes.

| File | Actual bytes | Actual SHA256 |
| --- | ---: | --- |
| encoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx | 71083163 | 563fde436d16cf7607cf408cd6b30909819d03162652ef389c2450ced3f45ac1 |
| decoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx | 1307236 | 98da299f471e38bb4e1a8df579b8cc9122d6039576a77e357b3c60f17dd83b02 |
| joiner-epoch-99-avg-1-chunk-16-left-128.int8.onnx | 259335 | d944208d660d67c8d72cd2acaeac971fa5ceb8c80e76c1968148846fedd6e297 |
| tokens.txt | 5048 | 49e3c2646595fd907228b3c6787069658f67b17377c60aeb8619c4551b2316fb |

The exact three-int8 combination works in this actual CPU experiment. It is an
explicit candidate refinement from the specification's non-int8 decoder example,
not permission to mix unrelated chunk/left-context model sets. The fetched model
card declares Apache-2.0; preserve the card, source attribution and license
notices in final model lifecycle metadata.

Official PyPI artifacts were selected from their versioned JSON, with project
homepage pointing to k2-fsa/sherpa-onnx. Their actual bytes matched PyPI SHA256:

| Wheel | Actual bytes | Actual SHA256 |
| --- | ---: | --- |
| sherpa_onnx-1.13.8-cp312-cp312-win_amd64.whl | 2287856 | 566e49ad3fb2aa8ceb723a52f9809aa6c2ee0a5eb3b0946c3fd2374af807a5c6 |
| sherpa_onnx_core-1.13.8-py3-none-win_amd64.whl | 16903581 | 5579e80196d516e6dae23c8f629292ce3142ab8869925d32b94612fd86f93733 |

Sources: [sherpa Python package](https://pypi.org/project/sherpa-onnx/1.13.8/),
[core package](https://pypi.org/project/sherpa-onnx-core/1.13.8/), and pinned
[upstream source](https://github.com/k2-fsa/sherpa-onnx/tree/11afbd009a7f8c08f4bcf2fc1b265d0df4670fbf).
Neither iOS/macOS XCFramework archive nor ONNX dependency archive was downloaded
or independently hashed by this experiment. Their reported package checksums
remain separate from the verified Windows wheels and model bytes.

## Local evidence and setup limitations

Ignored `.agent-local/asr-evaluation/` contains `verified-downloads.json`,
`actual-result.json`, `speech-generation.json`, exact original reference/audio,
downloaded wheels/models, preparation/evaluation scripts and pinned upstream
Swift/C source copies. No weights/audio/transcript from a real meeting is staged.
The evaluator command used the bundled Python interpreter with
`.agent-local/asr-evaluation/recognize_experiment.py`.

Initial sandbox-only SAPI enumeration and pip temporary-directory access failed;
authorized direct local COM access and offline target-only wheel installation
resolved those restrictions. No settings/credentials were changed. An evaluator
setup call used `reset_stream`; inspecting the pinned installed Python wrapper
identified its actual method `reset`, after which the complete run passed. This
was an experiment API correction, not a fabricated model pass or hosted RED.

Next: prepare/activate actual Swift runtime integration tests and no-op
interfaces, prove/push meaningful hosted RED, implement only afterward, and
require exact-source native GREEN before connecting production model readiness.
All model-manager install/lease, app ASR, iOS offline/CPU and physical gates remain
pending until their own actual evidence exists.
