# T09 test-first installation slice

Prepared 23 October 2026 by the bounded `verified_models` worker. These files
are outside active application/package paths. No Swift compiler is installed
on this Windows workstation. They have not compiled or executed; no RED,
GREEN, native loading, inference, or iPhone result is claimed.

## Activate without behavior

Root owns Git, state, package/project changes, and CI. Copy the two source
interfaces into `Models/ModelManifest.swift` and
`Models/ModelInstallationManager.swift`. Copy the tests into
`Tests/ModelTests/ModelInstallationManagerTests.swift`.

Add an SPM library product and target `LocalMinutesModels`, path `Models`, and
test target `ModelTests`, dependencies `["LocalMinutesModels"]`, path
`Tests/ModelTests`. The only imports are Foundation, CryptoKit, and XCTest.
The native application can later include `Models` in its existing target;
that does not require another app or extension target. If the same tests are
compiled inside the native test target, select the matching module import.

Run the full strict hosted suite including all 23 names below. Actual expected
stub behavior is one metadata pass and 22 failing behavioral cases; confirm
the observed counts rather than copying this prediction into evidence.
Compile errors, zero discovered tests, and timeouts are not RED. Preserve the
test-first source SHA and failing assertions before implementing the manager.

The metadata constant contains actual pinned expected upstream hashes and the
previously independently hashed token-file digest. Its provenance labels
describe the evidence available when that metadata was written. A concurrent
runtime worker has independently downloaded and matched all four files; root
must record that exact evidence before promoting provenance labels. Filename,
byte counts, and digest expectations do not change.

## Runtime-facing interface and storage contract

`ModelInstallationManager` is the app-owned actor. It supports directory import,
download-to-staging, validated current lookup, acquire/release, and deletion.
`VerifiedModel` has only immutable values: manifest, installation UUID,
directory URL, and `[ModelFileRole: URL]`. The model's immutable manifest carries
revision, runtime version, 16,000 Hz sample rate, and feature dimension 80.

The exact model names are preserved. Actual ASR consumes `files[.encoder]`,
`files[.decoder]`, `files[.joiner]`, and `files[.tokens]`, and keeps a `ModelLease`
alive until the native recognizer is released. A hash-verified handle only
authorizes native load; it never establishes recognizer readiness or inference.

The persistent layout is:

```text
Models/
  .staging/<operationUUID>/<required files>
  <modelID>/
    current.json
    <pinnedRevision>/<installationUUID>/
      encoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx
      decoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx
      joiner-epoch-99-avg-1-chunk-16-left-128.int8.onnx
      tokens.txt
      manifest.json
```

Use same-volume staging, validate every staged byte length and streamed SHA256,
and move the complete staged set into an immutable installation directory.
Only then atomically replace `current.json`. The pointer contains schemaVersion,
revision, and installationID; use validated single path components rather than
trusting a stored absolute path. Do not alter old leased files during replacement.
`current` and `acquire` must revalidate persisted bytes before returning a usable
handle. Failed/cancelled operations remove only their owned temporary staging.

The downloader closure receives one manifest artifact plus an owned staging
destination. It is the only doubled transport boundary; the disk-space closure
is the only doubled storage condition. All directory operations, persistence,
atomic publication, symlinks, reads, and hashes in these tests are real. The
dummy bytes are original non-model fixtures: they prove installer integrity,
never ONNX compatibility or inference.

## Required case inventory

1. `testPinnedSpeechManifestHasOneImmutableCompatibleSetAndHonestDigestProvenance`
2. `testValidLocalImportCopiesHashesAndPersistsLicenseWithoutChangingSource`
3. `testReopenedManagerReturnsTheSameVerifiedPersistentInstallation`
4. `testMissingRequiredFileIsRejectedWithoutPublishingAPointer`
5. `testTruncatedRequiredFileIsRejectedBeforePublishing`
6. `testSameSizeCorruptionFailsActualSHA256Verification`
7. `testUnexpectedFileCannotBeImportedAlongsideModelWeights`
8. `testSymlinkedRequiredFileIsRejectedWithoutReadingOutsideImport`
9. `testUnsafeModelAndArtifactNamesCannotEscapePersistentRoot`
10. `testUnpinnedRevisionMissingLicenseAndMalformedDigestAreRejected`
11. `testDuplicateRolesAndDuplicateNamesCannotCreateAmbiguousVerifiedHandle`
12. `testInsufficientDiskSpaceDoesNotCreatePartialInstallation`
13. `testDownloadBoundaryWritesOnlyOwnedStagingAndProducesVerifiedFiles`
14. `testDownloadFailurePreservesPreviousPointerAndCleansPartialFiles`
15. `testCancelledReplacementLeavesPreviousUsableInstallationAndNoStaging`
16. `testInProgressReplacementKeepsCurrentReadableUntilVerifiedAtomicPublication`
17. `testFailedImportCannotReplacePreviousUsableModel`
18. `testInstalledModelIsRehashedBeforeItCanBeLeased`
19. `testLeasePreventsDeletionUntilTheExactLeaseIsReleased`
20. `testReplacementCannotDeleteFilesStillReferencedByAnOlderLease`
21. `testDeletingUnusedModelPreservesMeetingFilesOutsideModelRoot`
22. `testMissingModelCannotProduceAVerifiedLease`
23. `testCorruptSelectionPointerIsRejectedWithoutReadingAnOutsideModel`

## Scope still pending

After hosted RED, implement only the covered manager behavior, keep strict
regressions, and obtain exact-source GREEN. A production URLSession downloader,
reviewed redirect-host allowlist, resume/progress presentation, explicit iOS
file-protection policy, model installation Settings UI, and complete bundled
licenses/SBOM still require their own test-first work. This slice does not
claim all of T09 or any of T10. Actual native model inference remains the
runtime worker's integration gate.

The human owns both required physical 125-minute iPhone runs. They remain
NOT_RUN until matching sanitized device evidence is provided; no waiver or
automatic pass is implied by that assignment.
