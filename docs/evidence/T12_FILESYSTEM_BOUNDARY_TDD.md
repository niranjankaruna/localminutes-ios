# Filesystem boundary regressions

Test-first source `917844b016664251c545fb70106c50cfceb62694`, run
[40071855360](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40071855360),
completed core job `120806812209`. Actual hosted macOS `swift test` compiled
and executed the three new real-filesystem regressions before repairs.

- `PersistentFileBoundaryTests.testHardLinkedOutsideInodeIsRejectedBeforeAnyPolicyAttributeMutation`:
  did not throw and changed outside inode/root permissions and backup flags.
- `PersistentFileBoundaryTests.testCAFConstructorRejectsSymlinkedParentWithoutCreatingOutsideSession`:
  did not throw and created the session directory through the outside symlink.
- `SQLitePolicyScopeTests.testOpeningAndReopeningSQLitePreservesUnrelatedSiblingBytesPermissionsAndBackupFlags`:
  changed permissions and backup flags of unrelated siblings on open/reopen.

Boundary suite: two cases failed, seven assertions, zero unexpected/skipped.
SQLite scope: one case failed, 16 assertions, zero unexpected/skipped. These
behavioral RED results authorize the corresponding bounded repairs. No phone
file-protection or locked-access result is established by these macOS tests.

The same source's reservation suite executed three cases, two passed, one
failed: the immutable reserved edit differed from its actual SQLite round trip
at sub-print-resolution timestamp precision. Its meeting binding and text were
correct. Preserve the strict equality oracle and canonicalize the generated
reservation timestamp to the existing SQLite epoch representation.

The real HTTPS four-file model download/install/reopen/import/lease/CPU-ASR
integration passed (one case, no skips), as did all ten native CPU recognizer
and all four live transcription composition cases. The directory URL hint
regression repair is verified for these scopes; the full workflow remains RED.


39d9eaa/run40073883889: both hardlink and CAF-parent regressions now pass. SQLite preserves sibling bytes/modes but still fails16 backup-flag assertions because excluding the parent changes effective child getters. This requires preserving all parent attributes in a generic database constructor, with explicit whole-root policy owned by App Services. The native WAL fixture must apply its explicit owned-root policy as setup, retaining every actual root/DB/sidecar assertion; no acceptance weakening or fabricated flags. Exact-file policy remains mandatory. This is repair attempt2 for SQLite scope, after actual repeat RED.

SecondSQLite scope repair preservesparentmetadata; defaultServicesownswholepersistentrootandnativeWALfixtureexplicitlyappliesrootpolicybeforeDBopen. Everyexistingroot/DB/sidecarassertionandall7physicaloraclebytesremainunchanged. No mixed-parent exclusion or newsidecarclass success isclaimeduntilnextCI/phoneevidence.


## Exact-source full regression GREEN

`db1b8d51c5ff72bf1d8abfd13f99a1da06a11e04` / [run40079629180](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40079629180) completed SUCCESS.269core/59scripts/85TSAN/5actualQwen/59native/3UI/2bundle/13archive cases all pass,0failures/skips/reported races; native/UI xcresult agrees. This supersedes earlier pending-GREEN statements for the bounded component above. It does not complete its broad parent feature or any physical gate. Source, artifact, limits and exact remaining work: [continuation08 checkpoint](CONTINUATION_08_CHECKPOINT.md).
