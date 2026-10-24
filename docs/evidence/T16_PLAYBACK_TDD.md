# T16 native playback versus recording ownership — test first

## Actual pending/scoped regression RED, 24 October 2026

Source `917844b016664251c545fb70106c50cfceb62694`, terminal failed run
[40071855360](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40071855360),
native job `120806812220`: device/simulator and test compilation succeeded;
57 app-hosted cases executed, 54 passed, three new playback cases failed with
24 assertions, zero unexpected/skipped. All eight original playback tests
passed. Global Stop and caller cancellation wrongly allowed the pending player
to activate; the scoped-request API returned notImplemented. These actual
behavioral failures were read before authorizing repair.

All five supported storage-policy cases passed, including the strict SQLite
sidecar-retirement/recreation assertions after the controlled fixture correction.
Recording UI three of three passed, zero skipped; final reporter/xcresult
verification is recorded separately. Seven unchanged physical protection cases
compiled for iPhoneOS, executed zero, explicitly NOT_RUN. Packaging did not run
after native failures; no IPA was retained.

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


Terminald699fc5/run40069154630: actual54app-hostedcases53pass1fail1assert0skip; all8newplaybackcontractsGREEN, fourstoragecasesGREEN. SQLite-sidecarcasefailedonlyautomaticunlinksetupassert; allsubsequentrealdata/permission/backupassertionspassed. FixturecorrectionusesactualcheckedTRUNCATEcheckpoint/PERSIST_WAL0/DELETE/synchronouscloseandWALre-enable; no manualWALdeletionorweakenedassertion. All3UIcasespass/xcresultagrees (178.94s caseexecution). Physical7strictassertionscompiledforiPhoneOS,EXECUTED0/NOT_RUN,unchangedhash. Packagingstepsskipped;noIPA. FullworkflowFAILED(core6failandQwen3failalso).


Terminal39d9eaa/run40073883889: ALL57native cases passed (includingall11playback), UI3/3pass, strictreportersandxcresultagree, physical7compiled/0executedNOT_RUN. Existing4realQwenqualitycasespass. FullworkflowFAILED fromnewcore16/counter/capacity andtwooldscope/fixtureassertions. Nativeproductinspection devicecasepasses; simulatorcasefailsbecausewithin-workflowDebugreuseallowsXCTesttoembedLocalMinutesAppTests.xctestbesidetheappex beforelateinspection. PreserveexactPlugInsallowlist andmovecompiledproductinspectionbeforeunitinstrumentation; doNOTignore/deleteunexpectedbundles. Actualnativejobtook~25.5min, sonextnativejobbounded35min(<45spec), samefreestandardpublicrunner/noextra infrastructure. NoIPApackage/retention/devicepass.
