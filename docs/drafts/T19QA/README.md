# T19.2 selected-meeting QA: inactive test-first draft

Status: DRAFT / NOT_RUN. These `.swift.pending` files are deliberately excluded
from all active targets. No Swift compilation, RED, QA implementation, actual
model execution, or semantic quality result is claimed here. Current invocation
has used its six CI runs; activate only in a later bounded invocation.

## Concrete activation

1. Copy `MeetingQuestionAnswerer.swift.pending` to
   `QuestionAnswering/MeetingQuestionAnswerer.swift`. Its only behavior is a
   deliberate empty refusal. Add a `LocalMinutesQuestionAnswering` package
   target/product depending on `LocalMinutesPersistence` and `LocalMinutesSummary`.
2. Copy the other three Swift files into `Tests/QuestionAnsweringTests/`, removing
   `.pending`. Add `QuestionAnsweringTests` dependencies on those three products.
   All fixtures use an actual temporary SQLite database and existing schema3
   FTS; no new migration or schema4 is proposed.
   Include `QuestionAnswering/**` in workflow source-path triggers. When later
   wiring the app, also add that source directory to `project.yml`; a SwiftPM
   target alone does not add files to the native app.
3. Include `MeetingQuestionAnswererTests` in the hosted core test filter and its
   three exact required case names in the strict reporter. Include
   `ActualQwenMeetingQuestionTests` and its one exact case in the existing actual
   Qwen job, using `LOCALMINUTES_QWEN_MODEL_PATH` and the existing pinned native
   framework/model preparation. Do not accidentally run this class in the
   model-free core job or mark it skipped. Expected delta: three core +one actual
   model case. Preserve every original test and exact named execution checks.
4. Commit/push the test-first stubs, obtain/read/persist real assertion RED at its
   exact SHA (a compile failure or missing environment is not RED), then implement
   only these contracts. Preserve the synthetic fixed corpus/rubric and model
   pin; failures are evidence, not permission to weaken semantic checks.

## Four observable cases

- `testNaturalQuestionFindsSelectedEvidenceWithoutNaivelyANDingStopwordsAndPreservesOriginals`:
  full-question FTS is intentionally empty because `what` is absent. Bounded QA
  retrieval must still find the selected budget, cite its unchanged UUID/time
  span/ASR revision, keep the original question, exclude the other meeting, and
  preserve both meetings' notes/transcripts after reopening SQLite.
- `testUnknownSelectedFactRefusesAndAnUnselectedCitationIsRejected`: selected
  undecided-owner source reaches generation; output explicitly refuses. A model
  response forging an actual other-meeting UUID must throw `unsupportedEvidence`,
  even though its quoted text really exists elsewhere in the database.
- `testQuestionExcerptAndCanonicalTokenBudgetsRejectBeforeGeneration`: oversized
  UTF-8 question, an atomic source exceeding excerpt bound, and exact canonical
  input+output at context capacity all fail explicitly before generation. Original
  segment text is never silently truncated to manufacture a fit.
- `testActualPinnedQwenAnswersSelectedBudgetAndPreservesUnknownOwnerDespiteOtherMeetingAnswer`:
  verifies actual file size/SHA256, loads the existing CPU runtime, uses its actual
  canonical tokenizer and typed generation, and inspects both raw model JSON
  outputs. The launch answer must cite the 42000-credit source rather than the
  competing 1800-credit training budget. Unknown owner must remain unknown despite
  another meeting naming Alex. It must execute two native generations; returning
  a prewritten answer or unconditional refusal cannot pass.

## Contract for implementation after RED

Use existing selected-UUID `retrieveEvidence` for bounded literal lexical queries;
plan useful content terms (or bounded per-term queries with deduplication) instead
of ANDing every question word. Candidate sources remain selected-meeting originals
and ordered/deduplicated deterministically; do not broaden across meetings. Unit
generation/tokenization closures are boundary doubles only. App and actual-model
composition use `LocalSummaryRuntime.promptTokenCount` and `generateJSON`.

First supported answer format is explicitly **one exact source quote**, not an
unvalidated paraphrase. Generated JSON fields, in order: `status` (enum
`supported_quote`/`insufficient_evidence`), `source_id` (enum `none` plus supplied
selected source UUIDs), `quote` (string). Keep both statuses and all candidate IDs
available to the grammar; do not constrain it to the expected correct answer.
Encode question/evidence as data and preserve the runtime's canonical role-token
escaping. Schema is a shape/domain bound, never a test-answer template.

Decode strictly: supported output requires one supplied source ID and nonempty
byte-exact quote from that original segment; refusal requires `none` and empty
quote. Reject unknown IDs/unsupported quotes rather than inventing citations.
Return original source/provenance plus generation revision/prompt version. Never
write back to manual notes or transcripts. The actual test must inspect native
output before validation as well as the final answer so a fixed refusal/answer
adapter cannot masquerade as measured Qwen behavior.

Limits are caller-bounded question UTF-8, candidates <=20 (default8), atomic excerpt
UTF-8, final prompt UTF-8 <=65536, actual canonical tokens+reserved output strictly
below context, and bounded generation <=1024 tokens. Invalid configuration/empty
question, cancellation, malformed JSON and unsupported exact quotes need explicit
production handling; this first four-case draft does not claim exhaustive coverage.

No UI, chat history, automatic summaries, model admission/lifetime ownership,
recording concurrency, full map/reduce, device performance, or privacy completion
is proved by this slice. Those remain separate pending tests/work.
