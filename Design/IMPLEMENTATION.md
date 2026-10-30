# Native implementation

## Variant controls and screenshot capture — 30 October 2026

The [shared button style](../App/LocalMinutesDesign.swift) now distinguishes compact inline actions from full-width CTAs. [Model actions](../App/ModelBrowserView.swift) use intrinsic widths, preserve the complete Download label during layout measurement, and allow wrapping in the accessibility-size vertical layout. This addresses the tall icon-only Download control shown in the supplied device screenshot. The same sizing fix applies to the inline summary actions. The [native regression](../Tests/NativeUITests/ModelBrowserAccessibilityUITests.swift) checks visible text, containment, touch targets, and standard-size height in both appearances and at accessibility size 5.

The [shared capture catalog](../Shared/AppScreenshotScene.swift) now contains **118 scenes / 236 light-and-dark screenshots**. Both the app and downloader consume its contracts. Added captures cover the eight confirmation presentations, contextual model sheets, expanded variants, editing/conflicts, structured and edited summaries, loading/recovery/progress/errors, permissions, and hosted launch/Live Activity surfaces. Fixture state is DEBUG-only and uses the actual application views; it does not start recording, download weights, run inference, or execute destructive confirmation actions.

The [native capture runner](../Tests/NativeUITests/AppScreenshotsUITests.swift) checks all required content, presentation titles, expected state text, keyboard state, and three stable layouts. Measured scrolling clears clipping while accounting for navigation, pinned controls, composers, tab bars, and keyboards. Each successful screenshot carries a JSON receipt with its pixel dimensions, checked frames, and capture contract. [Collection and verification](../scripts/app-screenshots.mjs) reject missing/incorrect evidence and retain failures as diagnostics; the [download command](../scripts/download-screenshots.mjs) cannot replace the existing gallery with an unverified capture. Legacy galleries retain their original provenance; old receipts are evaluated against their saved contract, not relabelled as current captures.

API behavior was checked against Apple's documentation for [ideal-size layout](https://developer.apple.com/documentation/swiftui/view/fixedsize(horizontal:vertical:)), [title-and-icon labels](https://developer.apple.com/documentation/swiftui/labelstyle/titleandicon), and [UI-test authorization reset](https://developer.apple.com/documentation/xcuiautomation/xcuiapplication/resetauthorizationstatus(for:)). The real microphone permission prompt is a simulator UI-test scene; it does not capture audio.

Validation: **127 Node tests passed**, including 25 screenshot/transfer tests, with GitHub calls mocked. Swift grammar comparison reported no new errors across the modified Swift files; the existing parser limitations in the model controller remain in the baseline. Whitespace checks passed and the editor reported no diagnostics. These are not native compilation or visual-rendering results.

**Not run:** Xcode compilation, the native button/capture tests, compiled Release-boundary checks, or a new screenshot capture. This is a Windows host. No GitHub Actions, commits, pushes, or branch changes were performed. The existing gallery has not been replaced. Hosted launch/Live Activity fixtures do not verify OS launch timing, Lock Screen delivery, Dynamic Island rendering, or privacy-cover transitions; those remain device checks. See [capture coverage](./SCREEN_COVERAGE.md) and [capture instructions](../README.md).

## Native UI review — 30 October 2026

Applied the apple-design skill to the actual SwiftUI application. Reviewed all 74 supplied screenshots (37 scenes in light and dark) and inventoried the additional views, sheets, menus, confirmations, and state branches in source. The current source inventory is in [SCREEN_COVERAGE.md](./SCREEN_COVERAGE.md#native-source-coverage--30-october-2026); the older prototype inventory below it is historical.

### Changes

- [Shared design primitives](../App/LocalMinutesDesign.swift): consistent page insets, reading width, system text styles, full-height buttons, error symbols, compact task sheets, adaptive action rows and metadata. Accessibility text uses native menu pickers instead of compressed segments. Custom chrome becomes opaque for Reduce Transparency and Increase Contrast; cards gain an outline for Increase Contrast. Press/disclosure feedback continues to respect Reduce Motion.
- [Recording](../App/RecordingControlsView.swift): a focused idle recording surface; a compact, pinned timer and Stop control while recording; a smaller header in landscape and at accessibility text sizes; consistent transcript text; accurate preparation and stopping labels. The app-owned capture and transcript auto-follow behavior are preserved.
- [Meetings](../App/LocalMinutesHomeView.swift) and [detail](../App/MeetingDetailView.swift): clearer history rows, a direct route to recording, meaningful durations for short recordings, a pinned content picker, grouped notes with an adjacent edit action, search-empty guidance, and a focused rename sheet with keyboard submission and duplicate-save prevention.
- [Summary and questions](../App/MeetingIntelligenceView.swift), [reading](../App/SummaryReadingView.swift), and [notes](../App/MeetingNotesView.swift): consistent reading surfaces and editing actions, no artificial gap before Edit notes, a single grouped empty-summary action, native keyboard dismissal, legible editor surfaces, explicit confirmation before replacing a conflicted draft, and no empty summary section headings. Original-versus-edited content handling, justification, citations, and save ownership are preserved.
- [Models](../App/ModelBrowserView.swift): full model names in details, readable selection status, “Use model” wording, stacked variant metadata, adaptive actions, clearly distinguished Remove controls, contrast-correct button text in dark mode, accessible technical values, and clearer transfer hierarchy. The pinned catalogue, verified downloads, and selection/removal logic are unchanged.
- [Backup and restore](../App/LibraryActionsView.swift), [export](../App/MeetingExportView.swift), and [settings](../App/LocalMinutesSettingsView.swift): coherent sheet sizing, full-size export choices, inline export failure feedback, grouped settings rows, branded About content, and distinct complete/incomplete storage-check symbols.
- [Permissions](../App/RecordingPermissionsView.swift), [generation progress](../App/IntelligenceProgressView.swift), and [Live Activity controls](../Shared/RecordingActivityControls.swift): shorter grouped guidance, adaptive status values, stronger progress hierarchy, and compact readable recording status.
- Meeting deletion (both entry points), model removal, summary reset/deletion, and backup restore use native alerts with explicit Cancel buttons. Multi-action menus, system sharing, Files, and the microphone prompt remain system controls. No confirmation is added to routine recording, editing, or sharing entry points.

### API grounding

Consulted Apple's current [Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts) and [Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets) guidance, plus the official SwiftUI documentation for [ViewThatFits](https://developer.apple.com/documentation/swiftui/viewthatfits), [presentationDetents](https://developer.apple.com/documentation/swiftui/view/presentationdetents(_:)), [presentationDragIndicator](https://developer.apple.com/documentation/swiftui/view/presentationdragindicator(_:)), [pinned LazyVStack headers](https://developer.apple.com/documentation/swiftui/lazyvstack/init(alignment:spacing:pinnedviews:content:)), [Reduce Transparency](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducetransparency), and [color scheme contrast](https://developer.apple.com/documentation/swiftui/environmentvalues/colorschemecontrast). These APIs are available within the project's iOS 18 minimum; no iOS 26/27-only API was introduced.

### Validation and limits

- Swift grammar comparison against HEAD: no syntax errors in the 17 modified/new Swift files, including the new native UI tests. This uses a parser, not the Swift compiler.
- No editor diagnostics were reported, and whitespace/diff checks passed. The modified native artifact-boundary JavaScript test passes Node syntax checking.
- Calculated contrast for custom enabled button colors: 5.51:1 for light primary, 9.10:1 for dark primary, at least 4.52:1 for light secondary blue, and 4.66:1 for light destructive text over its tint on the app background. Disabled and pressed states are separate. System materials and text still require device review.
- Added [native interaction regressions](../Tests/NativeUITests/DesignInteractionUITests.swift) for visible Cancel actions, retaining meetings/summaries/models after cancellation, and meeting/export controls at accessibility text size 5. Updated the [recording regression](../Tests/NativeUITests/RecordingControlsUITests.swift) to check that the compact pinned timer and Stop control do not overlap and stay above the content picker. The new accessibility fixture is DEBUG-only and covered by the existing Release-boundary marker check.
- **Not executed:** Xcode build/type checking, app-hosted XCTest, native UI tests, the compiled artifact-boundary test, new simulator screenshots, VoiceOver, or physical iPhone testing. This Windows host has no Xcode/iOS SDK or registered XCTest controller. Existing screenshots are evidence of the previous build, not the modified layouts. Their manifest reports an iOS 26.2 simulator; the user's test device is an iPhone 17 Pro on iOS 27.2 (user-reported).

Next native validation: run the existing LocalMinutesFocusedValidation and LocalMinutesUIValidation schemes on a prepared macOS/Xcode host; recapture the 37 catalogued scenes in both appearances; manually cover the additional source states in the inventory. Check portrait/landscape, long meeting/model names, long transcript and summary content, keyboard-visible editors, accessibility text sizes, Reduce Motion, Reduce Transparency, and Increase Contrast on the user's device. No branch was created, and no push or GitHub Actions run was performed.

## Earlier implementation — 26 October 2026

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

- 99 repository Node tests passed using node --test scripts/tests/*.test.mjs, including preservation of logs larger than 4 MB, errors after individual compiler lines over 64 KiB, job annotations, and partial diagnostic API failures.
- Swift grammar comparison found no additional errors in changed/new Swift files. Two existing files have baseline parser limitations around conditional/concurrent syntax; this check is not Swift type-checking.
- Whitespace/diff checks passed.
- The IPA workflow's Bash build step passed syntax checking and four mocked success/failure paths, including an unavailable result bundle and a failing diagnostic command. These checks verify that diagnostic collection preserves the original build exit status; they do not run Xcode.
- Added native regression tests for notes saved after navigation, rapid edits, failed saves, original-versus-edited summary presentation, and citation navigation. Existing UI tests were updated for the new screen structure.

**Native build follow-up:** A hosted Release build at a9d638efb5432ed2bdd036ab07ba602363abc03b reproduced a Swift 6.2.3 IR-generation crash in the generated function `$sSSScA_pSgIeAghgg_SSIeAghn_TR`. This matches [Swift compiler issue #82491](https://github.com/swiftlang/swift/issues/82491), including its exact crash symbol and computed-binding pattern. [MeetingNotesView.swift](../App/MeetingNotesView.swift) now passes an explicit setter closure instead of a bound method reference, following the reported workaround. Earlier corrections to the repository lookup Section initializer and recursive model-download destination remain in place.

The [IPA workflow](../.github/workflows/build-ipa.yml) emits full Xcode build output and result-bundle diagnostics. The ordinary GitHub CLI log formatter truncated this run at an 81 KB compiler-output line, hiding the later crash. The [download helper](../scripts/github-transfer.mjs) now fetches raw job logs and check annotations, strips terminal controls, and preserves retrieval errors. Live validation against the actual failed run confirmed that the long line, later crash backtrace, and job annotations were saved locally before deleting only that diagnostic run.

The setter correction has not yet been built by Xcode because the hosted workflow requires pushed commits; no commit or push was made by the agent. Script tests and successful diagnostic retrieval do not establish that the corrected native build passes.

**Not run:** app-hosted XCTest, simulator UI tests, native screenshot capture, VoiceOver, or on-device recording. This environment is Windows and has no Xcode/iOS SDK. Editor diagnostics and grammar parsing do not establish that the corrected native build passes.

On a macOS/Xcode host, prepare the project's native dependencies and XcodeGen project using the existing README instructions, then run the LocalMinutesUIValidation and LocalMinutesFocusedValidation schemes. Re-capture all 41 scenes in both appearances and review the native layouts before shipping. Existing screenshots are from the previous UI and were not overwritten.
