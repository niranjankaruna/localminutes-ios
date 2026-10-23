# Native control SDK boundaries

Checked against Apple's primary documentation on23 October2026. These API
notes are design inputs, not execution or physical-device evidence.

- [systemContext](https://developer.apple.com/documentation/appintents/appintent/systemcontext)
  is an AppIntent instance property. Modern foreground continuation must inspect
  its current execution mode and whether foreground continuation is available.
- [Modern foreground error](https://developer.apple.com/documentation/appintents/appintent/needstocontinueinforegrounderror(_:alwaysconfirm:))
  is available from iOS26. Use its explicit alwaysConfirm label to distinguish it
  from the legacy overload. A request can still be rejected by the OS.
- [Legacy foreground error](https://developer.apple.com/documentation/appintents/foregroundcontinuableintent/needstocontinueinforegrounderror(_:continuation:))
  supports iOS16.4 through25 and is unavailable to app extensions. An explicit
  continuation label selects this compatibility API. Keep it in app-only code.
- [Runtime behavior](https://developer.apple.com/documentation/appintents/configuring-the-runtime-behavior-of-your-app-intents)
  documents foreground defaults for some system intent protocols. The hidden
  session-scoped Activity Stop therefore needs an actual SDK mode test; its
  unactivated RecordingActivityExecutionTests.swift.pending is a future probe,
  not a passed assertion. Do not change that declaration before recording a
  meaningful test-first result, or assume extension delivery from direct calls.
- [System timer Text](https://developer.apple.com/documentation/swiftui/text/init(timerinterval:pausetime:countsdown:showshours:))
  accepts a closed date interval and an optional pause time. Content date tests
  do not establish actual Lock Screen rendering or background behavior.

The37 app-hosted cases executed at81960fd/run40020680067:24previous passed,
13new failed82assertions,0skipped. Their covered production behavior is now being
implemented. UI did not run before job cancellation and has no RED yet; the
Text-only screen stays unchanged while three UI contracts await actual execution.
The newly activated hidden Stop mode probe increases proposed app-host count to38;
its declaration remains unchanged until the probe's real SDK result is observed.

That run completed assertions in about33seconds but xcodebuild returned only after
substantial startup/result-processing delay. The next native job is bounded25min
(below configured45), and uses Apple's documented collect-test-diagnostics never
option to avoid unrelated failure diagnostic collection. Assertion exits, all
expected test IDs, .xcresult summaries, and regression requirements are preserved.
See [Apple's diagnostic collection guidance](https://developer.apple.com/forums/thread/698054).
No sanitizer setting was removed. No diagnostic/archive uploads are added.
