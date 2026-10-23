# T10.1 test-first native CPU streaming slice

Draft only: nine mandatory real-runtime tests plus a compileable no-behavior
interface. Nothing here has been compiled or run as Swift. The completed Windows
upstream experiment is separately recorded in
[T10_CANDIDATE](../../evidence/T10_CANDIDATE.md). It is not native RED/GREEN.
No inference behavior may replace the stub until these tests are committed,
pushed and execute meaningful failing assertions on compatible hosted macOS.

## Exact activation and dependency wiring

Root integrates these files; this agent edits no active source or build config:

| Draft | Proposed active path |
| --- | --- |
| CPUStreamingRecognizer.swift.pending | Transcription/CPUStreamingRecognizer.swift |
| CPUStreamingRecognizerTests.swift.pending | Tests/ASRTests/CPUStreamingRecognizerTests.swift |
| prepare_native_fixture.py | May run in place as test setup, or move under scripts with equivalent behavior |

The application specification calls this directory `Transcription/`. Add product
`LocalMinutesTranscription`, target `LocalMinutesTranscription` at that path,
and test target `ASRTests` depending on it at `Tests/ASRTests`. Package dependency:

```swift
.package(url: "https://github.com/k2-fsa/sherpa-onnx",
         revision: "11afbd009a7f8c08f4bcf2fc1b265d0df4670fbf")
```

The transcription target depends on
`.product(name: "sherpa-onnx", package: "sherpa-onnx")`.
The upstream product contains Swift module `SherpaOnnx` and conditional native
framework module `SherpaOnnxC`; the stub imports both, so linkage/module failures
must be resolved before a behavioral RED is counted. For XcodeGen, use the same
repository/revision package and product `sherpa-onnx` on the main app target only;
include `Transcription/` there. The Live Activity extension needs no recognizer,
model, ONNX dependency or recording resources. Root owns actual app integration.

The pinned [upstream Package.swift](https://github.com/k2-fsa/sherpa-onnx/blob/11afbd009a7f8c08f4bcf2fc1b265d0df4670fbf/Package.swift)
uses tools5.9, iOS15/macOS10.15, static XCFrameworks and exact
`csukuangfj/onnxruntime-libs`1.28.2, with `c++` linkage. Keep root Swift6/iOS18/
macOS15 checks enabled. Review and retain Package.resolved and native binary
provenance. No preconcurrency, unchecked Sendable or disabled isolation checks
are proposed. Static archive download/hash/declarative slice inspection is
recorded in the evidence; compilation/linking and actual Mach-O minimum OS
verification remain required. Device arm64 and simulator arm64 are distinct.

## Native SDK calls, ownership and execution

Use the checked [pinned C API](https://github.com/k2-fsa/sherpa-onnx/blob/11afbd009a7f8c08f4bcf2fc1b265d0df4670fbf/sherpa-onnx/c-api/c-api.h):

1. Zero-initialize `SherpaOnnxOnlineRecognizerConfig`, set only the transducer
   family, four local paths, sample_rate16000, feature_dim80, num_threads2,
   provider`cpu`, decoding_method`greedy_search`, endpoint enabled and explicit
   rules1/2/3 of2.4/1.2/20 seconds. Retain stable C strings through creation.
2. Check `SherpaOnnxCreateOnlineRecognizer` and `SherpaOnnxCreateOnlineStream`
   for nil; copy actual `SherpaOnnxGetVersionStr()` into readiness diagnostics.
   Missing/unverified files must never be passed blindly into native creation.
3. `SherpaOnnxOnlineStreamAcceptWaveform` borrows normalized Float32 samples;
   decode only while `SherpaOnnxIsOnlineStreamReady` is nonzero. Copy text and
   optional timestamp data from `SherpaOnnxGetOnlineStreamResult` before its
   matching `SherpaOnnxDestroyOnlineRecognizerResult`, including every failure
   path. A nil result is a checked failure, never fabricated transcript text.
4. Query `SherpaOnnxOnlineStreamIsEndpoint`. Reset only an observed endpoint via
   `SherpaOnnxOnlineStreamReset`; preserve the epoch source-sample count. C token
   timestamps are relative to that utterance, not global meeting timestamps.
5. For finish, append bounded decoder-only padding before
   `SherpaOnnxOnlineStreamInputFinished`, then drain. The actual fixed fixture
   needs more than3,200 padding frames:24,000 preserves the exact final word.
   Padding does not advance captured-source sample counts. Never append again
   after InputFinished. Cache completion for idempotent repeated finish.
6. Cancel destroys the stream; the next start creates a fresh stream. Destroy
   streams before their recognizer, once each, including actor teardown.

The [upstream Swift wrapper](https://github.com/k2-fsa/sherpa-onnx/blob/11afbd009a7f8c08f4bcf2fc1b265d0df4670fbf/swift-api-examples/SherpaOnnx.swift)
force-unwraps recognizer/stream creation and fatal-errors on a nil result. Its
`toCPointer` helper also returns an NSString-derived pointer without owning a
longer-lived storage scope. A checked adapter should use explicit C ownership,
not copy these failure/lifetime assumptions into the app.

All native work must use one dedicated serial worker, ideally an actor with a
DispatchQueue-backed custom SerialExecutor. A default cooperative actor alone
does not meet the dedicated-worker contract. C pointers stay actor-isolated;
no opaque pointer crosses an actor boundary or becomes unchecked Sendable.
The caller feeds one bounded <=3,200-frame request at a time, awaiting it before
the next; the broader durable/backlog/assembly pipeline remains T11 work.
Never run inference or model load in the audio tap or MainActor. An internal
test-only observer reports actual native-call thread and dedicated-queue
identity. The public initializer uses no observer. The streaming test calls
from MainActor and requires load/decode observations off-main on that worker,
alongside real recognized output; test-only observation storage uses Mutex.

## Fixed speech preparation and test command

Run from repository root on hosted macOS before tests:

```sh
python3 docs/drafts/T10/prepare_native_fixture.py
export LOCALMINUTES_ASR_MODEL_DIRECTORY="$PWD/.agent-local/asr-evaluation/native-fixtures/model"
export LOCALMINUTES_ASR_FIXTURE_PATH="$PWD/.agent-local/asr-evaluation/native-fixtures/6930-75918-0000.flac"
swift test --filter CPUStreamingRecognizerTests
```

Use root's strict native test reporter and actual return-code handling. The
script downloads only immutable HF model files and a bounded official OpenSLR
archive prefix, verifies exact sizes/SHA256/reference, and writes ignored local
fixtures. No executable, voice, extra package or full corpus is installed.
Setup has no automatic retry; root may apply the repository's bounded transient
retry policy. The archive path is never extracted. Only fixed member bytes are
copied, within32MiB compressed/120 seconds and1,000 members. A stale partial file
fails explicitly for review instead of overwriting unknown data.

The fixture is CC BY4.0 LibriSpeech `6930-75918-0000`,74,138 FLAC bytes,
SHA256 `9ce35224156f071ab58eb7feb8a5ceae600f6f9f353da2a6cbf797b6b1ac8a23`.
Reference: `CONCORD RETURNED TO ITS PLACE AMIDST THE TENTS`. It is3.505seconds
of mono16k speech. [Attribution/license](https://www.openslr.org/12) is preserved
in the preparation receipt and sanitized evidence. Do not commit or upload the
audio; CI re-downloads the exact public input and verifies it. Actual Windows
runtime output matched all8 words, with seven evolving partials; no-padding
finalization lost the last word. Native setup's AVAudioFile FLAC read and SDK
symbols remain to be compiled and exercised on macOS; errors there are setup/
compile failures, not behavioral RED. No missing fixture may skip these tests.

The nine tests require actual model load/runtime version, explicit CPU config,
partial evolution, <=15% normalized clean-sample WER plus exact final plural
word, all-source sample accounting, endpoint/reset without duplication,
cancellation/fresh stream, repeated finish, invalid/discontinuous input,
duplicate start ownership and explicit missing-model errors. This smoke sample
does not pass the broader clean/representative corpus targets. A network-denied
test process after dependency/fixture preparation should independently exercise
the same real inference tests; a CPU setting alone does not prove execution
provider selection. Review the pinned native provider path and actual runtime,
and keep iOS offline/CPU evidence pending until exercised there.

## Integration limits

The four-file low-level value deliberately avoids calling the still-no-op T09
manager during inference RED, which would mask native behavior. Production
composition must map an acquired VerifiedModel under a held ModelLease into the
adapter, release only after worker/native teardown, and block recording if real
model load fails. That composition, actual converted audio delivery, finalized
transcript persistence/global timing and UI updates require their own test-first
work. No inference double or recording-only fallback may establish readiness.
No iPhone performance, locking, Action Button, signing/renewal, representative
accuracy, two-hour endurance or summary capability follows from this draft.
