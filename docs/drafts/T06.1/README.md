# T06.1 Live Activity resource drafts

Status: **uncompiled, NOT_RUN**. These .swift.pending files are excluded from
active Swift package/Xcode paths. The controller interface is a no-op stub.
There is no ActivityKit adapter, RED/GREEN evidence, entitlement or phone result.
Root owns activation, test-first commit/push and hosted behavioral RED before
any lifecycle implementation.

The proposed platform-neutral Core interface is MainActor-owned. Its backend
and handle protocols are the only test doubles. Request is synchronous/throwing;
update/end are async to match the real SDK. Caller-supplied status is display
content projected from RecordingCoordinator, not another recording state
machine. Events report actual resource readiness, unavailability, unexpected
loss and cleanup acknowledgement. They cannot assert microphone, transcription
or recording success.

Nine focused tests cover disabled/throwing/non-active requests, same-ID reuse
and competing-ID rejection, matching update/end and stale commands, outdated
content that remains owned, terminal loss, delayed end completion, old callbacks
after same-ID replacement, and update/end serialization. Native end must settle
before acknowledgement; an early ended observation is insufficient. An admitted
async update must settle before native end, and later updates are ignored.
All async test waits are bounded to one second; fake SDK continuations are
released on every exit. No devices, fixture recordings or external accounts are
touched.

Apple documents synchronous Activity.request, async update/end, current state
and activityStateUpdates in [Activity](https://developer.apple.com/documentation/activitykit/activity).
The real iOS adapter must wrap those operations and Shared/RecordingActivityAttributes
with no required push server or remote inference. It must retain/cancel its
state-observation task safely and suppress callbacks from retired handle epochs.

Apple distinguishes outdated stale content from terminal ended/dismissed states;
pending has not started. See [ActivityState](https://developer.apple.com/documentation/activitykit/activitystate).
The tests do not treat stale content as termination. Pending/ended/dismissed
initial handles cannot qualify readiness. Returned non-active handles remain
owned until an explicit end settles. The later adapter normally uses nil
staleDate; SDK availability/mapping remains subject to the pinned native build.
The SDK pending case requires iOS 26.0; an eventual adapter supporting iOS 18
must guard that case's availability rather than reference it unconditionally.

People can disable Live Activities and request can still fail when enabled.
Check actual [ActivityAuthorizationInfo](https://developer.apple.com/documentation/activitykit/activityauthorizationinfo)
and handle SDK errors. Foreground versus App Intent starting rules, extension
signing with a free Apple Account, actual Lock Screen presentation, Action
Button, audio/background coupling and physical-device persistence remain pending.
No UI, intent, activity resurrection/reconciliation or inference is included.
