# T06.2.2 native app and intent contract drafts

The original .swift.pending files below remain outside active targets as the
reviewed proposal. Root activated their test/interface contents at 81960fd,
including two additional cancellation/overlap cases, three Activity content cases
and one separate UI case. Run40020680067 has passed existing core regressions
and compiled device/simulator app and extension products. Native app-hosted and
assertions actually ran:37executed24previous passed13new failed82assertions,
0skipped. Its result bundle agrees; later15min timeout prevented UI execution.
Root is implementing only the observed app/intent/content contract. GREEN,
foreground OS transition, Shortcuts registration, free signing, physical
recording and inference remain unverified. Three UI contracts and the extra
hidden Stop mode probe now await their own execution; Text-only UI and the
hidden Stop declaration's mode remain unchanged before that evidence.

Continuation update:7c1ae7c/run40024451125 passed38 actual app-hosted cases,
including the original37 and actual inherited background-mode probe. UI3cases
then failed on absent controls,3assertions0skip, before view implementation.
Root has now implemented their controls and DEBUG-only shared-view fixtures;
GREEN awaits the next exact source. A newly added native preparing-toggle
regression is not executed and the corresponding coalescing repair is forbidden
until its real RED. Next expected39app-hosted+3UI. Original pending files below
remain the historical proposal, not current production sources.

## Exact file integration proposal

| Draft | Eventual active location |
| --- | --- |
| RecordingApplication.swift.pending | App/RecordingApplication.swift |
| RecordingAppIntents.swift.pending | App/RecordingAppIntents.swift |
| StopRecordingActivityIntent.swift.pending | Shared/StopRecordingActivityIntent.swift |
| LocalMinutesApp.swift.pending | Existing App/LocalMinutesApp.swift identity interface, preserving placeholder UI for UI RED |
| NativeIntentTests.swift.pending | Append to existing Tests/RecordingTests/RecordingSessionOwnerTests.swift, in the SAME file |

Use spec names StartMeetingIntent, StopMeetingIntent and ToggleMeetingIntent.
The separate StopRecordingActivityIntent is a hidden, session-scoped Activity
control, not a fourth public shortcut. OpenLatestMeetingIntent is still required
by the baseline and remains an explicit follow-up tied to actual meeting history;
three shortcuts do not complete the specification's intent requirements.

RecordingApplication is MainActor-owned. The minimal stub has a nil default
owner, a nil lastOutcome and an injected initializer that only retains the
concrete RecordingSessionOwner and optional OS foreground boundary. Its perform
always throws NotImplemented. Default root and default intent values resolve
one shared application, but no default resource composition exists yet.

All AppIntent perform stubs always throw. Each declares the shared concrete
RecordingNativeResult typealias:
IntentResultContainer<String,Never,Never,IntentDialog>. The stub's typed
.result(value:dialog:) is unreachable after an always-throws Void helper.
Native tests capture actual returned values/dialogs as well as errors; the stub
should yield explicit XCTest assertion failures, not merely uncaught errors.
No dispatch, UUID parsing, fallback or model readiness is implemented. The empty
Shortcuts provider intentionally fails the three-entry assertion.

## Public result contract

Private lastOutcome is diagnostic only; it cannot communicate a failed start
to the Shortcuts user. Every returned native result must contain the same
truthful, user-readable message as its String value and localized IntentDialog.
The native tests inspect actual result.value and nonnil result.dialog, alongside
the existing real owner/media/error assertions:

| Resource outcome | Returned value and dialog message |
| --- | --- |
| Model unavailable | A verified speech model is required before recording. |
| Preparing | Preparing recording. |
| Recording | Recording is active. |
| Saved after successful cleanup | Recording saved. |
| Stale Activity control | This control belongs to an earlier recording. |
| Cleanup pending | Stopping is still pending. Open LocalMinutes. |
| Foreground attention required | Open LocalMinutes to review recording permissions and status. |

After RED use one localized message policy for both the returned String and
IntentDialog. Set the native test action language/region to English/US for these
assertions. Do not produce success merely because perform returned without an
error. A rejected foreground request must throw and return no result; its
latched failure remains visible on the real owner. Preserve a per-call outcome
across awaited foreground work rather than deriving the reply from a later
call's mutable lastOutcome.

Apple publicly exposes IntentResult.value and the concrete result container's
dialog property on iOS16+. IntentDialog has no documented public text/equality
getter. These tests verify the real returned value and dialog presence; they do
not claim to decode the SDK dialog text. Do not use reflection or
String(describing:) to inspect it. Keep the localized presentation policy itself
testable when its behavior is implemented.

## Owner harness and native test target

Change only the existing owner's test imports to this target-aware selection:

```swift
#if SWIFT_PACKAGE
import LocalMinutesCore
@testable import LocalMinutesRecording
#else
@testable import LocalMinutes
#endif
```

Keep existing Foundation/XCTest/AVFoundation/AudioToolbox imports and all owner/
router assertions unchanged. Append the native extension in that SAME source
file, since its bounded helpers and OS fixtures are private. It is guarded by
`#if os(iOS) && !SWIFT_PACKAGE`; package tests do not compile native SDK cases.

Add a LocalMinutesAppTests target to project.yml:

```yaml
LocalMinutesAppTests:
  type: bundle.unit-test
  platform: iOS
  deploymentTarget: '18.0'
  sources:
    - Tests/RecordingTests/RecordingSessionOwnerTests.swift
  dependencies:
    - target: LocalMinutes
  settings:
    base:
      PRODUCT_BUNDLE_IDENTIFIER: com.niranjankaruna.localminutes.AppTests
      GENERATE_INFOPLIST_FILE: 'YES'
      CODE_SIGNING_ALLOWED: 'NO'
```

XcodeGen infers TEST_HOST from the app dependency. Do not add Core/Recording/
Shared sources a second time to the test bundle. Add this test target to the
LocalMinutes scheme build as [test], and its Debug test action targets with
parallelizable:false. Preserve the Release archive action and bundle IDs. Verify
Debug app testability for @testable import. Do not add signing credentials.

There are EIGHT native methods, plus the existing owner/router methods from
that source. At this draft's creation there are 24 existing methods, proposing
32 app-hosted XCTest cases. Recount the actual source at activation; no executed
discovery count is claimed. XCTest process return/exit and result-bundle totals
must agree, with all expected case identifiers and zero skips. A simulator boot,
compiler error, missing test host or zero tests is not meaningful RED.

The proposed cases cover default shared identity/model-unavailable rejection;
real owner start/readiness/duplicate behavior; actual CAF stop/cleanup; native
toggle stop/later start; shared parameter storage and malformed/stale/matching
scoped stop; failed-end cleanup retry; rejected foreground transition; and real
SDK conformances/provider modes. Only the existing hardware/permission/Activity/
model-preparation OS boundaries and the foreground-transition boundary are
doubled. Real owner/coordinator/queue/converter/CAF code executes after dispatch
implementation. No fake recognizer is introduced or claimed present.

## Shared extension target boundary

The existing app and extension both include Shared. Define only the extension's
SWIFT_ACTIVE_COMPILATION_CONDITIONS with inherited values plus
LOCALMINUTES_EXTENSION. The shared file's extension branch then has no reference
to RecordingApplication, an engine, a file writer or a coordinator; perform fails
closed with applicationUnavailable. The app branch must later route valid UUIDs
through the app-held owner. An empty or malformed required session string must
fail as invalidSession, never become an unscoped stop. Populate it from the
Activity attributes' meetingID.uuidString when adding Button(intent:) in the
Lock Screen and expanded presentation after the relevant RED.

Both app and extension must compile the actual AudioRecordingIntent and
LiveActivityIntent declarations at deployment iOS18. Shared Stop deliberately
does not adopt ForegroundContinuableIntent; no application-only foreground API
belongs in extension compilation. Its errors may direct a person to open the
app without constructing another capture lifetime. Normal LiveActivityIntent
OS execution is documented as app-process routing, but simulator direct perform
tests cannot prove real extension delivery, locked dispatch or installed signing.

## Foreground fallback and metadata after RED

The app-only Start/Stop/Toggle declarations guard supportedModes at iOS26 and
include Apple's documented deprecated ForegroundContinuableIntent compatibility
conformance. They do not yet call either foreground API. After native RED,
production must use the actual intent context and guarded iOS26 API, or the
legacy iOS18-compatible continuation API. The optional injected foreground
boundary exists only to observe/fail the OS transition in deterministic tests.
Check canContinueInForeground on iOS26; a denied/unavailable transition cannot
be turned into recording success. Preserve lastOutcome before any awaited
foreground request; failure/cleanup facts must remain visible if it throws.
IntentModes publicly conforms to OptionSet and SetAlgebra; the guarded tests'
contains(.background) and contains(.foreground(.dynamic)) use those actual
protocol operations rather than SDK reflection.

The tests intentionally expect modelUnavailable to return a blocked outcome,
without trying to activate resources. Production default preparation must keep
that rejection until verified installed models and actual CPU streaming ASR are
wired. It must not infer readiness from file presence or test injection.

After RED create actual AppShortcut values with Start/Stop/Toggle intents,
localized phrases, short titles and system images. Check real metadata
extraction and packaged metadata separately; the provider count alone is not
proof of Shortcuts or Action Button discovery. Never put transcript/meeting text
in static shortcut metadata or the generic Activity status.

Select an available installed iPhone simulator by UDID from simctl inventory;
record its runtime instead of assuming a device model. Run unsigned xcodebuild
test with a fresh .xcresult bundle. Use Apple's xcresulttool test-results summary
and tests commands to verify actual totals and case IDs even when xcodebuild
exits failed. Keep the failing exit and assertion evidence; test infrastructure
changes require their own regression evidence where applicable. No artifact
upload is needed, and the account's separate storage blocker remains unchanged.

Primary references already researched for this proposal:
[AudioRecordingIntent](https://developer.apple.com/documentation/appintents/audiorecordingintent),
[LiveActivityIntent](https://developer.apple.com/documentation/appintents/liveactivityintent),
[supportedModes](https://developer.apple.com/documentation/appintents/appintent/supportedmodes),
[legacy continuation](https://developer.apple.com/documentation/appintents/foregroundcontinuableintent),
[result(value:dialog:)](https://developer.apple.com/documentation/appintents/intentresult/result(value:dialog:)),
[result value](https://developer.apple.com/documentation/appintents/intentresult/value-swift.property),
[concrete dialog property](https://developer.apple.com/documentation/appintents/intentresultcontainer/dialog),
[IntentModes](https://developer.apple.com/documentation/appintents/intentmodes),
[interactive widget routing](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities),
[XcodeGen 2.46 spec](https://github.com/yonaskolb/XcodeGen/blob/2.46.0/Docs/ProjectSpec.md).

No iOS18 fallback execution is established by an iOS26 simulator run. Action
Button assignment, extension/free-signing installation, locked cold/warm start,
locked live ASR, both125-minute runs and renewal remain physical gates. Overall
baseline and complete native intent/UI/history behavior remain unfinished.
