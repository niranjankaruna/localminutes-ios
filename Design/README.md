# LocalMinutes — Apple-style redesign

Interactive FigCraft reference for the native SwiftUI redesign now implemented in [App](../App). See [implementation status](./IMPLEMENTATION.md) for scope and validation limits.

The prototype is based on the 41 screenshot scenes in both appearances and the Swift application source. It uses editable layers and semantic light/dark color variables. Sample meeting content and device/model measurements are illustrative; recording, inference, downloads, file selection, and system sharing are simulated.

Open `LocalMinutes-Apple-Redesign.figcraft` in FigCraft and present the **Start here** flow. The review launcher provides light and dark appearances, core journeys, and a screen index for secondary states.

## Design direction

- Meetings, Record, and Settings separate frequent work from setup.
- Summary, Transcript, Notes, and Ask give each meeting task a focused view.
- Recording shows one relevant start/stop control. There is no invented pause feature.
- Required model setup, permissions, recovery, and failures appear when needed.
- Source revisions, runtime details, and diagnostics are available one level deeper.
- Export distinguishes original meeting content from generated summaries and answers.

## Review boundaries

This is a clickable design, not a running app. Text-entry screens show sample input and simulated keyboard states. File pickers and share sheets represent iOS-owned interfaces. SF Pro is not installed in this Windows FigCraft environment, so editable Inter is used as a review fallback; the native app should continue using system typography and Dynamic Type.

The native implementation uses system fonts, real controllers, and system-owned file, permission, and share interfaces. The FigCraft file remains a simulated design reference.

See [screen coverage](./SCREEN_COVERAGE.md) for all 41 original scenes and [validation](./VALIDATION.md) for the click-through and layout checks. The file contains 116 application/system states in each appearance, a review launcher, a complete screen index, and a foundations page. Press **R** in the prototype to return to the launcher.
