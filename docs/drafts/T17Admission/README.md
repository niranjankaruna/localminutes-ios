# T17 shared heavy-model admission — inactive test-first draft

No file here is in a Swift target. The two `.swift.pending` files are complete
test-first source and minimal no-op APIs. They have not been compiled or run;
compatible assertion RED, pushed test-first source and actual-model composition
are still required. They are not current GREEN evidence.

## Activation

- Copy `HeavyModelAdmission.swift.pending` to `Core/HeavyModelAdmission.swift`.
- Copy `HeavyModelAdmissionTests.swift.pending` to
  `Tests/CoreTests/HeavyModelAdmissionTests.swift`.
- Existing `CoreTests -> LocalMinutesCore` dependencies suffice. Add all four
  cases to mandatory CI reporting; do not skip them or count boundary probes as
  actual inference. Run the existing core regressions as well.
- Prove meaningful compatible RED from the no-op grant/validation/cleanup state,
  then commit/push that test-first source before implementing any exclusion.

Four cases, exactly:

1. `testASRSummaryAndQAAreMutuallyExclusiveUntilNativeResourcesAreClosed`
   covers all nine purpose pairs, including a second instance of the same kind.
   The shared probe tracks concurrently open resource intervals and their
   maximum, so a second grant actually opens a second boundary resource and
   fails the invariant. Cleanup must close the first resource before idle.
2. `testCancelledWaiterAndConcurrentJoinCannotReleaseBeforeDrainThenUnloadComplete`
   holds worker drain and native unload behind separate continuation barriers.
   A cancelled waiter and a second cleanup caller must share one retained
   cleanup operation; replacement is rejected throughout both barriers. The
   cancelled waiter reports cancellation after cleanup, and only the joined
   barrier may make the next resource usable.
3. `testStaleLeaseCannotAuthorizeOrCancelReplacementEvenWhenRequestIDIsReused`
   reuses the request UUID with a new purpose/generation. Old validation and
   cleanup must reject without changing the replacement resource or its events.
4. `testCleanupFailureRetainsExclusionAndRetryResumesWithoutRepeatedCancellation`
   makes the drain boundary fail once. Native resources remain open, unload is
   forbidden, admission stays blocked, and one explicit retry completes cleanup
   without issuing cancellation twice.

The latches are scheduling boundaries only. Native resources, inference, memory
pressure, phone locks, capture drain and real model leases are not simulated
passes. The probe does not generate text or claim a model is ready.

## Current integration findings and proposed ownership

`LocalMinutesServices` is retained by the app-owned `RecordingApplication` and
already creates one `ModelInstallationManager` and `LiveTranscriptionSession`.
It can retain one `@MainActor HeavyModelAdmission`; views only request app
operations and never own the gate. The gate has no static singleton, native
pointers, unsafe shared state, model-framework dependency or filesystem access.

`ModelInstallationManager.acquire/release` pins an immutable verified installation
and prevents its deletion. It does not exclude two different model IDs or native
instances. These file leases remain separate from heavy-model operation leases.
`LocalSummaryRuntime` serializes its own calls but does not exclude a different
runtime or the streaming recognizer. Acquire heavy admission before either
runtime construction/model load, and validate its generation before accepting a
late load/generation result. Keep both leases until native unload has completed.

`RecordingSessionOwner` already claims `RecordingUsageAdmission` synchronously
before permission/preparation work and releases that claim only after its full
capture/transcript/storage/activity cleanup barrier. `LiveTranscriptionSession`
already drains ingress/consumer, unloads the recognizer and then releases the
model-installation lease during finish. Preserve this ordering. A future
app-services adapter can compose the existing meeting-usage claim with the heavy
claim, rolling both back on rejected preparation. Integration must prove that
signals and failed cleanup also retain/release the same exact operation; adding
a view-level Start check would leave intents and async preparation unprotected.

`HeavyModelResourceLifecycle` is only the app owner control boundary:

- `requestCancellation()` synchronously closes new work admission and cancels
  the existing owned worker, without freeing native resources.
- `drain()` joins actual preparation/capture/ASR or summary/QA generation work.
  The actual recording adapter should reuse the owner's existing settled stop
  operation; do not call a gate cleanup from inside that same operation and
  create a self-join cycle.
- `unloadAndReleaseModel()` unloads native runtime and releases the installation
  lease after the worker barrier. A recording adapter may observe resources
  already unloaded by the owner's settled finish; this must be proved in its
  separate integration test, not duplicated blindly.

Summary and QA should share the app-owned gate even when they eventually reuse
one Qwen runtime. Retain their operation/task and verified file lease in an
app-owned adapter. Closing a view or cancelling one waiting UI task must not
cancel the retained cleanup or release admission early. There is no implicit
preemption: a busy start rejects; an owner can request cancellation, await the
barrier, then make one new request. Cleanup failure remains fail-closed pending
an explicit bounded retry; no automatic retry or recursive session is proposed.

## Mandatory later integration gate

Before release composition is claimed, add actual-model tests showing the same
app-services instance prevents a Qwen load/generation while actual streaming ASR
is loading/running/draining, then permits it after genuine recognizer unload and
file-lease release. Show the reverse direction and summary-vs-QA as well. Inject
only scheduling/OS boundaries; use the pinned verified model artifacts and real
runtime. Also retain the existing app/intent preparation-cancellation and drain
regressions. This draft alone does not prove these integrations or physical
iPhone performance, Lock Screen continuation, Action Button or renewal.
