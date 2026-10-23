# Actual local summary candidate experiment —23 October2026

This is bounded research and a test-first handoff. No application summary
behavior, native Swift runtime, or semantic-quality pass is claimed.

## Model bytes and licenses

Official [Qwen model](https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF)
pinned revision `91cad51170dc346986eccefdc2dd33a9da36ead9`:

```text
qwen2.5-1.5b-instruct-q4_k_m.gguf
1117320736 bytes
SHA256 6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e
```

The official model API reported those values, and one actual download into
ignored `.agent-local/qwen-research` matched both length and SHA256. The pinned
LICENSE was read and begins with Apache License Version2.0. This is the Instruct
model, not the Coder model. About555GB disk space was available before the
bounded1.12GB download. No corpus, confidential data, external inference service,
or paid resource was used. `git check-ignore` confirms the weight is ignored.

The current HTTPS redirect observed with HEAD was `huggingface.co`302 to
`us.aws.cdn.hf.co`200. Signed URL query strings were suppressed. Distribution
hosts are changing upstream data; approve exact reviewed hosts rather than a
wildcard that could accept an unrelated suffix.

## Actual CPU experiment and observed accuracy failure

Official llama.cpp [b11798](https://github.com/ggml-org/llama.cpp/releases/tag/b11798)
resolves to `9febe63d5a379f8568bae7116a5b2ba844a4a4a6`, MIT license. The actual
24,044,260-byte Windows CPU archive matched its published SHA256:

```text
ee0a6715749b63bc61c193152d9442b98e13403870eb54083d64bcf407d4d375
```

The checksum-verified native executable loaded the real verified model and ran
offline, `--gpu-layers0`, context2048, four threads, greedy temperature0, seed7,
maximum192 generated tokens, single-turn mode. The original fictional evidence:

```text
[s1] Maya: We decided to ship the prototype on Friday.
[s2] Leo: I will write the installation guide by Thursday.
[s3] Maya: The training budget remains undecided.
```

The first actual process exited0, generated nonempty structured output at53.1
tokens/second, and correctly stated Friday shipment, installation-guide task,
Thursday due date, and undecided budget. It incorrectly assigned the action to
Maya instead of Leo. A second bounded actual run added explicit system guidance
to copy the speaker of "I will"; it still assigned Maya, generated52.9tokens/sec,
and used string "No" rather than a Boolean for budget_decided.

These observations establish actual native CPU inference feasibility on this
Windows host and expose semantic/schema failures. They do not pass summary
quality. Do not hide the first result, change expected owner, accept a String
where the required schema expects Boolean, or replace generation with a canned
summary. Native generation needs constrained JSON plus evidence grounding and
quality validation. Both actual outputs and runtime logs remain ignored.

## Apple binary pins and simulator gate

The actual b11798 Apple archive was also downloaded and verified:

```text
llama-b11798-xcframework.zip
66792335 bytes
SHA256 ed3a4da2f0ba7be26b9c6ed7b09f3a9e9b506b9fd5e5a2116cdebe5af0ccd624
```

Its real Info.plist contains only `ios-arm64` and `macos-arm64_x86_64`.
There is no simulator variant. Module name is `llama`; metadata minimums are
iOS16.4 and macOS13.3. This is usable for a dedicated macOS experiment, but
cannot be added to the main simulator build and called complete. The official
pinned `build-xcframework.sh` supports `ios-sim` as a selected build and compiles
arm64+x86_64 simulator binaries. Its downloaded script SHA256 is
`0764172147091a8b8b2e03134d0496fbe11bfa9aa1945962701d1605287e731b`.
It cleans build directories and must run only inside a fresh ignored source
checkout; this worker did not execute it on Windows.

A faster complete official candidate was then actually verified:

```text
llama-b5046-xcframework.zip
74944281 bytes
SHA256 c19be78b5f00d8d29a25da41042cb7afa094cbf6280a225abe614b03b20029ab
source 74d4f5b041ad837153b0e90fc864b8290e01d8d5
https://github.com/ggml-org/llama.cpp/releases/download/b5046/llama-b5046-xcframework.zip
```

The checksum matches the [official XCFramework documentation](https://github.com/ggml-org/llama.cpp/blob/9febe63d5a379f8568bae7116a5b2ba844a4a4a6/docs/xcframework.md).
Its actual AvailableLibraries includes:

| Identifier | Platform | Variant | Architectures |
|---|---|---|---|
| ios-arm64 | ios | device | arm64 |
| ios-arm64_x86_64-simulator | ios | simulator | arm64,x86_64 |
| macos-arm64_x86_64 | macos | native | arm64,x86_64 |

Additional tvOS/visionOS slices are present. b5046 is an older runtime candidate;
the Windows experiment used b11798. Actual b5046/Qwen load, tokenization,
generation, JSON schema and quality must therefore pass on hosted macOS before
using this pin. No model-readiness inference follows from architecture metadata.

## Test-first native handoff

`LocalSummaryRuntime.swift` imports the real native module `llama`, then throws
notImplemented. Root may activate it under `Summary/`, add a library target
`LocalMinutesSummary` depending on a `llama` binary target, and activate
`LocalSummaryRuntimeTests.swift` under a dedicated SummaryTests target. Download,
verify and extract the complete b5046 framework to ignored
`Native/Artifacts/llama.xcframework` before package evaluation. A path binary
target avoids guessing whether the release ZIP's enclosing build-apple directory
is accepted as a remote SwiftPM binary layout.

Provide `LOCALMINUTES_QWEN_MODEL_PATH` to the exact verified real GGUF file. Its
absence is a test failure, never a skip. Four complete intended cases:

```text
testActualQwenProducesValidJSONWithCorrectActionSpeakerAndDecision
testActualQwenPreservesUnknownBudgetAndReturnsOnlySuppliedEvidenceIDs
testNativeSummaryLoadRejectsMissingAndInvalidGGUF
testCancelledNativeGenerationDoesNotPublishAndRuntimeCanBeReused
```

The first two and cancellation retry require actual model output, strict JSON
decoding, correct Leo attribution, and uncertainty. Invalid bytes test only native
load rejection and cannot count as actual inference. Runtime resources must be
released safely, and each generation must reset its native context so cancelled
or prior conversation state cannot contaminate another meeting.

No Swift source in this handoff has compiled or executed. Actual hosted
behavioral RED must precede implementation, followed by exact-source GREEN and
device/simulator compilation. App integration must run summaries after capture
and ASR release; no concurrent ASR/LLM requirement is introduced. Physical-phone
performance, locking, signing and both125minute tests remain pending with owner.
