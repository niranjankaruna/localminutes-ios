# Native application signal-wiring test-first draft

Inactive `.swift.pending` fragments only: uncompiled/NOT_RUN, no production or CI
change. Native monitor component tests alone do not establish app retention or
that an App Intent's completed start still receives native notifications.

Exactly two cases:

- `testNativeApplicationRetainsSignalObservationAfterStartReturnsAndInterruptsActualCAF`
- `testNativeStaleAppStopCannotDetachReplacementSignalObservation`

The fragment appends after the final `#endif` of
`Tests/RecordingTests/RecordingSessionOwnerTests.swift`, reusing its private real
owner/queue/conversion/CAF harness. Only preparation/permission/hardware/Activity
boundaries are doubled. An isolated actual NotificationCenter posts the actual
AVAudioSession interruption/media-reset names; the tests instantiate no monitor.
The first calls the actual Start intent and requires application-retained routing
after Start returns. The second exercises actual scoped Stop through the app,
then a stale Stop while a replacement records; the replacement must still react
to media reset. Both decode actual64-frame CAF and prohibit Saved/completed.

Activate the companion within-class interface fragment only: an optional unused
notification-center dependency on the injected owner initializer and a no-op
`flushSignals()`. Preserve all old initializer calls and all assertion bodies.
No production monitor creation, epoch binding or notification route before a
pushed test-first source proves compatible native assertion RED.

After RED, default-services and injected-owner construction must share the same
retained monitor setup, rather than creating a test-only route. Binding belongs
to the actual app/owner epoch, never a transient view or an intent's temporary
Task. Stale Stop/end commands must not detach a replacement, and flush must join
already-admitted events. Before-recording permission/preflight signal timing,
default-root identity assertions and any observer lifetime beyond the two tested
interleavings need their own coverage if the chosen implementation changes them.

These tests do not establish physical OS delivery, locked operation, a real phone
media-server reset, ASR quality or either125-minute pass. Root must add both names
to strict native reporting and preserve all earlier tests. No model/network
fixture or new runtime dependency is needed. Compile/setup failure is not RED.
