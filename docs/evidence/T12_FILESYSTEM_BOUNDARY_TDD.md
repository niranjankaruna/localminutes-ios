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
