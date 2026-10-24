# Library product UI — three inactive native UI cases

DRAFT / NOT_RUN. No active App, UI, tests, workflow, model, or Git changes.
Inspection of the current LocalMinutesHomeView confirms history/details, selected
transcript search, manual notes, Share text/Markdown, and model-settings states.
**There is no Generate Summary/Q&A product action yet.** The third case deliberately
requires those new product sections/actions as test-first behavior, alongside the
existing export controls and model-settings state. It must fail until that UI is
implemented after its actual hosted UI assertion RED.

## Activation and exact cases

Copy `LibraryProductUITests.swift.pending` into `Tests/NativeUITests/` (already part
of LocalMinutesUITests in project.yml). Preserve all original three recording UI
cases. Add these three exact names to the UI strict reporter/xcresult count:

- `testActualHistoryDetailsAndTranscriptSearchStayWithinTheSelectedMeeting`
- `testManualNoteNavigationAndRelaunchPreserveTheEditWithoutChangingAnotherMeeting`
- `testEditableGeneratedSummaryAndAskMissingModelStaySeparateFromOriginalsAndOtherMeetings`

Existing selectors use English labels: Meetings/Models tabs, unique meeting titles,
`Original meeting notes`, `Find in this transcript`, Share text, Share Markdown,
`Optional download · 1.12 GB`, and Download summary model. New product acceptance
identifiers are `meeting.generatedSummary.editor` (separate TextEditor),
`meeting.generatedSummary.generate` (Summary action), `meeting.qa.question`
(TextField), `meeting.qa.ask` (Ask button), `meeting.intelligence.modelRequired`
(honest model-required message), `meeting.qa.answer` (published answer only), and
`meeting.intelligence.running` (actual operation progress only). The Ask button is
available after a question is entered; when no model is installed it explains the
block with “Download the summary model to summarize this meeting or ask questions.”
and must not publish an answer/start progress. Current fixture failure ID is
`ui.fixture.library.failure`; canary is
`LOCALMINUTES_DEBUG_LIBRARY_FIXTURE_CANARY_v1`.

Copy the no-op fixture hook into App/ **inside its entire existing DEBUG+iOS
conditional**. In LocalMinutesApp's DEBUG entry path, the launch argument
`--ui-test-library-fixture` selects LibraryUITestFixtureRoot before any normal
RecordingApplication.shared initialization. Its UUID comes only from
`LOCALMINUTES_UI_LIBRARY_TOKEN`. A missing/invalid UUID fails closed on the fixture
screen; it must not fall back to ordinary services or a default storage root.

The present `let application = RecordingApplication.shared` property is eager:
do not keep that initialization on a fixture launch. Delay normal shared creation
until the ordinary branch, preserving its Release path. Both request parsing and
fixture root must remain under `#if DEBUG`; Release must have no fixture branch,
environment override, seed fallback, test reset, or alternate runtime.

First test-first push contains only the compilable no-op hook, root selection, UI
tests, and compiled-build boundary checks. Missing synthetic meetings will produce
actual UI assertion RED. Read/persist that exact hosted result before implementing
the real fixture seeding. A compile error, failed launch, or zero tests is not RED.
Record this narrow fixture-harness RED separately from product-action RED/GREEN:
absence of fixture data does not prove Summary/Ask behavior was exercised. After
real fixtures are seeded, obtain actual reached assertions for the missing new
sections/actions before implementing that product UI. Preserve all three cases.

## Actual fixture contract after harness RED

Use LocalMinutesServices(rootURL:) and RecordingApplication(services:), with real
SQLiteMeetingStore and SegmentCAFWriter. Present the actual LocalMinutesHomeView.
Do not inject arrays into a view/controller, render a second fake library, or
substitute generated answers. The model root is empty; these tests never start
microphone capture, install/download models, invoke inference, or send shares.

Own only ApplicationSupport/LocalMinutesUITestFixtures/<canonical UUID token>/,
which is a sibling of the normal LocalMinutes root. Validate all owned components
against symlinks/aliases and use the existing protection policy. Never accept an
absolute root/path from launch arguments. Never inspect, clear, delete, seed, or
change attributes on normal/default storage or another token's directory.

For a new empty UUID-owned root, seed these constant original synthetic records:

| Record | Stable ID | Required values |
|---|---|---|
| Alpha meeting | 00000000-0000-0000-0000-000000000001 | title UI Library Alpha; completed; created1000; captured32000 |
| Beta meeting | 00000000-0000-0000-0000-000000000002 | title UI Library Beta; completed; created2000; captured32000 |
| Alpha source0 | 00000000-0000-0000-0000-000000000010 | seq0; samples0...16000; Alpha shared-term original transcript. |
| Alpha source1 | 00000000-0000-0000-0000-000000000011 | seq1; samples16000...32000; Alpha separate-topic original transcript. |
| Beta source0 | 00000000-0000-0000-0000-000000000020 | seq0; samples0...32000; Beta shared-term original transcript. |
| Alpha note | meeting Alpha | Original Alpha manual note.; revision1; modified3000 |
| Beta note | meeting Beta | Original Beta manual note.; revision1; modified3000 |
| Alpha generated summary | 00000000-0000-0000-0000-000000000100 | kind summary; meeting Alpha; editedText Seeded Alpha generated summary. |
| Beta generated summary | 00000000-0000-0000-0000-000000000200 | kind summary; meeting Beta; editedText Seeded Beta generated summary. |
| Beta saved answer | 00000000-0000-0000-0000-000000000201 | kind question_answer; meeting Beta; editedText Seeded Beta private answer.; question What planning source was recorded? |

All source modelRevision values: synthetic-ui-asr-fixture. For each meeting create
its UUID-owned Meetings/<meeting UUID>/ directory and actual mono16k PCM16 CAF plus
capture-manifest.json using SegmentCAFWriter, with exactly32000 synthetic zero
samples. Finalize/close writer before marking the meeting completed. Text is
explicit synthetic seeded data, not claimed recognition of that silence.

Seed generated records through the actual schema4 `createGeneratedDocument` API;
retain originalJSON as a constant synthetic JSON object referencing only its own
meeting/source IDs and exact source quotes. Use revision0, modelRevision
synthetic-ui-qwen-fixture, promptVersion synthetic-ui-summary-v1 / synthetic-ui-qa-v1,
created/modified4000...4002; summary question is nil. This is declared UI fixture
data, never a fake model adapter. The new Summary editor persists only generated
editedText through revision-checked storage; the third case checks Alpha original
notes remain unchanged and Beta's generated summary does not receive Alpha's edit.
Alpha has no saved QA answer, so its blocked Ask must never show Beta's saved answer.

Commit a protected fixture-ready marker only after both actual CAFs and every
SQLite record commit, including token, fixture version, and expected meeting IDs.
For relaunch with that token, reopen without reseeding or resetting original/user
notes. A nonempty root without a matching marker fails closed, never gets wiped or
silently overwritten. Retain small token roots only in the disposable CI simulator;
tests terminate the app and never recursively delete app/default container data.

## Compiled Release exclusion gate

Activate `library-fixture-build-boundary.test.mjs.pending` as a native-build test
under scripts/native-tests/; run only after actual Release-device and Debug-
simulator compilation and before XCTest mutates pristine products. It reads actual
Mach-O bytes of the Release app and extension, requiring every launch/seed/canary
marker absent. A Debug positive control requires the hook/canary actually linked.
Missing products fail; source inspection is not a substitute. Keep it before
packaging so no fixture mode reaches the IPA. Existing archive/product gates stay
strict and unchanged. Any new build-check script changes need their own reviewed
test-first activation; this inactive file performs no local compilation/execution.

The export UI case observes real enabled ShareLinks plus the existing privacy cue;
selected payload byte contents are already covered by actual MeetingTextExporter
tests. It does not assert OS share-sheet delivery or send content to another app.
Summary/Ask generation must eventually use the separately tested actual-backed
IntelligenceSession and operation admission. Missing-model UI and seeded editable
records do not prove native generation, semantic quality, or lifetime integration.
No actual-model quality, phone Lock Screen, Action Button, renewal, or endurance
gate is replaced by these simulator UI flows.
