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
`Core/StorageAudit.swift` returns only an empty `.notInspected` report;
`App/StoragePrivacyReport.swift` throws `.notReady`. No inspector or UI behavior
is implemented before hosted assertion RED.

Command: workflow `core-tests.yml`, mode `mvp4-storage`; actual hosted
`swift test --filter 'CoreTests[.]StorageAuditTests'` and selected iOS app/UI cases.
Source `e9b1701cb81e0fb5f0a84f608f7c7598cd917449`, pushed before implementation.
Run40184895367, Core job121143513139: actual seven cases executed, two passed,
five failed with28 assertion failures,0 skipped,3.135 seconds. The real39-item
fixture received0 inspected items and `.notInspected` instead of `.complete`;
roles, missing/unsafe roots and limits also failed. This is behavioral RED after
successful compilation. Native/UI outcomes remain pending. Compile errors or
zero executed tests are not RED.
Only standard public macOS runners; no model weights/quality jobs.

## GREEN

Pending actual RED and implementation. No physical claims.

## Review and continuation

Report must distinguish Simulator/device provenance and incomplete/unreadable/
unsafe/limited observations. Read-only enumeration must remain bounded and reject
symlinks. Native admission must preserve capture, heavy operations and library
maintenance. Sharing requires the owner's explicit action. Actual original
seven physical protection tests remain unchanged and NOT_RUN; an exported audit
does not imply those tests executed or prove locked access/real-time inference.
Next: commit/push prepared tests, obtain actual hosted RED, then implement.
