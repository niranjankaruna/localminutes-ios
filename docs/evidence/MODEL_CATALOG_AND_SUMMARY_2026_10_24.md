# Model catalogue, actual summaries and app diagnostics

Owner removed the30minute cap, retained focused checks during implementation,
and requested arbitrary Hugging Face repository lookup, model-card details,
actual phone resources versus model requirements, Download/Remove and independent
Speech/Summary Equip choices. Several alternatives may remain installed; exactly
one per purpose is equipped. No publisher allowlist or forced Whisper size.

## Recorded RED before the repairs

Source84ff22a6b54731ec179b78910d48da8476ba746b, [run40107527439](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40107527439).

- Phi positive summary: job120912204976, one actual caseFAILED/one assertion,
  zero skipped,203.809s. Actual JSON completed; text paraphrased the quote and
  task changed its case. Validator rejected unsupportedClaim.
- Phi unknown-owner/date summary: job120912205083, one actual caseFAILED/one
  assertion, zero skipped,174.341s. Nullable fields were null, but task was an
  unsupported paraphrase paired with a quote about missing ownership.
- Default app diagnostics: job120912205102, three Simulator casesFAILED,
  ten assertions, zero skipped,2.960s. Real default recorder was nil, visibility
  did nothing, and protected metrics export threw notImplemented.
- Existing blocked-SQLite cancellation case: job120912205127, one casePASSED,
  zero skipped,0.591s. Do not change working cancellation merely to add code.

This is genuine behavior RED after compilation and actual model execution.
An independent bounded Windowsb5046 run also completed Phi nested JSON in36.3s
and showed the same unsupported paraphrasing. It does not establish phone speed.

## Proposed repairs and tests-first scope

Extractive JSON grammar may choose verbatim text from the current selected
chunk. All source choices are supplied generically; none are fixture answers.
Category/source/owner/date choices still come from the real model and unchanged
validation rejects wrong provenance, links and nullable attributes. No generated
output rewriting or semantic-oracle weakening. Larger literals retain the
existing free-string route rather than silently removing their evidence.

Default app diagnostics will retain and connect the actual existing recorder,
forward real scene visibility, and publish validated protected atomic JSON.
This cannot prove locked progression, memory/endurance or a physical-device gate.

New catalogue, selection and Whisper files are test-first interfaces only until
their actual assertion RED is observed. Metadata/card text remains untrusted
data. Downloads need exact immutable revision, size and SHA256, verified again
before installation/use. Model removal cannot delete meetings or active leases.
Memory estimates remain labelled estimates, compared with current phone facts;
unknown requirements are not displayed as zero or supported.

GREEN and actual catalogue/Whisper RED: pending exact-source run.


## Actual component and integration evidence

Source4f328bd2095e91686c72f564f2d514b74d14d543/run40111205922: HFmetadata30PASS, originalselection10PASS, inventory2newRED. Whisper4actualcasesPASS32.717s0skip (rolling26.859s, cancel4.417s, load0.730s, invalid0.711s). SelectedWhisperlive job1209231265251FAIL5.539s atreadiness becausefixedZipformerpreflightignoredselectedmodel. ActualselectedPhi defaultservicejob1209231265531FAIL4assertions167.583s; bothoperationsrejectedinvalidModel byhardcodedQwenloader. These are behavioral RED, beforethecurrent repairs.

Portablejob also accidentally matched legacyActualSummaryPipelineTests withoutQwenfixture becauseunanchoredclassname regex. That one missing-fixturefailure is NOT behavioralRED; nextfilter usesexplicitmodule-qualifiedclassestoavoidunintendedactual-model jobs. No existing oracle was removed orweakened.

NativeResourcejob120923126296 exited65beforeanyXCTestcase; nativeMetricsjob120923126506 wascancelled15min withnocompletedcases. This doesnotprove a resource/metricsbehaviorfailure. Precise xcresult startupdiagnostics areaddednext; no linkpinchangeorsimulatorpass guessed. ResourceadapterisnowsharedportableFoundationstub plus2actualhostRAM/volumecontracts toobtaincompatible-platform RED. iOSapp-memoryavailability remainsseparatephysicalscope.

Nativebrowser/controllerbindings, genericmetadata-basedGGUFloader, selectedWhisperliveadapter andmetadata-only inventoryareimplemented aftertheirrecordedRED; integrationGREENpending. Metadata/cards remaininert, andweightsneverenterGit/artifacts. iLoaderdocs/ownerinstallationreportarepreserved. No physical/2h/ActionButton/renewalclaim.

## Integration result, 24 October 17:25 UTC

Exact source `d0fe973b0045d5fb11c3dc0a33bd62ab5c39a991`,
[run 40114656922](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40114656922):

- Actual selected Phi default loader: job120933345261, 1 PASS, zero failures/skips,
  571.357s. Installed actual pinned GGUF, automatic native template detection,
  generated/saved summary and selected-meeting guide answer; original SQLite
  content and model ownership assertions pass. Not an iPhone speed measurement.
- Actual selected Whisper live session: job120933345309, 1 PASS, zero failures/
  skips,16.771s. Licensed speech is published before stop and durable global
  ranges retained. Separate native Whisper 4-case job120933345190 is SUCCESS.
- Portable job120933345263:60 tests,58 PASS,2 failed cases/3 assertions,0 skipped
  (counts reported by XCTest); HF30, selection/inventory12, pure-summary16 pass.
  Both actual resource-reader tests fail against the nil stub: physical RAM and
  owned-volume free capacity absent. This is genuine RED before OS-backed reader.
- Native metrics job120933345288: xcresult records3 actual tests,2 PASS,1 FAIL,
  zero skips. Protected atomic JSON test fails MetricsValidationError because
  codec accepts numeric versions but real manifest uses sherpa-onnx-1.13.8.
  Quiet xcodebuild log hides case discovery; xcresult is authoritative. Next
  focused run removes quiet output; no simulator startup failure is inferred.
- Native resource job120933345132 has no observed completed result yet. Earlier
  no-case/harness evidence is preserved, never relabelled as a pass or RED.

Test-first commit `d95554f` precedes the packaging repair. Windows actual RED:
3 package-policy tests,1 PASS/2 FAIL (GGML .bin and raw weights were accepted).
After repair the same3 pass. Relevant portable package regressions:45/46 pass;
the remaining Windows symlink test cannot create a link (EPERM), a host setup
limitation rather than behavioral RED. It remains enabled for hosted macOS.
Whisper MIT notice and disk-space required-reason declaration are added to app
resources; full dependency privacy/SBOM review remains MVP3.

Next batch includes test-first exact nested variant identities, actual adapter
scope/availability, selected-epoch metric pins, narrow engine-version codec,
durable summary checkpoints and actual CAF ASR recovery replay. No production
behavior for these new cases precedes their hosted assertion RED. Expensive
selected Phi/Whisper generations already passing are excluded from this batch.
MVP1 is not delivered yet; no physical gate or VERIFIED_COMPLETE claim.

## Final repair RED and first resource GREEN

Test-first source `c93633213c9cde7fa9d25bc004f26113f98ef265`,
[run40116270957](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40116270957),
job120938092705, exact module-qualified focused filter in workflow:
80 executed,66 PASS,14 failed cases,62 assertions,0 skipped,3.593s.

- Actual resource reader2 PASS after its preceding2-case RED. macOS host facts
  only; iOS advisory memory/native resource cases remain separate.
- Installation identities3 executed/1PASS/2FAIL,3 assertions,1.166s: nested
  variants collide and exact Unicode path bytes are lost. Full remote paths
  now enter an order-independent length-framed byte digest; GREEN pending.
- Runtime readiness6 executed/1PASS/5FAIL,13 assertions,0.020s: wrong Zipformer
  tuples, unknown GGUF families and missing engines were advertised supported.
  Policy now checks actual compiled adapters, reviewed Zipformer pins and
  Qwen2/Phi3 scope; unavailable/unknown stays explicit. GREEN pending.
- Metrics7 executed/4PASS/3FAIL,7 assertions,0.018s: exact engine labels rejected
  and selected epoch model/runtime pins remain stale. Repair binds model pins
  atomically while retaining binary identity/clock/visibility and restricts
  diagnostic version labels. Existing negative privacy checks remain enabled.
- Durable summary checkpoint4 executed/0PASS/4FAIL,39 assertions,0.165s:
  reopen/provenance/contiguity/conflict/cancel contracts fail against no-op.
  Protected atomic sidecar implementation follows RED; app pipeline resume is
  still a separate unimplemented MVP2 step, not inferred complete from storage.

Separate job120938092779:3 actual CAF/model-install/SQLite recovery cases FAIL,
21 assertions,0 skips,14.987s. The no-op performs no inference: original-only
transcript, zero replayed samples, missing gaps/checkpoint and ignored registry
claim prove absent replay after setup. Production replay follows this RED and
must run actual CPU ASR to pass; no synthetic recognizer is substituted.

Default starter summary pin now promotes the measured Phi candidate after its
real summary and default-loader GREEN. Qwen's failed quality evidence/oracles
stay preserved. Existing installed models/meeting data are not deleted.
Decision and owner usage: SUMMARY_MODEL_DECISION.md and MVP1_MODELS.md.

Native c936332 result is now observed: resource job120938092784,2 PASS,0fail/
skip,0.012s on iOS26.2 Simulator. Metrics job120938092614,3executed/2PASS/1FAIL,
1assertion,0skip,1.055s, same engine-version codec failure. Standard XCTest
output now permits strict discovery; no simulator launch defect remains.

Final delivery batch will verify only relevant model/metrics/storage regressions,
changed real speech flows, five native service/resource cases and the real
iPhone app/extension package. Already-passing Phi inference is not repeated.
Separate future SummaryResumePipelineTests and replay checkpoint-integrity
tests remain tests-first pending actual RED, explicitly outside MVP1 scope;
the existing full validation mode retains them. There is no full-suite claim.

Review found an MVP2 replay cursor-integrity defect: changing nextGlobalSample
can skip untranscribed audio despite intact other hashes. Explicit regression
is prepared before repair. Replay stays unwired in the app and is not a shipped
recovery feature merely because the initial three primitive cases may pass.
Same-model recovery for chosen Whisper variants and actual app resume wiring
also remain MVP2 work. Persisted summary transport alone does not resume a job.
