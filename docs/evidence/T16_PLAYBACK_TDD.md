# T16 native playback versus recording ownership — test first

Eight native cases cover delayed playback after Start/Toggle reservation while
the real coordinator still reports idle, held preparation, active capture,
recording admission after playback, failed player deactivation, held Activity
cleanup and failed capture deactivation/retry. Real queue/conversion/CAF writer
and mapper are used; model preflight, permission, OS activity and playback/audio
hardware are explicit lifecycle boundaries. This is not real inference evidence.

Test file: Tests/NativeAppTests/NativePlaybackOwnershipTests.swift.
Minimal interfaces: App/PlaybackOwnershipController.swift returns notImplemented
after a real snapshot and optional scheduling hook. RecordingApplication's
injected initializer can retain it and delegate calls; the default production
path is still nil. Its no-op admission result is intentionally unenforced until
actual native RED. No working gate or OS player behavior is added here.

Assertions require playback never activate/deactivate after a recording
reservation, admitted playback stop and deactivate before capture activation,
and failed deactivation retain explicit ownership and prevent all preparation,
permission and capture effects. Only an explicit successful retry may release
that ownership. Matching saved manifests/actual CAF bytes are checked.

All eight names are required by the strict native reporter, together with the
two new transcript-finalization owner cases and seven privacy cases. Expected
native total56. Compatible compile/RED and exact pushed source are pending.
No prior test/assertion was changed; no physical-device result is claimed.

Test-first sourcecdf4a06f6a4a9cd226e306941fd0199a18bf418c pushed and remoteHEAD verified before implementation. Hosted run40038154279 active; compatible assertion RED remains pending.


## Actual native RED read on owner resume

Exactcdf4a06/run40038154279 compiledbothactualdevice/simulatorproducts andexecuted56app-hostedXCTest:41pass15fail40assertions(5unexpected)0skip. All8newplaybackcasesfailed againstexplicitnotImplemented/ignoredadmission: staleplaybacknotblocked, playernotactivated/stopped, faileddeactivationadmittedcapture. All7privacycasesfailed:5notImplemented policyerrors, missingdefaultModels/Meetings andbackupflags, nilprotectionmetadata. Existing41nativecasespassed, includingthepreparing-toggle repairandtranscriptfinishbarrier. SeparaterealUI3/3pass,0fail/skip; xcresultagrees. Thisauthorizesmissingpolicy/admissionbehavior; itdoesnotprovephysicalprotection. ThesymlinkfixtureitselfreturnsnilaftersettingCompletebeforepolicy, demonstratingunsupportedSimulatorprotectionmetadata. Preservephysicalassertions/gate; noemulatedattributes orfakepass. FullworkflowremainsFAILED; packagingnotrun.
