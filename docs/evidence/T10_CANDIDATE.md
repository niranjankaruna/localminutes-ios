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
The later bounded archive inspection below independently verified both static
XCFramework archives. Their checksum/declarative slice evidence is separate
from actual native linking or execution. The ONNX dependency archive has not
been independently downloaded/hashed by this experiment.

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

## Licensed fixed native-test fixture: actual second experiment

The [official OpenSLR LibriSpeech resource](https://www.openslr.org/12) declares
CC BY 4.0. Attribution: LibriSpeech, prepared by Vassil Panayotov with assistance
from Daniel Povey, derived from LibriVox public-domain audiobooks. Preserve
[CC BY 4.0 attribution/license](https://creativecommons.org/licenses/by/4.0/).
Audio remains ignored; no private speech or Windows system-voice audio is
uploaded. This public corpus fixture is the proposed hosted test input.

A bounded streamed prefix from the official
[`test-clean.tar.gz`](https://www.openslr.org/resources/12/test-clean.tar.gz)
provided exactly `LibriSpeech/test-clean/6930/75918/6930-75918-0000.flac`
and its reference in `6930-75918.trans.txt`. The actual member is 74,138 bytes,
SHA256 `9ce35224156f071ab58eb7feb8a5ceae600f6f9f353da2a6cbf797b6b1ac8a23`.
Only 3,645,440 compressed prefix bytes were read; the entire archive was neither
downloaded nor checksum-verified. The selected member has an independently
downloaded exact digest. No archive member path was extracted to disk.

Reference and actual final CPU output both equal:

> CONCORD RETURNED TO ITS PLACE AMIDST THE TENTS

Actual decoding: mono 16 kHz, 56,080 samples, 3.505 seconds, same pinned model/
runtime/CPU/two-thread/200 ms configuration. It produced seven evolving partials
and **0 / 8 normalized word errors** on this single short sample. This is a
smoke-test input, not validation of corpus-wide or representative-meeting WER.
Endpoint/reset and discarding/replacing a partial stream preserved the exact
reference. A three-second trailing-silence input triggered the real endpoint.

The experiment exposed a real finalization boundary: plain `input_finished()`
lost `TENTS`; 3,200 decoder-padding frames produced `TENT`; 24,000 padding frames
(1.5 seconds) preserved exact `TENTS`. Padding must remain bounded and excluded
from captured source-sample counts. A 1.5-second appended input did not yet
trigger the endpoint for this short utterance, so the dedicated endpoint test
uses 48,000 silence frames. These observed native-runtime facts inform failing
tests; they are not app implementation or hosted RED evidence.

Official PyPI `soundfile==0.13.1` decoded FLAC only for this Windows experiment,
installed offline into the same ignored target. Actual wheel:
`soundfile-0.13.1-py2.py3-none-win_amd64.whl`, 1,019,162 bytes, SHA256
`1e70a05a0626524a69e9f0f4dd2ec174b4e9567f4d8b6c11d38b5c289be36ee9`, matching
[versioned PyPI metadata](https://pypi.org/project/soundfile/0.13.1/).
No global installation was made. Recognition ran with local paths and disabled
Python socket/DNS APIs. Ignored `librispeech/actual-result.json` records outputs;
`recognize_librispeech.py` reproduces the completed assertions. The separate
draft fixture-preparation script pins the exact input for hosted use, subject
to actual macOS setup and compiler verification.

## Actual static native archive integrity and declarations

Both official versioned archives were downloaded into ignored research storage
and their complete bytes matched the immutable source package's SHA256:

| Official release asset | Actual bytes | Actual SHA256 |
| --- | ---: | --- |
| sherpa-onnx-v1.13.8-macos-static.xcframework.zip | 11628310 | 93f7a064abe99e0d6185a88c5b36ce18c4bff35cd0d5e4e81f81151de8e3e7e5 |
| sherpa-onnx-v1.13.8-ios-static.xcframework.zip | 17013113 | 6b8e769cb153343270fdccbe92e3b3db0d1c421d67fa0989ab01fdf5b2fcf2de |

Sources: official
[macOS asset](https://github.com/k2-fsa/sherpa-onnx/releases/download/xcframework/sherpa-onnx-v1.13.8-macos-static.xcframework.zip),
[iOS asset](https://github.com/k2-fsa/sherpa-onnx/releases/download/xcframework/sherpa-onnx-v1.13.8-ios-static.xcframework.zip)
and pinned
[package manifest](https://github.com/k2-fsa/sherpa-onnx/blob/11afbd009a7f8c08f4bcf2fc1b265d0df4670fbf/Package.swift).
Only ZIP-contained module maps and XCFramework Info.plist were read; no binary
was installed or executed. Every inspected module map declares framework module
`SherpaOnnxC`, exporting `sherpa-onnx/c-api/c-api.h`. The macOS plist declares
arm64+x86_64. The iOS plist separately declares device arm64 and simulator
arm64+x86_64. These are actual archive declarations, not Mach-O verification,
minimum OS/build-flag proof, SDK compilation, runtime linkage or iPhone evidence.
Ignored `native-archive-inspection.json` preserves the exact declarations.
