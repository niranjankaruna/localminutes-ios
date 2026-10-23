# Blockers

No confirmed external blocker prevents the next T03.1 code fix. T00 authentication
and repository bootstrap succeeded. A sandbox-only network error was resolved
by an authorized direct check; account billing read access was available in the
signed-in browser despite insufficient CLI billing scope.

Observation to track: account Actions storage displays 0.5 GB used / 0.5 GB
included. Artifact headroom is unverified. Initial CI can use test logs without
uploads; check headroom before attempting an IPA artifact. No unrelated artifacts
were deleted and no billing settings were changed. All device gates remain
NOT_RUN, not inferred blocked or passed before a candidate exists.

## ARTIFACT_STORAGE_HEADROOM_UNVERIFIED — external, artifact delivery only

- First observed: 23 October 2026, approximately 14:41 UTC; rechecked about 15:07 UTC.
- Affected: T04/T21 artifact upload and G03 IPA delivery; no effect on current
  core tests or native builds without uploads.
- Evidence: signed-in Actions overview displays 0.5 GB / 0.5 GB and rendered
  progress 100%. Rounded values do not establish any safe upload capacity.
- Attempts/retries: read-only observations only; zero uploads, billing changes
  or deletions attempted. The existing account Actions hard budget remains $0.
- Safe independent work: core behavior, native compilation/testing without
  uploads, local scripts and documentation.
- Owner action when an IPA is ready: free space by reviewing unneeded account
  artifacts, or wait for their expiration, then verify included storage headroom.
  No purchase, public repository or credential is requested.
- Resolution: pending. Never set candidateArtifact until a retained, checksummed
  artifact has actually been delivered and verified.

## Open implementation issue — T03.1 (not an external blocker)

Observed by independent review on 23 October 2026 at source
`9c39e5f6a44904dc5746fc31c6a1c5e3c9373fc2`: after activation is emitted,
interrupt is ignored while the phase is still preparing. A late readiness event
can then publish recording. Regression test was written before fixing it;
native RED is verified at `33cd7c6a88195998b6a5f15bb62cc9c6c415045a`, run
39976742123: 20 executed, 19 passed, 1 failed, 6 assertions, 0 skipped.
Next implementation must handle that interruption with
one cleanup command, reject late readiness and preserve interrupted status.
No owner action or credential is needed for the code fix. All six invocation
CI runs have completed; this invocation checkpoints without a seventh run.
No fix has been attempted. T03 remains IN_PROGRESS; main was not advanced.

For each blocker record: ID, first observed time, affected tasks/gates, exact sanitized error/evidence, hypotheses already tried, retry count, safe independent work, owner action if required, and resolution evidence. Missing authentication, unknown budget guard, and unavailable physical device must not trigger an endless retry loop.
