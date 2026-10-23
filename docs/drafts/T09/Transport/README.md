# Next test-first slices — no behavior implemented

Transport activation: copy HTTPSModelTransport.swift to Models, and
HTTPSModelTransportTests.swift to Tests/ModelTests. Foundation/CryptoKit only.
All functions are no-op interfaces awaiting actual hosted RED. The ten required
portable method names are:

```text
testActualURLSessionWritesNonemptyServerBytesOnlyToOwnedStaging
testHTTPStatusFailureCannotPublishAStagingFile
testShortAndOversizedResponsesFailBeforeAFileCanBeInstalled
testPlainHTTPAndUnapprovedInitialHostsAreRejectedBeforeNetwork
testFinalResponseURLMustRemainHTTPSOnAnApprovedDistributionHost
testUnownedOrSymlinkedDestinationCannotBeWritten
testExistingDestinationIsNeverOverwritten
testCallerCancellationCancelsActualURLSessionTaskAndLeavesNoOutput
testRedirectDelegateApprovesOnlyReviewedHTTPSHosts
testRealStorageCapacityQueryReturnsNonnegativeCapacityForPersistentDirectory
```

Use actual URLSession download tasks to temporary files, not full model Data in
memory. URLProtocol doubles only the server HTTP response. The redirect test
uses the actual URLSessionTaskDelegate entry point with real URLSession/task
values. Its example reviewed host is a fixture policy allowlist, not a claim
about the current publisher redirect. A separate HEAD observation on23October
actually saw `huggingface.co`302 → `us.aws.cdn.hf.co`200 for the pinned Qwen
artifact; signed query strings were deliberately not printed. Root must review
the exact live ASR distribution hosts before configuring the production allowlist.

Construct the transport with the model manager's `.staging` directory. A legal
destination is exactly `.staging/<operationUUID>/<artifact.fileName>`, with no
symlinked directory/file and no preexisting destination. A failed/cancelled task
removes its own uncommitted temporary/output file. Installer tests already prove
preservation of the previous model on download failure/cancellation.

NativeModelStoragePolicyTests.swift is a separate iOS test-target draft. It checks
actual file-protection metadata on existing model/metadata directories/files.
Activate it only with the native implementation; simulator metadata success
does not prove locked physical-phone access. The Files import and production
download UI must keep integrity separate from successful real-runtime loading.

No tests here have compiled or executed. Resume/progress UI and actual native
recognizer readiness are still separate work. Root owns integration and CI.
