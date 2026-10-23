# T12 privacy metadata gate — test-first draft

No active source, package, project, test, CI, Git, or root checkpoint was edited
by this worker. These seven native tests have not compiled or executed. Root
must obtain actual SDK assertion RED before any policy implementation, including
the existing `ModelStoragePolicy.protectPersistentDirectory` no-op.

Activate `NativePersistentPrivacyTests.swift` under the existing native
`LocalMinutesAppTests` source path, for example
`Tests/NativeAppTests/NativePersistentPrivacyTests.swift`. It imports only
AVFoundation, CryptoKit, Foundation, SQLite3, XCTest, and the actual LocalMinutes
app module. No new production interface is necessary. The current existing
method, real default LocalMinutesServices, actual installer, actual SQLite store,
and actual CAF writer are exercised.

Required case inventory:

```text
testDefaultServicesUseProtectedExcludedApplicationSupportRoots
testExistingModelAndMetadataTreeIsProtectedWithoutChangingBytes
testNewVerifiedModelImportReceivesPersistentPrivacyInsteadOfSourceProtection
testActualSQLiteDatabaseWALAndSHMAreProtectedAndRowsSurviveReopen
testSQLiteSidecarsRecreatedAfterReopenRetainPersistentPrivacy
testNewCAFSegmentsAndAtomicManifestStayPrivateBeforeAndAfterFinish
testRecursivePrivacyPolicyRejectsSymlinksWithoutChangingOutsideFiles
```

The first test instantiates actual default services and inspects the true
ApplicationSupport/LocalMinutes, Models, Meetings, and meetings.sqlite paths.
It never deletes or inserts into the default database/model tree. Its extra
database connection is closed. Root's current default creates no explicit
protection/backup policy and does not precreate every directory, so this contract
must be observed rather than assumed.

The other tests own fresh UUID directories under the real ApplicationSupport
directory's separate LocalMinutesPrivacyTests parent. Cleanup checks that exact
ownership boundary and never removes the ApplicationSupport/default app root.
Only original non-model bytes, generated PCM, and synthetic meeting rows are
written. Nonsense ONNX fixtures establish filesystem privacy, never inference.

Every needed file/directory must have actual after-first-unlock protection
metadata. Backup exclusion can be set on the owned root or an owned ancestor;
the test follows that hierarchy because an excluded directory covers its
contents. It does not demand redundant backup flags on every descendant.
Files imported with a stronger source class are deliberately copied; installed
files must receive the locked-use policy while source protection stays unchanged.

SQLite fixtures use actual SQLite C calls to choose WAL and prevent auto-
checkpointing while real writes create real WAL/SHM sidecars. This does not
require switching the application to WAL if it currently uses another journal
mode. The test ensures that whichever sidecars exist receive the policy and that
future recreation/reopening does not lose it. The database is reopened and its
actual persisted row checked. CAF tests inspect closed checkpoint segments and
the atomic manifest during capture, then verify the new final segment/manifest
without a post-hoc blanket policy call.

The symlink test expects fail-closed behavior for a path escaping the selected
owned tree and proves no bytes/protection/backup metadata changed outside it.
Do not traverse links, suppress the error, or delete outside paths to pass.

## Honest limits and next implementation boundary

Simulator success would establish only returned iOS filesystem metadata and
actual persisted I/O. It cannot establish device encryption, first-unlock/reboot
behavior, locked readability, background capture/transcription, backup-network
activity, signing refresh, or two-hour endurance. If a selected simulator cannot
preserve/report a required protection class, record that precise limitation and
retain the physical metadata/access gate; do not fake a class or silently skip.

After actual native RED, root can implement one narrowly owned policy that
sets the selected protection class and excludes the owned persistent root from
backup before constructing data-producing services. It must also cover copied
models, SQLite sidecar recreation and new CAF/atomic metadata files. Preserve
these assertions and obtain exact-source native GREEN. Applying attributes
after an entire recording is finished does not satisfy the during-capture case.

The policy deliberately permits access after first unlock until reboot. Explain
that tradeoff in the privacy/onboarding guide and require first unlock after
reboot. Both owner-run125minute physical tests remain NOT_RUN until matching
evidence exists; this draft neither runs nor waives them.
