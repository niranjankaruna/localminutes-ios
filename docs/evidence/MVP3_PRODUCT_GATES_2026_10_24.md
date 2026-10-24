# MVP3 product gates — tests first

Tasks: T20.1 root privacy, T06.3 authenticated latest-meeting shortcut,
T13.3 measured active-recording progress. Requirements R06/R12 and Goal6.1/11/15.

## RED preparation

Four Core RecordingProgressPresenterTests require monotonic first-PCM elapsed
time independent of presenter recreation, actual pending-sample backlog,
strictly-above-five-second warning, catch-up and missing/invalid observations.
The interface currently returns only nil/unknown.

Two NativeRootPrivacyTests host an actual SwiftUI root in UIWindow. They
require synchronous scene-scoped opaque coverage, inaccessible underlying
content, safe foreground restoration and continued app-owned synthetic capture
into real CAF. The privacy controller currently attaches no observers or cover.
This does not prove a physical app-switcher snapshot or locked-screen capture.

Five NativeOpenLatestMeetingIntentTests exercise actual SQLite ordering,
retained application routing, empty/closed/cancelled state, local authentication,
foreground policy and fourth discoverable shortcut. Router/intent return
unavailable stubs, application routing seam is nil, and registration still has
three shortcuts. Existing recording intent SDK assertions remain, with the
fourth shortcut requirement added. One NativeRecordingProgressTests case
composes actual retained app metrics with injected counters; no microphone/ASR
result is inferred from it.

Hosted command: workflow core-tests.yml mode=mvp3, exact pushed source.
Only progress/metrics Core checks and these native classes plus the original
SDK shortcut check execute. No model inference/full suite/package is requested.
Actual portable RED: source677b477f346292e6922f5995997cf28b84143f4b,
run40133352703/job120989603428. Eleven executed: seven existing metrics PASS,
four progress cases FAIL with15 assertion failures, zero skips (1.159s total).
Expected known elapsed10/lagging/processing/caughtUp and measured backlog were
nil/unknown from the no-op stub. This is a behavioral failure after successful
native compilation. Test-first source was pushed before implementation.
Progress implementation is now authorized by this actual RED. Native job
120989603247 failed compilation, zero executed tests: IntentResultContainer.value
is String?, and the new privacy-of-reply assertion called contains without
unwrapping. Correction uses XCTUnwrap, strengthening missing-value failure;
no assertion or privacy rule is removed. This is not native behavioral RED.
Native privacy/latest-shortcut/app composition behavior remains a no-op until
their assertions execute in the corrected focused run.

## GREEN and review

C10 source8edff56a96f051587d727812239937ccba51b9a5/run40134199884:
portable11PASS/0fail/skip0.108s, including all4 progress cases; actual native
metrics-composition case PASS. The separately compiled native9 cases executed:
1PASS,8FAIL,28 assertion failures,0skip0.952s. OpenLatest5FAIL18assert,
privacy2FAIL9assert, original shortcut SDK case FAIL1assert (three versus four).
Missing opaque cover/accessibility shielding and unavailable/nil navigation
are genuine behavioral RED; real SQLite/CAF fixtures execute successfully.
This is the first valid native RED, after preserving C9's compile-only failure.

After owner resume, three explicitly configured GPT-6.1 Sol Medium agents
implement the native root privacy boundary, authenticated retained router/UI
shortcut and same-source ASR-only build candidate. No original assertions are
weakened. Native implementation GREEN, ASR native build/link/model integration
and consolidated release validation remain PENDING. Physical permissions,
snapshot/VoiceOver, Action Button and endurance gates stay NOT_RUN.

## Model-control accessibility test-first slice

Two ModelBrowserAccessibilityUITests mount the actual Models view/controller
through a DEBUG-only isolated fixture. Two tiny checksum-verified synthetic
installations are list/control boundaries only: no model is equipped, evaluated
or downloaded, and no inference result is claimed. Tests require four distinct
spoken Equip/Remove labels including purpose and displayed repository identity,
plus reachable enabled controls with44x44-point targets at AX5. Production
labels and hit-region behavior remain unchanged until actual hosted RED.
The existing compiled Release/Debug fixture-boundary gate now includes the
new fixture markers. Static script checks are not native RED or GREEN.

The next bounded run also builds an ASR-only same-version native candidate;
the root app package remains on the verified current engine until that build's
actual artifacts, hashes and symbol receipts are reviewed. No release artifact,
model integration, final a11y result or native linking is inferred from a script.

## Prior delivery

MVP2 source35c7cefb946af188f5cc09858dca4ab180d72eab/run40132528745:
309focusedPASS/0fail/skip; IPA, source and checksum verified. New test-first
stubs belong to the next version; they do not change the delivered IPA.

## Native dependency hygiene — actual artifact RED

New scripts/native-hygiene-tests/test_no_unused_tts.py audits the real delivered
35c7 IPA without extraction/modification. On Windows bundled Python: three
cases, two PASS (exact source/receipt/SHA/CRC/canonical ZIP, defined CPU ASR
entrypoints retained), one FAIL (21 defined non-STAB TTS symbols:18eSpeak +3Piper),
zero skips,0.330s, exit1. Actual package SHA matches the delivery record. Full
output remains ignored at .agent-local/native-hygiene/35c7-macho-red.log.
Initial empty-symbol-table parser setup failure executed zero cases and is not
RED; parser correction permits legitimate empty tables while retaining required
CPU recognizer entrypoint checks. No stripping/relicensing/runtime replacement
is an acceptable way to manufacture GREEN. Source/build inventory and actual
CPU model regressions remain required after any ASR-only rebuild.

Root repeated this three-case actual artifact audit at pushed test source
d6efa438161bfe23079e6409707fe127201e74c0:2PASS/1FAIL/0skip,0.316s, exit1.
Both controls passed,21 defined TTS symbols remain. Exact source log stays
ignored at .agent-local/native-hygiene/d6efa43-red.log. This confirms RED before
the separately prepared same-revision ASR-only dependency repair.

## C11 actual result and next integration batch

Sourceb26b89dda04c49c0742417179f79b1c2aa762654/run40135661801:
ASR-only build SUCCESS; portable focused job SUCCESS. Both native product/UI
jobs failed compilation before executing tests: RecordingPrivacyRoot transferred
the non-Sendable Notification into MainActor.assumeIsolated. First repair extracts
only Boolean event/scene facts before that synchronous boundary; all original
scene, accessibility and capture assertions remain. This is not new behavioral
RED or native GREEN, and model-button labels remain unchanged pending actual RED.

Actual source-built iOS device/simulator and publisher macOS no-TTS frameworks
were produced and independently reviewed: archive20,879,035bytes,
SHA1ba515336274ceae21bbdbbbde0076d8865b04c7082b0623b260800e76d090e7;
receiptSHA84a352eb11b1190caefe7b0562b42c90b875828a84628b3724924cbdad5d52f1.
All13 file hashes, ZIP CRC, expected three platform entries/five architectures
and source pins matched. Native symbols retain CPU recognizer controls and no
defined eSpeak/Piper. Actual app linking/inference/final IPA audit remain pending.
The successful build took roughly five minutes, so jobs use platform-specific
source preparation; the unactivated cache draft is preserved, not reported GREEN.

The next batch adds test-first nil/unknown seams for source-segment navigation,
actual app version/build and database-derived content status; actual screen tests
exercise the missing bindings. Production defaults are also tested against the
mandatory CPU-only policy before changing the current ANE-enabled default.
Fixed public three-speaker clean/15dB-noise WER and one real Phi multi-map/refusal
evaluation are pending actual native results; no quality pass is inferred.

Library UI seeding is test-harness bootstrap only. A separately named old-source
8edff56 baseline job preserves actual nil-fixture failure, while current UI tests
exercise real isolated SQLite/CAF and retain original data/edit/isolation oracles.
Only obsolete Qwen settings expectations are reconciled with the owner's current
model browser. No product RED is inferred from missing fixture setup.

## C12 terminal checkpoint

Run40138806203 at14ff749a2bd8678b6523cf377b6695283513a76e is terminal
FAILURE. Core, current Phi and native product jobs stopped before tests because
the local package declared Swift tools5.9 while using iOS18/macOS15 platform
constants introduced in newer PackageDescription. No new current behavior RED,
quality outcome or app linking/IPA result is inferred. The accompanying llama
artifact mapping diagnostic followed the invalid dependency manifest; a distinct
llama defect is not proven. First repair sets the local tools declaration6.2,
matching the root/dependency toolchain. Preparation now validates the local
manifest, and the Phi job builds test code before downloading weights.

The independent, explicitly old-source8edff56 library harness did execute:
3tests,3failures,0unexpected/skip,64.008s. Each fails at actual product home
initialization with the original nil fixture. This is harness-only failure
evidence; the real SQLite/CAF seeding candidate still needs its successful UI
run. It is not evidence that current product interactions passed or failed.

Six of six runs in the carried bounded invocation are consumed. No seventh run
is dispatched. Corrected metadata/build ordering and all pending tests remain
reviewable/persisted; remaining nil/unknown product seams and CPU/ANE default
are not implemented before their actual behavioral RED. The next legitimate
bounded invocation must first prove compatible native compilation, then record
actual remaining RED/GREEN and model results before completing MVP3. Existing
MVP2 source35c7 delivery and all physical NOT_RUN gates remain unchanged.
