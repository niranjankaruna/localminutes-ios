# T12 persistent-file privacy — native test-first gate

Seven native cases are activated from docs/drafts/T12Privacy/ before policy
implementation. They require actual iOS metadata on default app roots,
verified model imports, SQLite/WAL/SHM/recreation, CAF/checkpoint creation and
symlink safety. No mocked filesystem/inference and no owner meeting data.
The existing ModelStoragePolicy.protectPersistentDirectory still throws
notImplemented. Root/default constructors do not yet establish the policy.

Actual SDK RED is required before implementing protection/exclusion. Compile
failure or absent cases will not count. Hosted simulator metadata cannot prove
physical locking, encryption, backup-network behavior or signing renewal.
All owner-run physical gates remain NOT_RUN. Next: final permitted invocation
run compiles the new native tests, records exact result, then implement only
after meaningful assertion RED and preserve a checkpoint if CI budget is used.

## First compatible run — compiler issue, NOT RED

Exact source7659a1980b53fc17d624973c6666d83084234ab6, run40036438183 is
terminal FAILED. Actual Release iPhoneOS and Debug simulator app/extension
compilation succeeded. Native app/UI test bundles did not compile: the new
fixture used FileManager.setAttributes(_:atPath:) twice; the actual SDK requires
setAttributes(_:ofItemAtPath:). xcresult reports0test cases. This is NOT RED and
does not authorize privacy implementation. The two argument labels are repaired
without altering assertions; policy remains notImplemented.

Continuation07's next test-first run must execute all seven native cases plus
the original lifecycle cases and eight new playback ownership cases. Native
build now runs independently of the core test-first job; core, native and actual
summary jobs are still mandatory and any failure fails the overall workflow.
No mandatory test is skipped or ignored, no artifact is uploaded and no signing
or locked-device result is inferred. Full ignored log:
.agent-local/T12-7659a19-terminal.log.
