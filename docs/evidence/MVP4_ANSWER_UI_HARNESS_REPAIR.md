# Build6 answer-screen navigation check

App source: `36bf6f4c8726fbc5d2efbfa4f740ef4031457233`.
Run40190643613 is terminal FAILURE, not hidden or relabelled. It passed76
related portable cases,46 scripts,116 app-hosted cases,4 history/information
screen cases and3 existing library screen cases. The Release app/extension,
3 actual-IPA hygiene cases and separate actual compiled Release/Debug fixture
oracles passed. Downloaded IPA/digests/CRC/source/version6/IDs/arm64/pins/notices
were independently verified. No new inference-quality or phone claim.

One new answer UI case failed2 assertions after293.557s: it had already passed
answer editing, explicit Save acknowledgment, meeting isolation and edited-value
checks after navigation/relaunch. The failures were the original manual-note
value wait (line69) and original transcript existence (line44).

Actual logs show `reveal` repeatedly dragging farther down while looking for
original notes above the current saved-answer position. SwiftUI's lazy List
omits offscreen elements; an absent element provides no useful frame/direction.
The same generic helper defaults downward through the document in that case.
Actual SQLite immutable-note/source tests and the separate library UI cases
passed. Diagnosis: an unsatisfied navigation precondition, not evidence of a
successful original-content check.

The harness-only fix first returns toward the known Meeting name section with
bounded down gestures, asserts that anchor is visible/hittable, then runs every
unchanged original notes/transcript assertion. No assertion, edit, Save,
navigation or relaunch check is removed. No production source changes.

Focused retry: `mvp4-answer-ui`, exactly one actual UI case. The job checks out
the reviewed app source above, fetches the workflow/harness revision, proves
zero differences in every production path/project/package pin, overlays only
the repaired test, and records APP_SOURCE separately from TEST_HARNESS_SOURCE.
The app build stamp remains the exact delivered source. It compiles only the
simulator validation app; it does not rebuild or replace the IPA, rerun the
passed suites, download model weights or run quality benchmarks.

Retry source/run/result: pending. Do not claim this check passed until actual
positive execution, or call the whole original run green.
