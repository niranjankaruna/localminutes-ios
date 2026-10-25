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

Implementation checkpoint: compact native installed rows now collapse artifact details; Apple availability/selection, FoundationModels runtime composition and source validation are implemented locally. Additional fresh-startup binding and bundled descriptor tests are committed before implementing the service binding. These must produce actual hosted results; no simulator Apple inference is claimed.

SDK repair (not behavioral RED/GREEN): native job 121238932959 in run 40216588328 at 7cb82d4 failed compilation because String? and Bool? do not conform to Generable for DynamicGenerationSchema.init(type:guides:) in Xcode 26.2. The remaining iPhone job was cancelled during native-framework preparation because the same source cannot compile. Logs and failed job remain preserved. Apple documents optional dynamic properties from iOS 26.0, while explicit-null schemas and representNilExplicitlyInGeneratedContent begin at 26.4. The correction uses optional properties and a new test-first JSON bridge contract. Omitted owners/dates must become explicit unknown nulls without adding facts; malformed/oversized output must fail. The JSON bridge remains a no-op stub until actual behavioral RED. Fresh system-selection startup is also still unimplemented pending its committed assertion.

## Apple optional-JSON behavioral RED

Source 6d95c74975ee5584c421c057604cc2c04652f73b, run 40217546023 / native job 121241866043 compiled successfully after the SDK repair. Three AppleGeneratedJSONTests executed: one passed, two failed with four assertions, zero skips, 0.782 seconds. The no-op bridge omitted unknown owner/due keys and accepted malformed/65,537-byte output. This is genuine behavioral RED, committed/pushed before bridge implementation; the source-preservation case already passed. The 12 real v2/v3 cases and 195 independent regressions passed in that job. The iPhone build/startup assertion remains pending.

## Mixed native-bundle verification regression

The existing log helper also failed with `XCTest case count mismatch` in original run 40213241251 because app-unit and UI bundles each print Selected/All aggregate roots. This does not change the actual app/UI failures in that run. Test-first commit 29061c7444d51c822a86987944b6e5efe3cde13d adds five regression cases: combine completed bundles, retain an earlier failed bundle, avoid duplicate-root counting, reject contradictory duplicate status, and reject a truncated later bundle. On Windows/Node 24.21.0, `node --test scripts/tests/verify-test-log.test.mjs` executed 21: 17 passed, four failed, zero skipped, 50.8055 ms. The failures are three count mismatches and one wrongly accepted contradictory root. Implementation and hosted RED are pending; original named-test, skip, truncation and failure checks will be retained.

## Native iPhone layout GREEN and Apple startup RED

At source 6d95c74975ee5584c421c057604cc2c04652f73b, run 40217546023 / job 121241865915: all six actual iPhone UI/accessibility cases passed, zero skips, 118.933 seconds. This includes both existing model actions at largest accessibility text with 44-point frames, progress/resume details, separate verification, Apple availability/selection row, removed sections and final device information. Native app tests executed 12: 11 passed, one fresh Apple startup case failed two assertions, zero skips, 7.491 seconds. Actual FoundationModels schema construction and local SQLite composition passed, as did the bundled v3 descriptor, five GGUF startup and four memory-warning regressions. Fresh Apple selection incorrectly bound nil IntelligenceSession, a genuine RED from the test committed before service binding. Actual Apple model generation on a phone remains NOT_RUN.

Hosted verifier RED: source 29061c7444d51c822a86987944b6e5efe3cde13d, run 40219610954 / job 121248107756: all 123 model cases passed, while script suite executed 67, 63 passed, four failed, zero skips. The failures reproduce the same four local log-aggregation assertions. After implementation, the unchanged focused verifier suite passed 21/21 locally, zero failures/skips, 55.7697 ms. Applying it to actual sanitized XCTest lines from the original native logs correctly retains run 40213241251 as 16 executed / 11 passed / five failed / nine assertions, and run 40217546023 as 18 executed / 17 passed / one failed / two assertions, zero skips. No historical failure is converted into GREEN.

Next: final exact-source tests and unsigned build 7. Native UI/schema/selection/storage validation does not pass real Apple inference or any physical-phone gate.
