# T06.1.1 native compile repair checkpoint

Status: **IN_PROGRESS**, candidate only, outside active source paths. No applied
production fix, native compilation success or device result is claimed.

At e2876e8/run40004059233 the actual Swift6/iOS26.2 compiler rejects sending
the stored MainActor Activity reference to the SDK's nonisolated async update
and end methods. The core87 tests,59 scripts and53 repeated sanitizer cases
passed. This is a localized SDK isolation failure, not behavioral RED or an
external credential/device blocker. Zero compile repairs have been tested yet.

Apple's [Activity declaration](https://developer.apple.com/documentation/activitykit/activity)
has no documented Sendable conformance. Shared attributes/content are internal
UUID/String value structs that already qualify for implicit checked Sendable;
adding conformance there is not an evidenced receiver repair. The compiler
did not diagnose payloads, the state observer or observation-task deinit.

The candidate ActivityKitOperations.swift.pending passes only the immutable
[Activity.id](https://developer.apple.com/documentation/activitykit/activity/id)
and Sendable display status into nonisolated async functions. Each obtains the
exact matching SDK reference through documented
[Activity.activities](https://developer.apple.com/documentation/activitykit/activity/activities),
constructs content there, awaits the SDK operation, and returns a checked value.
It never selects another activity by meeting ID or by list position. No actor
reference, actor-bound closure or unchecked concurrency conformance is sent.

A missing lookup is explicitly notFound, not a performed SDK end. The current
handle protocol returns Void, so this candidate must not simply be pasted into
the active wrapper and silently discard that outcome. Its error/cleanup policy
requires regression tests before integration. Apple documents current activity
lookup but not an atomic relationship between lookup, retained state and async
end; source inspection alone cannot establish that relationship on a phone.

Exact next task T06.1.1: recheck private Git/CI and free allowance in the next
invocation; add checked SDK-operation outcome contracts and failing tests proving
that a missing/mismatched handle cannot become an end-success acknowledgement,
that a failed end remains observable/retryable, and that matching successful
operations retain the existing async ordering. Prove/push hosted RED, integrate
the ID-only native boundary, then require all focused/regression/sanitizer tests
and actual device/simulator app+extension/package GREEN at the exact SHA.
Existing nine lifecycle tests must remain unchanged in strength. First native
repair attempt remains uncompiled; preserve the failed run. T06.2 app ownership,
recording intents and foreground fallback follow only after this gate succeeds.

Six of six continuation-03 runs are terminal; no seventh run/re-run is allowed.
Do not reset that ledger during compaction, push active changes that dispatch
another run, weaken concurrency checking or claim an IPA exists at e2876e8.
