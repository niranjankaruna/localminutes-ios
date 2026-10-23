# ADR 0003: Live Activity ownership and recording intents

Status: primary API research and T06.1 test-contract preparation only. No intent,
ActivityKit adapter, availability, free-signing or locked-start result is claimed.

Apple's [AudioRecordingIntent contract](https://developer.apple.com/documentation/appintents/audiorecordingintent)
requires a Live Activity to start with audio recording and remain active while
recording. The app-owned resource controller must therefore reject unavailable
or failed activity preparation before reporting recording readiness. The existing
RecordingCoordinator remains the recording state authority. An activity resource
snapshot is not evidence of microphone or transcription readiness.

[LiveActivityIntent](https://developer.apple.com/documentation/appintents/liveactivityintent)
documents launching the app process to perform an activity action without opening
the app. Apple's [interactive widget guidance](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities)
also specifies app-process execution for this intent type. Recording start/stop/
toggle actions should route through the same app owner used by foreground UI;
neither a widget process nor a view creates a separate engine/coordinator. The
actual declarations and metadata must compile in our pinned SDK, including the
iOS18 deployment target, before availability is reported as verified.

The intended start action adopts both recording and activity semantics. Standard
activity requests use [request(attributes:content:pushType:)](https://developer.apple.com/documentation/activitykit/activity/request(attributes:content:pushtype:))
with pushType:nil. There is no push server or paid push entitlement requirement
introduced by this design. Native free extension signing still requires T07
phone evidence; API documentation cannot establish signing feasibility.

Resource ownership is per session and per actual handle identity. Duplicate
requests must reuse the active resource, competing/stale commands must not affect
it, and old observer callbacks must not affect a later resource even if a caller
reuses a session UUID. End acknowledgement follows the actual asynchronous end,
with no update resuming after end and changing the replacement resource.

[ActivityState](https://developer.apple.com/documentation/activitykit/activitystate)
distinguishes active, stale, pending, ended and dismissed. Stale content can be
updated; it is not a terminal state. Pending is not yet started; ended/dismissed
cannot establish initial recording readiness. Unexpected terminal loss must be
reported to the recording coordinator for explicit capture cleanup. Normal
activity content contains only generic status; it exposes no transcript, title
or confidential text on the Lock Screen by default.

Action Button assignment, warm background start, locked cold-start and an
unlock-required foreground fallback are separate device procedures. None is
proved by these documented protocols. The owner alone can waive the desired
locked cold-start experience. The two long locked live-transcription runs and
in-place renewal remain mandatory completion gates.
