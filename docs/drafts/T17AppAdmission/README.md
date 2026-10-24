# App-owned shared heavy admission — inactive test-first composition

DRAFT / NOT_RUN. Two portable owner-composition cases, one native default-services
case, and minimal pass-through/nil observation seams. No active production, tests,
workflow, project, Git, or native/model execution changes. Heavy lifecycle boundary
resources are explicit doubles, never fake inference. Actual owner/coordinator,
per-meeting registry, capture queue/conversion, CAF, and heavy gate remain real.

## Activation details

1. Replace Core/RecordingUsageAdmission.swift with the draft protocol/default-
   forwarding contract. The async method **must be a protocol requirement**; an
   extension-only method would statically dispatch instead of reaching the bridge.
   Do not invoke it from the owner before actual new hosted assertion RED.
2. Copy RecordingHeavyModelAdmission.swift.pending into MeetingLibrary/. This is
   deliberately only the existing registry pass-through; it ignores the heavy
   gate and owner binding until RED. Existing MeetingLibrary dependencies already
   include Core/Recording. Do not loosen private registry/token access.
3. Append the two portable tests and private helpers to the existing same-file
   RecordingSessionOwnerTests.swift **outside iOS-only blocks**, preserving all old
   bodies. Add LocalMinutesMeetingLibrary to RecordingTests package dependencies
   and its SWIFT_PACKAGE import branch. Add optional usageAdmission to the existing
   OwnerTestHarness.init and withHarness signatures, defaultnil, and forward it to
   both existing owner-construction branches; this is test composition only.
4. Append native case to NativeStartupIntegrationTests.swift. Add these **nil
   optional fields only** to default Services for test-first compilation:
   `let heavyAdmission: HeavyModelAdmission? = nil`,
   `let recordingAdmission: RecordingHeavyModelAdmission? = nil`, and
   `let intelligence: IntelligenceSession? = nil`. Do not construct a working bridge
   or IntelligenceSession through them before RED. Ensure existing Intelligence/
   QuestionAnswering directories are in the native target if not already present.
   For identity observation add internal read-only accessors on the real types:
   `RecordingSessionOwner.usageAdmissionIdentity` returns its existing private
   usageAdmission; `IntelligenceSession.heavyAdmissionIdentity` returns its existing
   private admission. These are observation seams, not new gates or fake identity
   fields. Nil service fields yield actual reached behavioral assertions.
5. Existing RecordingTests core filter/native shared source discovery cover the
   portable cases; add their exact names to both strict reporters. Add the native
   name to the native reporter and increase expected totals by2core/+3native:
   - testHeldSummaryOrQAHeavyClaimBlocksActualOwnerBeforePreparationAndOSUse
   - testActualASRReservationHoldsHeavyGateThroughPreparationTranscriptActivityAndAsyncFinish
   - testDefaultServicesShareOneHeavyGateAcrossIntelligenceAndActualRecordingOwner

Read/persist compatible actual assertions at the exact test-first SHA, then
implement. Compile/tool failures, nil unexecuted cases, and source inspection are
not RED. Keep every original assertion and these new gate/CAF oracles unchanged.

## Required ownership contract after RED

App Services owns exactly one HeavyModelAdmission. Its IntelligenceSession and
RecordingHeavyModelAdmission receive that same object, and RecordingApplication
injects that bridge into the actual RecordingSessionOwner. The bridge must retain
the real MeetingUsageRegistry claim as well. Acquire synchronously on MainActor
before reservation, preparation, actual model loading, permission, or OS resources;
roll back only the exact newly acquired token if either admission fails. A view
checking recording state is not this invariant and must not replace it.

Owner keeps both claims through held preparation, capture stop, finalized SQLite/
native model drain/unload, and Activity end. After all those barriers, call and
await `finishRecordingUsage` before coordinator.captureStopped, completedManifest,
clearing the epoch, or acknowledging saved recording. Async cleanup failure must
retain exclusion and the exact epoch for explicit retry; never release early or
turn it into successful completion. Existing synchronous release remains for
immediate rollback/compatibility, not permission to release a heavy lease whose
native lifecycle has not settled.

The bridge holds a weak owner binding. Its heavy lifecycle's cancellation may
request a scoped owner stop, but **drain must not await owner.stop**: owner cleanup
itself awaits gate finalization, so that would self-join forever. Use a distinct
owned resources-settled barrier; owner signals it after its real combined barriers,
before joining gate cleanup. Gate drain waits on that barrier, and native unload/
model-lease completion must already be known or explicitly awaited independently.
Do not join the outer owner cleanup task from the gate resource. The portable
second case cancels the gate externally while owner Stop awaits Activity, then
releases Activity and requires both waiters to finish, exposing that deadlock.

The native case does not touch default/user data: it reuses the existing UUID-owned
NativeStartupFixture. With a held summary gate, direct actual owner start stays
idle. Once released, the real empty model root yields modelUnavailable before OS
permission. That distinguishes a working shared gate from unrelated startup denial
or a view-only check. No model download/fake generation is needed for this wiring
case. A combined actual-ASR/actual-Qwen resource run and physical memory/thermal/
background behavior remain separate mandatory integration/device gates.
