# Blockers

No confirmed external blocker prevents the next harness task. T00 authentication
and repository bootstrap succeeded. A sandbox-only network error was resolved
by an authorized direct check; account billing read access was available in the
signed-in browser despite insufficient CLI billing scope.

Observation to track: account Actions storage displays 0.5 GB used / 0.5 GB
included. Artifact headroom is unverified. Initial CI can use test logs without
uploads; check headroom before attempting an IPA artifact. No unrelated artifacts
were deleted and no billing settings were changed. All device gates remain
NOT_RUN, not inferred blocked or passed before a candidate exists.

## Open implementation issue — T03.1 (not an external blocker)

Observed by independent review on 23 October 2026 at source
`9c39e5f6a44904dc5746fc31c6a1c5e3c9373fc2`: after activation is emitted,
interrupt is ignored while the phase is still preparing. A late readiness event
can then publish recording. Regression test was written before fixing it;
native RED is pending. Next implementation must handle that interruption with
one cleanup command, reject late readiness and preserve interrupted status.
No owner action or credential is needed. The sixth CI run is reserved for RED;
this invocation must checkpoint before a seventh run. No fix has been attempted.

For each blocker record: ID, first observed time, affected tasks/gates, exact sanitized error/evidence, hypotheses already tried, retry count, safe independent work, owner action if required, and resolution evidence. Missing authentication, unknown budget guard, and unavailable physical device must not trigger an endless retry loop.
