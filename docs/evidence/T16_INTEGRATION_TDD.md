# T16 owned deletion and note/selection regressions — test-first

Requirements R08/R11/R12. Ten new cases use actual SQLite and native CAF:
six owned deletion/recovery cases, two immutable note identity cases and two
rename projection races. Tests remain active alongside all existing cases.
Only no-op deletion/usage/bound-note APIs and a nil-by-default post-real-SQLite
read scheduling seam were added. No deletion, admission or race repair exists
before actual compatible RED.

Deletion must remove one confirmed, unused UUID-owned meeting's metadata,
original notes, transcript and audio while preserving other meetings/models.
Reject external/nested symlinks and mismatched session manifests. A real closed
database must prevent any move; a real metadata failure after quarantine must
leave a durable request recoverable by a new coordinator after reopen.

Delayed notes must retain the originating UUID/revision and never alter another
selection's visible data or error. A held rename result must not replace a newer
selection, including A-to-B-to-A where UUID equality alone is insufficient.
Exact source-review findings: docs/drafts/T16Deletion/INTEGRATION_REVIEW.md.

Next: review and push the test-first source after the preceding native run is
terminal, record hosted assertions, then implement. No new test has yet compiled
or established RED/GREEN; existing source assertions were not weakened.
Native editor debounce/navigation and actual recording/playback usage wiring
still require their own integration evidence before handoff.

Test-first sourcecdf4a06f6a4a9cd226e306941fd0199a18bf418c pushed and remoteHEAD verified before implementation. Hosted run40038154279 active; compatible assertion RED remains pending.


## Actual RED read on owner resume

Test-firstcdf4a06f6a4a9cd226e306941fd0199a18bf418c/run40038154279 isterminalFAILED. HostedmacOS/Xcode26.2 compiledandran224corecases:199pass25fail57assertions(7unexpected)0skip. All25newcasesfailed:8actualCAF/SQLiterecovery,6owneddeletion,2boundnotes,2renameepoch and7formattercases. Actualfiles/nativefixturesand original199regressionspassed. Examples: noquarantine/journal/metadata deletion, wrongnote/selectionafterheldSQLite read, notImplemented recovery, emptycanonicalenvelope/no budgetrejection. This isbehavioralRED, notcompile/tool failure. Onlyafterreadingandpersistingthisevidence isimplementationauthorized. Ignoredfull log:.agent-local/TDD-cdf4a06-terminal.log.


Newinput-boundarytest-firstslice:3ManualNoteEditReservationTests plusnil-returning synchronousreserveManualNoteEdit stub. Firsttwo expectimmutableAidentity/revisionsreservedbeforeanyawait; thirdunchanged/nilselectionshouldalready pass. RealreadonlySQLitePRAGMAdata_version checksno writefornon-edit. ProductionUIstillusesoldStringautosaveuntilactualnewRED. Expectednextcore228includingactualnetworkcase; implementationoforiginal10awaitsGREEN.


Actualedit-inputRED: exactd699fc5bfc266e03d8139869146fd55d7573fef9/run40069154630 corejob120798629939 completed228cases222pass6fail8assert0skip. New3reservationcasesexecuted:2failed3assertionsonmissingedits, negativecasepassed. Existing8recovery/6deletion/2boundreceiver/2rename/7formattercasesallpassed. ThreeoldpositiveLiveASRcasesregressedinvalidInstallation atModels:295 andnewrealdownloadfailedbeforetransfer; nofullcoreGREEN. Canonicalformatter7/7GREEN didnotfixrawQwenquality:4exe1pass3fail6assert0skip. Onlyafterreading/persistingthe2newbehavioralfailures isreserve/UIinputcaptureimplementationauthorized. Nativejobstilllive; nopushmaycancelit.
