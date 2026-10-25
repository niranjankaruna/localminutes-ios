# Native dependency and notice inventory

Audit dates: 24–25 October 2026. **IN_PROGRESS; not a complete SBOM or legal clearance.**
This records the pinned checkout, independently inspected public artifacts and
the delivered MVP2 development preview. It changes neither project licensing nor
runtime/dependency selection. Updated notices become part of a later build;
the already-delivered IPA is unchanged.

## Pinned runtime sources

| Component | Source pin and license | App scope |
|---|---|---|
| llama.cpp / ggml | [b5046 source](https://github.com/ggml-org/llama.cpp/tree/74d4f5b041ad837153b0e90fc864b8290e01d8d5), MIT | Local GGUF summaries/questions; dynamic `llama.framework`. |
| whisper.cpp / ggml | [v1.7.5 source](https://github.com/ggml-org/whisper.cpp/tree/51c6961c7b64b406833f4b6a4a20e67142f69225), MIT | Rolling Whisper GGML recognition; dynamic `whisper.framework`. |
| sherpa-onnx | [pinned package/source](https://github.com/k2-fsa/sherpa-onnx/tree/11afbd009a7f8c08f4bcf2fc1b265d0df4670fbf), v1.13.8, Apache-2.0 plus transitive notices below | Local ASR-only Swift wrapper and static SherpaOnnxC candidate; streaming Zipformer. Delivered MVP2 contains unused TTS code; final MVP3 symbol audit is pending. |
| ONNX Runtime | [packaging revision](https://github.com/csukuangfj/onnxruntime-libs/tree/8ebc5ebf92190903c274a7621ba4c96a732335ec), exact package1.28.2; [Microsoft source/license](https://github.com/microsoft/onnxruntime/tree/33ca9628233dc8f002435e868d4c2e9f82766ca1), MIT plus third-party notices | Static ORT dependency of sherpa. Microsoft source commit is the resolved v1.28.2 tag; this is not an attestation of the distributor's complete build inputs. |
| FluidAudio | [c79c4106b954f81205113c3343e5a7e59a1089b5](https://github.com/FluidInference/FluidAudio/tree/c79c4106b954f81205113c3343e5a7e59a1089b5), Apache-2.0 plus fastcluster notice | Source-built Core ML/Swift TDT Parakeet. Swift6.2 manifest with `traits: []`; see exclusions below. |
| Apple system frameworks / SQLite | SDK-provided SwiftUI, App Intents, ActivityKit, WidgetKit, AVFoundation, Core ML, Accelerate, Metal, Foundation and `libsqlite3` | System SDK dependencies; no separately downloaded SQLite binary. Exact system versions depend on build/device OS. |

The ONNX packaging repository has no root license file in the inspected pinned
tree. Its published binary version and Microsoft license are recorded separately;
do not infer a license grant for every packaging-source file from the binary's
MIT license.

## Independently checked distribution archives

These SHA-256 values were calculated from actual downloaded bytes. They match
the existing preparers or pinned package checksums and publisher release digests.
The iOS archives contain device arm64 and arm64/x86_64 Simulator slices; macOS
archives contain arm64/x86_64. Extra tvOS/visionOS slices in the ggml archives are
not app targets.

| Archive | Bytes | SHA-256 |
|---|---:|---|
| llama-b5046-xcframework.zip | 74,944,281 | `c19be78b5f00d8d29a25da41042cb7afa094cbf6280a225abe614b03b20029ab` |
| whisper-v1.7.5-xcframework.zip | 37,754,339 | `c7faeb328620d6012e130f3d705c51a6ea6c995605f2df50f6e1ad68c59c6c4a` |
| sherpa-onnx-v1.13.8-ios-static.xcframework.zip | 17,013,113 | `6b8e769cb153343270fdccbe92e3b3db0d1c421d67fa0989ab01fdf5b2fcf2de` |
| sherpa-onnx-v1.13.8-macos-static.xcframework.zip | 11,628,310 | `93f7a064abe99e0d6185a88c5b36ce18c4bff35cd0d5e4e81f81151de8e3e7e5` |
| onnxruntime-ios-static-xcframework-1.28.2.xcframework.zip | 33,821,118 | `2c2299acbb461d26d4bac4bc85985d40e7c7177ed6072703ae0846d88b0b4599` |
| onnxruntime-macos-static-xcframework-1.28.2.xcframework.zip | 23,683,204 | `cb0b0bec912c77229517c463e28a3fac9674c521f9599919efff1ef2b42f3da0` |

All six ZIP central directories were inspected: none contains a LICENSE, NOTICE,
COPYING or third-party-notice entry. Source licenses are therefore reproduced
in [the shipped notice resource](../Resources/THIRD_PARTY_NOTICES.txt). Raw GitHub
source files were decoded from API base64, not copied from normalized PowerShell
text files. Source-file checksums accompany the copied text. The full Microsoft
`ThirdPartyNotices.txt` is preserved: 325,054bytes,
SHA-256`0e07b95f3a8d6230037707c5c4a2b554d12c4cb67369669ac255635528ffcee2`.
It is an upstream platform-wide superset, not a claim that every listed backend
is present in the iPhone build.

## Actual preview membership and transitive sources

Inspected IPA: source`35c7cefb946af188f5cc09858dca4ab180d72eab`,
run40132528745, SHA-256
`21b6feaf59824a2eb6ab92de68fdb07fc9eb36449ba58337b41771ad986ac7f6`.
Its arm64 main executable's Mach-O `LC_SYMTAB` contains **18 defined `_espeak*`
symbols**, three defined Piper namespace symbols and six KissFFT symbols.
The parser excludes debug/STAB and undefined symbols and requires `N_SECT` with
a nonzero section. Examples include `_espeak_Initialize`, `_espeak_ListVoices`
and Piper's `phonemize_eSpeak`. This establishes actual linked TTS-component
membership despite the absence of a TTS feature in LocalMinutes.

The pinned sherpa CMake files declare these additional source inputs. Archive
hashes below are upstream CMake pins, not independently downloaded-source hashes.
The following notices are reproduced without changing LocalMinutes' license:

| Source component | Reviewed source reference | Published notice |
|---|---|---|
| kaldi-native-fbank | `v1.22.3`; source archive SHA256`9176cc66fc7ce1edf85cf355b06e320c57db6297df74277f575183468893cf61` | Apache-2.0 |
| KissFFT | `febd4caeed32e33ad8b2e0bb5ea77542c40f18ec`; archive SHA256`497103e664168ebe39580b757adbe616f6cf85a16572af581ca7bc42d0ab13fd` | Mark Borgerding copyright and full BSD-3-Clause |
| kaldi-decoder | `v0.3.0`; archive SHA256`b9f34cfb4fd3b1344100eead79ef4d37aa15962274b9e3056de345021f76a1b0` | Apache-2.0 |
| OpenFst / kaldifst | `v1.8.5-2026-07-09`; archive SHA256`2ff712a32952fcb01d351121a6bc8ccf4fdc6b2aa06ce8df2b3095dedd518c0e` | Apache-2.0 / COPYING |
| simple-sentencepiece | `v0.7`; archive SHA256`1748a822060a35baa9f6609f84efc8eb54dc0e74b9ece3d82367b7119fdc75af` | Apache-2.0 |
| Piper phonemize | `f3ff95afc03640bc1399e113e83361192a2fafb4`; archive SHA256`d9cca4e2bdc7d6dd8dffb96a4668283dbd3f77a9c194a3e530c1e8eba9406a5d` | MIT |
| eSpeak NG fork / Unicode data | `ed530aa113046142eb5115cf2fc9157854d0ffe1`; archive SHA256`e4e262cbe34f7fe21f91f1ba3397f2728e1f30eafbae7853f2b753a9ed13f0dd` | GPLv3 COPYING; supplementary Apache-2.0, BSD2 and UCD notices |
| nlohmann JSON | `v3.12.0`; archive SHA256`4b92eb0c06d10683f7447ce9406cb97cd4b453be18d7279320f7b2f025c10187` | MIT |
| Eigen | `5.0.1`; archive SHA256`e9c326dc8c05cd1e044c71f30f1b2e34a6161a3b6ecf445d56b53ff1669e3dec` | MPL-2.0 and supplementary BSD text |
| hclust-cpp | `2026-02-25`; archive SHA256`8f14e024c709d73afb40ae69cb22de4b73dba67cbce40f2e518813da8139ab56` | Upstream BSD/copyright notice |
| FluidAudio FastClusterWrapper | Same pinned FluidAudio revision; unconditional target dependency even with empty traits | Pinned fastcluster BSD-2-Clause notice |

Presence of a published license is not a determination that this distribution
satisfies every source-distribution obligation. The actual eSpeak membership
requires release/source-compliance review. No relicensing or owner approval for
relicensing is inferred. An ASR-only replacement is a separate tested change.

## Build policy versus runtime policy

LocalMinutes uses hosted Xcode26.2, Swift6 language mode, SwiftPM tools6.2,
XcodeGen2.46.0 and iOS18 minimum. The candidate build manifest records the actual
compiler/SDK build; upstream prebuilt compiler identities are not attested here.

The pinned llama/Whisper build scripts enable embedded Metal and BLAS support,
disable OpenMP/examples/tests/server and set `GGML_NATIVE=OFF`. They build static
inputs and wrap them into dynamic Apple frameworks. **CPU inference policy does
not mean these distributed frameworks lack GPU code.** App adapters explicitly
set llama`n_gpu_layers=0`/`offload_kqv=false`, Whisper`use_gpu=false`/
`flash_attn=false`, and sherpa provider`cpu`. Delivered MVP2 Parakeet permits
Core ML CPU+Neural Engine. The MVP3 production default is now CPU-only after an
actual failing policy test; its repaired default awaits GREEN. Explicit CPU-only
real-model corpus execution passed. Neither configured policy enables the GPU;
physical scheduling and locked-screen performance remain unverified.

FluidAudio's `Package@swift-6.2.swift` selects no default traits in this project.
TTS, diarization and NemoTextProcessing conditional dependencies/resources are
disabled; FastClusterWrapper and MachTaskSelfWrapper remain direct dependencies.
Do not use the older unconditional `Package.swift` to describe this build.

The current sherpa static build sets C API ON, binary/Python/tests/PortAudio/
JNI/WebSocket OFF; its regular script does **not** disable TTS. Root
`CMakeLists.txt` defaults `SHERPA_ONNX_ENABLE_TTS` and
`SHERPA_ONNX_ENABLE_SPEAKER_DIARIZATION` to ON. Its merge list explicitly includes
Piper, eSpeak and UCD. Disabling their executables/tests does not remove those
libraries.

## ASR-only source integration, 25 October 2026

The MVP3 source now replaces the old sherpa binary dependency with the local
`Vendor/SherpaASROnly` package. `scripts/prepare_asr_only.py` builds the same
revision with TTS, speaker diarization, GPU providers, executables and PortAudio
disabled, and explicitly merges only the nine required ASR archives. ONNX Runtime
remains the separately pinned 1.28.2 dependency. This supersedes the old regular
static build described above; delivered MVP2 bytes are unchanged.

Run40135661801 built and retained the three iOS framework slices. Independent
Windows verification checked the receipt, all 13 archive file hashes and five
architectures. That framework result alone did not prove application linking or
recognition. Run40172670154 is checking the application integration; its summary
lane has passed Swift build-test compilation after the Swift-tools6.2 correction.
Real ASR, final device linkage and the IPA's absence of unused TTS definitions
must still pass before MVP3 delivery. The source archive, header and platform
inputs are individually hashed in the generated receipt.

## Prior ASR-only investigation evidence

The same pinned source provides [build-ios-no-tts.sh](https://github.com/k2-fsa/sherpa-onnx/blob/11afbd009a7f8c08f4bcf2fc1b265d0df4670fbf/build-ios-no-tts.sh).
It passes `-DSHERPA_ONNX_ENABLE_TTS=OFF` for all three iOS slices and omits
Piper/eSpeak/UCD from its archive merge. `SHERPA_ONNX_ENABLE_SPEAKER_DIARIZATION=OFF`
is a separate available source option. Native linking, Swift wrapper compatibility,
real ASR regression and final IPA symbol exclusion still require evidence.

The official `xcframework` and `v1.13.8` release inventories contain no no-TTS iOS
framework. A macOS universal2 **library tarball**, not an XCFramework, exists:
`sherpa-onnx-v1.13.8-osx-universal2-static-no-tts-lib.tar.bz2`,39,379,910bytes,
independently verified SHA256
`7bbaa4bf1c73a68cc9ea126967278873c86eeeb99774b544f3644e0a6200e993`.
Its twelve libraries contain no `espeak_Initialize` or `phonemize_eSpeak` bytes;
the C API archive contains the online-recognizer API. Independent universal-ar
and Mach-O symbol-table inspection finds 847 defined records in the C API and
60,481 in the core library across arm64/x86_64, with zero forbidden eSpeak/Piper
definitions; the online-recognizer constructor is defined for both architectures.
This is an investigation result, not native load/recognition/link proof.
The tarball also contains unused
PortAudio and ORT libraries; blindly merging every archive is inappropriate.

## Remaining release evidence

- Complete binary-to-source/build correspondence and notices for the eventual
  ASR-only candidate, including exact source archives and final symbol audit.
- Review upstream ORT's broad notice set against actual compiled components,
  plus packaging-wrapper permission and transitive source disclosures.
- Verify notice text in the final checksummed IPA; this resource edit is not
  retroactively present in the inspected development preview.
- Capture a reproducible final dependency-resolution inventory/lockfile and
  build manifest. Do not infer a complete SBOM from six archive hashes.
- Keep installed-model provenance/licenses separate from app libraries: model
  weights are not bundled. Existing notices identify Whisper GGML, Qwen,
  Microsoft Phi and NVIDIA/FluidInference Parakeet; these are not endorsements
  or claims that arbitrary repositories/models are supported.

No physical-device, offline/endurance, signing, renewal or final baseline gate
is passed by this documentation audit.
