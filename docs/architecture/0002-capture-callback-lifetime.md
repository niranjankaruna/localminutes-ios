# ADR 0002: callback admission and capture shutdown

Status: T05.3 tests-first preparation. No gate/runtime implementation or native
RED/GREEN is established by this decision. Microphone/device validation is pending.

Apple documents off-main taps, one tap per bus, variable actual buffer sizes,
and removal during engine operation. The reviewed stop/removeTap documentation
does not promise callback join or non-overlap. Treat engine stop/removal as
hardware requests; independently establish callback admission and quiescence.

Keep one stable callback context per capture epoch. Its single atomic admission
state must linearize entry against close, reject a concurrent callback before
it can touch the SPSC queue, and publish the end of an admitted copy. Entry
acquires the previous callback's release so sequential callbacks on different
threads retain the single-producer memory ordering. Closing prevents new entry;
the owner acquires closed-and-quiescent before finishing the queue. Separate
unsynchronized closed/count observations cannot establish that invariant.

The eventual tap explicitly uses a Sendable closure capturing this owned context.
It checks actual frame count/format and sample-time validity, then copies through
the queue. No Task, actor, array allocation, conversion, persistence or mutex
belongs in that callback. Overflow, overlapping input or invalid/discontinuous
time must trigger an explicit gap or clean interrupted stop outside the callback.

Shutdown order: close admission, stop/remove the hardware tap, wait outside the
callback for an admitted copy to finish, finish/drain the queue, finish real
conversion and durable writing, deactivate the session, then acknowledge
coordinator cleanup. A retained old callback must keep its closed context alive
and reject work after a newer epoch exists.

Test paused admitted work versus stop, late/replayed callbacks, overlapping
callbacks, sequential reuse, duplicate close/invalid release and real concurrent
entry/close. Hardware/permission may be doubled at their boundary; synthetic PCM
must still exercise actual queue, conversion and CAF writing in later runtime
tests. This does not prove a live microphone or locked phone behavior.

Read actual formats after session activation; preferred sample rates are hints.
Use the supported AVAudioApplication permission path and an appropriate measured
AVAudioSession category/mode. First-buffer readiness and failures must reach the
app-owned coordinator; no success before its three readiness gates.

Primary sources reviewed on 23 October 2026:

- [Tap contract](https://developer.apple.com/documentation/avfaudio/avaudionode/installtap(onbus:buffersize:format:block:))
- [Engine stop](https://developer.apple.com/documentation/avfaudio/avaudioengine/stop()) and [removeTap](https://developer.apple.com/documentation/avfaudio/avaudionode/removetap(onbus:))
- [Apple DTS Swift 6 tap guidance](https://developer.apple.com/forums/thread/793455)
- [Record permission](https://developer.apple.com/documentation/avfaudio/avaudioapplication/requestrecordpermission(completionhandler:))
- [Actual versus preferred session format](https://developer.apple.com/library/archive/qa/qa1631/_index.html)
- [Audio timestamp validity](https://developer.apple.com/documentation/avfaudio/avaudiotime)
