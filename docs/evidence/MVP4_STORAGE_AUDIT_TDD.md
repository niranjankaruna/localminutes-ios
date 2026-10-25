# MVP4 T12.1a — owner storage metadata export

The Windows/iLoader owner cannot launch the compiled physical XCTest scheme.
The existing recording report does not contain actual protection/backup metadata.
Expose a bounded, read-only report with actual OS facts and no private paths,
names, transcript/audio/model content, or claimed physical-device verdict.

## RED

Prepared seven real temporary-filesystem cases in
`Tests/CoreTests/StorageAuditTests.swift`, seven app-hosted cases in
`Tests/NativeAppTests/NativeStoragePrivacyReportTests.swift`, and one actual UI
case in `Tests/NativeUITests/StoragePrivacyReportUITests.swift`.
At the test-first source, `Core/StorageAudit.swift` returned an empty
`.notInspected` report and `App/StoragePrivacyReport.swift` threw `.notReady`.
No inspector, native service or UI behavior was implemented before its
respective hosted behavioral RED.

Command: workflow `core-tests.yml`, mode `mvp4-storage`; actual hosted
`swift test --filter 'CoreTests[.]StorageAuditTests'` and selected iOS app/UI cases.
Source `e9b1701cb81e0fb5f0a84f608f7c7598cd917449`, pushed before implementation.
Run40184895367, Core job121143513139: actual seven cases executed, two passed,
five failed with28 assertion failures,0 skipped,3.135 seconds. The real39-item
fixture received0 inspected items and `.notInspected` instead of `.complete`;
roles, missing/unsafe roots and limits also failed. This is behavioral RED after
successful compilation.

Same source/run, native job121143513071: seven cases executed, two passed,
five failed with18 failures (three unexpected stub errors),0 skipped,1.033s.
Ready/export threw `.notReady`; actual active recording snapshots expected
`.recordingActive` and actual held heavy/maintenance leases expected `.busy`.
The report was absent, not a compiler/tool failure.

Same source/run, UI job121143513055: one actual screen case failed its assertion
that Models exposes **Prepare storage check**,67.770s,0 skipped. This was after
the real persisted library fixture and Models navigation loaded.
The overall run is terminal FAILURE as expected for the missing behavior.
Compile errors or zero executed tests are not RED.
Only standard public macOS runners; no model weights/quality jobs.

## GREEN

RED is recorded above. Inspector, guarded service and explicit Prepare/Share UI
are implemented and reviewed by root plus an independent Medium agent; actual
hosted GREEN/package is pending. Model/inference/capture/persistent-policy source
is unchanged. Release metadata advances both bundles to build5; the two existing
exact-build packaging assertions advance4→5 together without changing their
oracles. The new Swift tests and all historical physical tests are unchanged.

The next focused batch selects7 Core,15 app-hosted cases (new7 plus8 existing
storage/admission regressions),3 UI cases (new1 plus2 existing model-accessibility
cases),46 script checks and actual Release packaging/3 native-hygiene checks.
No full suite or model-quality benchmark. A Windows-only script attempt failed
on OS symlink permissions (EPERM); this is not behavioral RED or GREEN and is
not used as platform evidence. Those unchanged checks run on hosted macOS.
Actual GREEN: source `3273fb20401023fd8095d36c7007923aa42d7bca`,
[run40186443609](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40186443609)
terminal SUCCESS.7 Core PASS0fail/skip0.422s;46 scripts PASS;15 app-hosted
PASS0fail/skip1.280s;3 actual UI PASS0fail/skip209.543s; actual Release iPhone
app/extension build5 and3 IPA-native-hygiene cases PASS. Owner-only unpublished
draft retains14,925,881-byte IPA, SHA256
`66cce1440d83dfaf6c93b528b0fb1b3f6d558780c271c2f7eb3db7c215d5238f`.
Downloaded Windows bytes match manifest/checksum and GitHub asset digest;
CRC/canonical entries/source/build/IDs/arm64 iPhoneOS app+extension, exact
dependency pins/receipt and bundled notices independently verified. Local
directory `build/delivery/MVP4-Storage-40186443609`. This storage slice is
CODE_COMPLETE_PENDING_DEVICE; other final functional gaps have separate TDD.
No physical claims.

## Review and continuation

Report must distinguish Simulator/device provenance and incomplete/unreadable/
unsafe/limited observations. Read-only enumeration must remain bounded and reject
symlinks. Native admission must preserve capture, heavy operations and library
maintenance. Sharing requires the owner's explicit action. Actual original
seven physical protection tests remain unchanged and NOT_RUN; an exported audit
does not imply those tests executed or prove locked access/real-time inference.
Storage code, focused GREEN and candidate-byte verification are complete.
Next: retain this compatible evidence while the separately recorded final gaps
reach the combined build6 gate, then deliver the complete MVP4 development IPA.
No model-quality or full-suite run per edit is requested.
