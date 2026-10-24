# LocalMinutes sherpa ASR packaging

This local package preserves the `sherpa-onnx` product and `SherpaOnnx` /
`SherpaOnnxC` module names. It exports the real C API, not a replacement inference
engine. No upstream Swift convenience wrapper or TTS API is compiled.

Run `python3 scripts/prepare_asr_only.py --platform all` on hosted macOS before
resolving this package. Generated `Artifacts/*.xcframework` and receipts are
ignored. A single `Artifacts/SherpaOnnxC.xcframework` binary target contains
exactly the requested platforms. Use `--platform macos` in native-test jobs,
`--platform ios` in iOS-only jobs, or `all` when both are required before
resolution. `--platform ios` builds device arm64 and Simulator arm64/x86_64 from
sherpa revision `11afbd009a7f8c08f4bcf2fc1b265d0df4670fbf` (1.13.8).
TTS and speaker diarization are disabled at source configuration. The nine
merged archives match the pinned upstream no-TTS iOS script. ONNX Runtime is
external and remains exactly 1.28.2; it is never merged twice.

`--platform macos` packages the checksummed upstream 1.13.8 universal2 no-TTS
library archive, using only those same nine ASR archives and the pinned source
C header. Its bundled ORT, PortAudio and C++ convenience API are not included.
This is a publisher binary; its complete compiler/build-input provenance is not
attested by our source receipt. Each packaged framework is checked for both
expected CPU C entrypoints and absence of defined eSpeak/Piper symbols.

The preparer records input/output SHA-256, exact merge inputs, build flags,
compiler versions, architectures and actual symbol checks. Native linking,
real-model tests and a final IPA symbol audit remain separate acceptance gates.
No strip operation, license change, model weight or private audio is involved.
Existing third-party notices remain applicable; see `docs/DEPENDENCIES.md`.
