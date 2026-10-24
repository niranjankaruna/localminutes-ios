# T13 app-owned metrics: inactive test-first draft

Three cases are pending activation, SDK compilation, hosted RED and behavior.
No active source, workflow, project, state or existing test is changed here.

1. `testDefaultServicesRetainOneLiveRecorderWithActualBuildAndModelPins` requires
   the real default Services recorder and the exact same instance in Live, with
   source/build identity from the built app and model/runtime pins from the real
   immutable speech manifest. It uses an owned root and no installed model.
2. `testAppScenePhaseControlRecordsTruthfulBoundedVisibilityCheckpoints` exercises
   the actual app control boundary, explicit scene-phase mapping and 128-entry
   bound. Its zero sample counts cannot establish inference or lock progress.
3. `testAppPersistsProtectedAtomicMetricsJSONAndExportsOnlyValidatedFacts` uses
   real SQLite sentinel rows, actual policy-protected JSON replacement and an
   open first-inode reader. It checks POSIX permissions, real backup exclusion,
   round-trip schema, exact export bytes, no temporary files, and no content/path
   leakage. SDK protection metadata is reported honestly; physical encrypted
   access remains NOT_RUN when the Simulator cannot establish it.

Activate the Swift file as `Tests/NativeAppTests/NativeAppMetricsTests.swift` and
apply only the minimal declarations in `ACTIVATION_PATCH.md`. The current
XcodeGen `LocalMinutesAppTests` target already includes this directory. Keep
test discovery mandatory in both native test-log and xcresult reporters; add the
three exact names and increase the expected native suite count by three. Missing
source settings, compile/tool errors, zero tests or nil fixtures are not RED.
The new no-op APIs must reach explicit behavioral assertions before implementation.

## Exact source identity and native build wiring

The existing app and extension Info definitions already contain
`LocalMinutesSourceCommit: $(LOCALMINUTES_SOURCE_COMMIT)`. Keep this explicit
build setting and pass `LOCALMINUTES_SOURCE_COMMIT="$GITHUB_SHA"` to every
device, simulator, build-for-testing and native test build. Existing workflow
calls already do this; verify rather than add another inconsistent identity.

Add meaningful assertions to the actual native product tests for **both** built
configurations: app and the single embedded extension source values must equal
the current full 40-character `GITHUB_SHA`. The existing packaging tests assert
device archive stamps, but current simulator product inspection does not assert
the source stamp. These native product assertions need their own auditable
test-first activation/RED if introduced as a new behavior requirement. Native
XCTest then checks the retained recorder equals the actual host app bundle's
stamp, not a test-only fabricated identity. Do not place runtime source identity
in `ProcessInfo` environment alone, and never fall back to all-zero/unknown pins.

Retain the existing app bundle ID `com.niranjankaruna.localminutes` and extension
ID `com.niranjankaruna.localminutes.LiveActivity`, with one application and one
Live Activity extension. No new app/extension target, entitlement or signing
claim is needed.

## Limits and next coverage

Direct `recordScenePhase` tests do not prove the actual SwiftUI root forwards
scenePhase notifications. Add covered app-entry binding separately before
claiming it. `.background` is an app visibility fact and is never renamed
`deviceLocked`. This draft does not establish periodic/background persistence,
crash-safe checkpoint cadence, export share-sheet behavior, phone protection,
locked live transcription, Action Button behavior, renewal or either 125-minute
owner-run pass. Existing real-CPU metrics integration remains separate evidence.
