# T18 app-owned intelligence — inactive test-first slice

All Swift files are `.pending` outside build paths. No working session, loader,
save adapter, runtime experiment, RED/GREEN or phone evidence exists here.
Existing semantic assertions and active production files are unchanged.

## Files and activation

Proposed new portable target `LocalMinutesIntelligence`, directory `Intelligence`,
depends on Core, Models, Persistence, Summary and QuestionAnswering. It does not
depend on SwiftUI or the iOS app target. Proposed `IntelligenceTests` depends on
that target plus the same component libraries; CryptoKit is available on the
supported Apple platforms. Copy:

- `IntelligenceSession.swift.pending` to `Intelligence/IntelligenceSession.swift`.
- The other three Swift files into `Tests/IntelligenceTests/`.

Root must update Package/XcodeGen/app dependencies and required CI/reporting
before activation. Run four `IntelligenceSessionTests` cases on compatible macOS,
while `ActualIntelligenceCompositionTests` belongs only in the dedicated actual
Qwen job. It is mandatory, with no skip or environment opt-out. Missing model is
a failure. Existing actual pipeline unknown-owner/QA-refusal cases remain required
and must not be hidden by this positive composition fixture.

Four unit cases use actual temporary SQLite, its generated-document APIs, the
real filesystem ModelInstallationManager, actual volume capacity and the real
shared HeavyModelAdmission. Only load/tokenization/generation/unload and ASR
lifecycle boundaries are doubled. Nonsense model bytes test file lease/integrity
only and must never be sent to the native loader. The boundary runtime never
saves documents or releases a model/admission lease on the service's behalf.

1. `testSummaryAndQASaveSelectedValidatedDocumentsAndProvenanceWithoutChangingOriginals`
   requires both typed existing components, real saved immutable JSON/provenance,
   reopened persistence and unchanged transcript/manual notes/other meeting.
2. `testCancellationJoinsWorkThenUnloadsAndReleasesRealModelLeaseBeforeReplacement`
   cancels actual service work behind async generation/unload boundaries. Real
   manager deletion must fail until unload ends, then succeed; replacement must
   save exactly one new QA document, with no cancelled summary residue.
3. `testOneSharedGateRejectsASRThenConcurrentSummaryQAWithoutLoadingAnotherRuntime`
   occupies the same gate for ASR, then holds one session's summary against a
   second session's QA. Loader observations prove the loser never loads another
   resource; after cleanup it can load. Actual-ASR composition remains separate.
4. `testActualClosedSQLiteSaveFailurePublishesNothingAndStillReleasesRuntimeAndLeases`
   closes the real database after source loading and before generated save.
   The service must report the real error, publish no document, unload/release,
   and leave unchanged originals plus zero generated rows after reopening.

The fifth case,
`testDefaultPinnedQwenServiceSavesSummaryAndSelectedAnswerThenReleasesActualInstallation`,
imports the exact existing Qwen artifact, calls the mandatory default loader,
checks actual prototype/Friday and guide/Leo/Thursday semantics plus selected QA,
reopens documents and proves installation deletion succeeds after real unload.
No new model download is authorized by this draft. Import uses two additional
temporary copies (~2.24GB) beyond the existing verified 1.12GB artifact; review
actual job headroom before activation, then use honest failures, never a skip.

## Required service contract after its own actual RED

The app-services instance retains one session and shared gate. A request fixes
operation UUID, selected meeting, document UUID and creation time before any
suspension. Reject competing requests on that same session with
`IntelligenceSessionError.busy`; a busy shared model gate retains its existing
`HeavyModelAdmissionError.busy`. Source and notes are read from that selected
meeting, not from a view's current selection at a later time. Capture immutable
values and reject a missing meeting. Validate an exact current gate generation
before native load and accepting late results.

Acquire heavy admission before model acquisition/native construction, retain
the actual ModelInstallationManager lease, and ensure the default loader accepts
only the already reviewed manifest revision/size/SHA/runtime. It must construct
the actual CPU LocalSummaryRuntime in an explicitly off-MainActor task; do not
replace it with a fake/default injection or perform its expensive constructor
on MainActor. The stub intentionally throws until compatible native RED.

Use the existing SummaryPipeline or MeetingQuestionAnswerer with that runtime's
actual canonical token counter/generator. Map stored source UUIDs and global
16kHz ranges without changing original source text. Serialize only the validated
domain result, preserving every citation/provenance and null owner/date. Initial
edited text is a display rendering, separate from immutable generated JSON and
original manual notes. Save through the real createGeneratedDocument API.

Persisted envelope v1 uses snake_case keys: `schema_version`, `meeting_id`, and
`summary_points`/`decisions`/`actions` for summaries; points have `text`, `evidence`,
`provenance`; actions also have `task`, nullable `owner`/`due`. Evidence has
`source_id`, `start_sample`, `end_sample`, `quote`; provenance has
`model_revision`, `prompt_version`, `map_index`. QA has `status` and validated
`evidence` entries. Store columns preserve model/prompt revision, kind/question,
creation time and initial edit revision zero. This wire contract needs its own
audited encoder in the implementation, not unchecked raw model JSON persistence.

Avoid cleanup self-join: the retained outer operation awaits a distinct work
task; gate resource `drain()` joins only that work task, never the outer operation
or its own cleanup task. Gate `unloadAndReleaseModel()` awaits runtime unload,
then releases the exact installation lease. Only after that barrier may the
outer operation publish final success/cancellation/failure or accept replacement.
Cancellation before the one SQLite save prevents publication. Define the atomic
SQLite commit as the saved-result boundary: cancellation arriving after that
accepted commit cannot silently erase an already saved/user-editable document.
Native cleanup errors retain the gate's existing fail-closed ownership.

These tests do not prove app screens/actions, history editing/export integration,
unknown semantic correctness beyond the existing mandatory model oracles, ASR
resource composition, two-hour phone endurance, locks, Action Button or refresh
preservation. Those gates remain separate and pending.
