# T27: native iPhone Models page and Apple on-device summaries

Owner steering, 25 October 2026: use Figcraft MCP; remove Privacy and renewal and
Action Button sections; organize installed speech models; put This iPhone last;
list and support the built-in Apple Intelligence summary model. Owner rejected
the initial card design as Android-like and requested native iPhone styling.

## Design

The configured local Figcraft MCP was discovered at the owner's existing CLI.
Actual JSON-RPC initialize, tools/list, batch, save_file and export calls created
[the editable design](../../design/LocalMinutes-Models.figcraft) and
[its PNG](../../design/LocalMinutes-Models.png). The revised design uses iOS inset
grouped lists, compact rows, separators, system blue, checkmarks and chevrons.
The concept contains illustrative states, not observed installed models/device
results. Production uses SwiftUI system typography and controls.

## Acceptance and tests-first scope

- The real model screen exposes detailed progress, omits both removed sections,
  keeps installed model actions accessible and places device details last.
- Summary choices always list the Apple on-device model with real availability;
  selection is disabled with a reason when unavailable. It is not represented as
  downloaded weights or a fabricated checksum/model revision.
- Available system selection persists, respects active-work admission and can
  switch back to downloaded GGUF models without changing speech selection.
- System summary composition uses the same source validation, SQLite storage,
  cancellation and resource admission, without acquiring a downloaded-model lease.
  Apple supplies the actual on-device runtime. No cloud fallback or API key.
- Availability and native inference are distinct: simulator/unavailable-host
  checks cannot pass actual Apple model inference on the owner's phone.

RED source/runs/assertions: `1d2f290032bdebcc497d2701eb456caef887124c`,
[run 40213241251](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40213241251).
App-native: ten executed, nine passed, one failed assertion, zero skips,
1.801 seconds. The Apple summary composition failed `notImplemented` while all
five persisted-GGUF-startup and four memory-pressure cases passed. UI: six
executed, two legacy accessibility cases passed, four new progress/layout/Apple
cases failed with eight assertions, zero skips, 197.560 seconds. The missing
system row, device fields and progress labels are explicit failures.
The portable Apple-selection cases also failed their availability/admission
assertions in run 40212954360. These are genuine behavioral failures before
production system-summary or layout behavior. Native tests are
`ModelDownloadProgressUITests`, `AppleSummarySelectionTests`, and
`NativeAppleSummaryTests`. Compileable selection/session interfaces deliberately
implement no system-model behavior until hosted RED is observed.

GREEN, native availability, source SHA and device evidence: PENDING.
Next: observe original progress UI RED, push the added contracts/fixture, then
prove genuine Parakeet/Apple/layout failures before implementing those behaviors.
