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
Actual RED source/run/count/assertions: PENDING. Production behavior must not be
implemented until meaningful hosted assertion failure is recorded.

## GREEN and review

PENDING. Complete real app-owned UI wiring after RED, run focused regressions,
review privacy/lifetimes, retain source/run evidence. Physical permissions,
snapshot/VoiceOver, Action Button and endurance gates stay NOT_RUN.

## Prior delivery

MVP2 source35c7cefb946af188f5cc09858dca4ab180d72eab/run40132528745:
309focusedPASS/0fail/skip; IPA, source and checksum verified. New test-first
stubs belong to the next version; they do not change the delivered IPA.
