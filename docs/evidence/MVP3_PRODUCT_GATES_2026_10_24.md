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

PENDING. Complete real app-owned UI wiring after RED, run focused regressions,
review privacy/lifetimes, retain source/run evidence. Physical permissions,
snapshot/VoiceOver, Action Button and endurance gates stay NOT_RUN.

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
