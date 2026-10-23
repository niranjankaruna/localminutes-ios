# T16 owned deletion and note/selection regressions — test-first

Requirements R08/R11/R12. Ten new cases use actual SQLite and native CAF:
six owned deletion/recovery cases, two immutable note identity cases and two
rename projection races. Tests remain active alongside all existing cases.
Only no-op deletion/usage/bound-note APIs and a nil-by-default post-real-SQLite
read scheduling seam were added. No deletion, admission or race repair exists
before actual compatible RED.

Deletion must remove one confirmed, unused UUID-owned meeting's metadata,
original notes, transcript and audio while preserving other meetings/models.
Reject external/nested symlinks and mismatched session manifests. A real closed
database must prevent any move; a real metadata failure after quarantine must
leave a durable request recoverable by a new coordinator after reopen.

Delayed notes must retain the originating UUID/revision and never alter another
selection's visible data or error. A held rename result must not replace a newer
selection, including A-to-B-to-A where UUID equality alone is insufficient.
Exact source-review findings: docs/drafts/T16Deletion/INTEGRATION_REVIEW.md.

Next: review and push the test-first source after the preceding native run is
terminal, record hosted assertions, then implement. No new test has yet compiled
or established RED/GREEN; existing source assertions were not weakened.
Native editor debounce/navigation and actual recording/playback usage wiring
still require their own integration evidence before handoff.
