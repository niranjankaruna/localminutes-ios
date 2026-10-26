# Native implementation

Implemented in the local working tree on 26 October 2026. No commits or pushes were made.

## Delivered

- [App shell and meeting history](../App/LocalMinutesHomeView.swift): Meetings, Record, and Settings; date grouping, full-library search, pagination, deletion, and shared library-action state.
- [Recording](../App/RecordingControlsView.swift): one appropriate start/stop control, live Transcript/Notes, genuine elapsed/backlog state, contextual setup and failures, and opening the saved meeting after completion.
- [Meeting detail](../App/MeetingDetailView.swift): Summary, Transcript, Notes, and Ask; rename, search, recovery, source navigation/playback, and deletion.
- [Generated content](../App/MeetingIntelligenceView.swift) and [summary reading](../App/SummaryReadingView.swift): readable original sections, explicit editing, citations, saved answers, model setup, reset confirmation, cancellation, and conflict handling. Edited or unsupported documents display the actual saved text instead of substituting original generated content.
- [Notes](../App/MeetingNotesView.swift): edits reserve their original meeting/revision before debounce, explicit Done flushes pending changes, and failed saves retain the draft.
- [Export](../App/MeetingExportView.swift): real text/Markdown export and a separate generated-content share action.
- [Settings](../App/LocalMinutesSettingsView.swift) and [models](../App/ModelBrowserView.swift): focused model lists/details, repository/file selection, verified downloads/imports, pause/resume, compatibility/resources, Apple Intelligence availability, removal, privacy, device metadata, and storage checks.
- [Library actions](../App/LibraryActionsView.swift): fresh backups, explicit restore confirmation, retained status across service replacement, and real recording reports.
- [Design primitives](../App/LocalMinutesDesign.swift): semantic light/dark colors, native Dynamic Type, accessible controls, press feedback, and reduced-motion behavior.
- [Live Activity](../Shared/RecordingActivityControls.swift): compact status, elapsed time, and session-scoped stop. Meeting content remains excluded from the Lock Screen.
- Screenshot routes and native UI tests now follow focused screens instead of scrolling through the previous monolithic views.

## Deliberate native adaptations

The app uses real content and system typography rather than the prototype's sample data and Inter fallback. Native navigation/tab bars, keyboard, share sheets, file pickers and permission prompts are owned by iOS and adapt to the OS version. Model import stays behind repository/file selection because verification requires a selected manifest. Installation remains separate from model selection. Diagnostic data is never treated as a guarantee of device performance.

No domain recording, inference, transfer, or storage engine was replaced with simulated behavior.

## Validation

Completed locally on Windows:

- 92 repository Node tests passed using node --test scripts/tests/*.test.mjs, including preservation of failed-build logs larger than 4 MB and compiler failures without a source diagnostic.
- Swift grammar comparison found no additional errors in changed/new Swift files. Two existing files have baseline parser limitations around conditional/concurrent syntax; this check is not Swift type-checking.
- Whitespace/diff checks passed.
- The IPA workflow's Bash build step passed syntax checking and four mocked success/failure paths, including an unavailable result bundle and a failing diagnostic command. These checks verify that diagnostic collection preserves the original build exit status; they do not run Xcode.
- Added native regression tests for notes saved after navigation, rapid edits, failed saves, original-versus-edited summary presentation, and citation navigation. Existing UI tests were updated for the new screen structure.

**Native build follow-up:** The invalid SwiftUI Section initializer reported at commit 79c5e82c5bf535f2991731ee6d554b0703ba175a was corrected using explicit content, header, and footer closures. The next Release build, at b4fad5b1d58ae83af8d9544993afb553006ecce9, failed in SwiftCompile without a specific source diagnostic. Inspection found a recursive opaque view type in [ModelBrowserView.swift](../App/ModelBrowserView.swift): the route builder included the download page, whose transfer destination called the same route builder. That destination now creates the transfer page directly, preserving its styling. This is a likely cause of the compiler failure, not a confirmed successful native build.

The [IPA workflow](../.github/workflows/build-ipa.yml) now emits full Xcode build output and prints result-bundle diagnostics in the failed step. The [download helper](../scripts/github-transfer.mjs) saves these logs before remote cleanup, allows larger logs, and surfaces compiler-command failures in its console excerpt. The corrected working tree has not yet been built by Xcode because the hosted workflow requires pushed commits; no commit or push was made by the agent.

**Not run:** app-hosted XCTest, simulator UI tests, native screenshot capture, VoiceOver, or on-device recording. This environment is Windows and has no Xcode/iOS SDK. Editor diagnostics and grammar parsing do not establish that the corrected native build passes.

On a macOS/Xcode host, prepare the project's native dependencies and XcodeGen project using the existing README instructions, then run the LocalMinutesUIValidation and LocalMinutesFocusedValidation schemes. Re-capture all 41 scenes in both appearances and review the native layouts before shipping. Existing screenshots are from the previous UI and were not overwritten.
