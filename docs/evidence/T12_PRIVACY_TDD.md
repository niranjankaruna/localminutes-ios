# T12 persistent-file privacy — native test-first gate

Seven native cases are activated from docs/drafts/T12Privacy/ before policy
implementation. They require actual iOS metadata on default app roots,
verified model imports, SQLite/WAL/SHM/recreation, CAF/checkpoint creation and
symlink safety. No mocked filesystem/inference and no owner meeting data.
The existing ModelStoragePolicy.protectPersistentDirectory still throws
notImplemented. Root/default constructors do not yet establish the policy.

Actual SDK RED is required before implementing protection/exclusion. Compile
failure or absent cases will not count. Hosted simulator metadata cannot prove
physical locking, encryption, backup-network behavior or signing renewal.
All owner-run physical gates remain NOT_RUN. Next: final permitted invocation
run compiles the new native tests, records exact result, then implement only
after meaningful assertion RED and preserve a checkpoint if CI budget is used.

## First compatible run — compiler issue, NOT RED

Exact source7659a1980b53fc17d624973c6666d83084234ab6, run40036438183 is
terminal FAILED. Actual Release iPhoneOS and Debug simulator app/extension
compilation succeeded. Native app/UI test bundles did not compile: the new
fixture used FileManager.setAttributes(_:atPath:) twice; the actual SDK requires
setAttributes(_:ofItemAtPath:). xcresult reports0test cases. This is NOT RED and
does not authorize privacy implementation. The two argument labels are repaired
without altering assertions; policy remains notImplemented.

Continuation07's next test-first run must execute all seven native cases plus
the original lifecycle cases and eight new playback ownership cases. Native
build now runs independently of the core test-first job; core, native and actual
summary jobs are still mandatory and any failure fails the overall workflow.
No mandatory test is skipped or ignored, no artifact is uploaded and no signing
or locked-device result is inferred. Full ignored log:
.agent-local/T12-7659a19-terminal.log.


## Actual native RED read on owner resume

Exactcdf4a06/run40038154279 compiledbothactualdevice/simulatorproducts andexecuted56app-hostedXCTest:41pass15fail40assertions(5unexpected)0skip. All8newplaybackcasesfailed againstexplicitnotImplemented/ignoredadmission: staleplaybacknotblocked, playernotactivated/stopped, faileddeactivationadmittedcapture. All7privacycasesfailed:5notImplemented policyerrors, missingdefaultModels/Meetings andbackupflags, nilprotectionmetadata. Existing41nativecasespassed, includingthepreparing-toggle repairandtranscriptfinishbarrier. SeparaterealUI3/3pass,0fail/skip; xcresultagrees. Thisauthorizesmissingpolicy/admissionbehavior; itdoesnotprovephysicalprotection. ThesymlinkfixtureitselfreturnsnilaftersettingCompletebeforepolicy, demonstratingunsupportedSimulatorprotectionmetadata. Preservephysicalassertions/gate; noemulatedattributes orfakepass. FullworkflowremainsFAILED; packagingnotrun.


## Implementation after actual RED; physical oracle preserved

Root and3boundedagents implementedonlyafter reading/persistingcdf4a06assertions: durableCAF/SQLite recoveryplan/quarantine/globalgaps; owneddeletionjournal/leases; immutablebound-note receiver andrenameepochs; synchronousplayback/startgenerationgate withfailureownershipretained; sharednativepersistentpolicyandatomicprotectedpublication; canonicalpinnedQwen envelope. Sourceisnotyetcompiled/GREEN. UIinputcapturestillawaits3newtest-first reservationcases andnil-returningstub; automaticrecovery/deletionUI/ownerleaseintegrationandfullplaybackremainunfinished.

Theoriginal7NativePersistentPrivacyTests were moved byte-for-byte toTests/PhysicalDeviceTests/NativePersistentPrivacyTests.swift. SHA2563abdf26b1175adc6919065931e9ed13193d5d9e2d45f01bbe73919e43bd37105 matchesgitHEAD sourceexactly. Everyphysicalprotectionassertionremainsstrictandmandatory. NewactualSimulator5casescoverexistingpolicy behaviorusingrealbackupflags/POSIX/bytes/SQLiteWAL/CAF/atomicrename/symlinkfailure. A nilSDKgetterexplicitlyreportsUNVERIFIED; physical7executed0/NOT_RUN isloggedandpersisted, nevercountedaspassing. Dedicatedphysicaltesttarget/schemebuildsforiPhoneOSwithoutsigning/execution. Thisisaplatform-correct harnessrepairbasedonactualindependentnilmetadata evidence, notanacceptancewaiver orsimulatedencryption. Deviceaccess/lock/backupnetwork/renewalstillrequirephoneevidence; ownerneedsnoMacsubscription.

LocalWindows59Node tests passed0fail/skip afteraninitialsandbox-onlysymlinkEPERM; sanctionedunsandboxedrerunpassedunchangedtests. NoSwift/nativeGREENfromthat. CostpolicyofficialsourceandlivePUBLICreporecheckedbeforedispatch; no paidrunners/upload/billingchanges.


Terminald699fc5/run40069154630: actual54app-hostedcases53pass1fail1assert0skip; all8newplaybackcontractsGREEN, fourstoragecasesGREEN. SQLite-sidecarcasefailedonlyautomaticunlinksetupassert; allsubsequentrealdata/permission/backupassertionspassed. FixturecorrectionusesactualcheckedTRUNCATEcheckpoint/PERSIST_WAL0/DELETE/synchronouscloseandWALre-enable; no manualWALdeletionorweakenedassertion. All3UIcasespass/xcresultagrees (178.94s caseexecution). Physical7strictassertionscompiledforiPhoneOS,EXECUTED0/NOT_RUN,unchangedhash. Packagingstepsskipped;noIPA. FullworkflowFAILED(core6failandQwen3failalso).
