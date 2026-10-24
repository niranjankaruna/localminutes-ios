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
