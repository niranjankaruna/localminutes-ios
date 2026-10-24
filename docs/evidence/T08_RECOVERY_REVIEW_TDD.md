# Recovery integrity and global-gap regressions

Source review after d699 identified shape-only journal acceptance, captured-count versus global-timeline inconsistency, and a header-only CAF readability check. Three new real-CAF/SQLite regressions retain all original8 test bodies. No journal/gap/decode production repair precedes actual new assertion RED. Captured sample count is distinct from timeline extent; existing playback already accepts totalFrames=sum(captured segments) with a global gap. The new test requires one same manifest to recover and seek without changing that valid old assertion. Exact schema decision and implementation follow observed RED.

Concurrent Start/Delete/recovery still needs one app-lifetime usage admission; snapshots and per-instance sets do not establish it. Startup must settle pending deletions first and enumerate beyond default100. These are explicit remaining T08 requirements, not fulfilled by current component tests.

Test-firstsource917844b016664251c545fb70106c50cfceb62694 pushed/remoteverified; actualcompatibleREDpending run40071855360. No newworkingbehaviorbeforeactualassertions.

## Actual hosted RED, 2026-10-24

Source `917844b016664251c545fb70106c50cfceb62694`, run
[40071855360](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40071855360),
completed core job `120806812209`, `swift test` on hosted macOS:
241 cases executed, 228 passed, 13 failed, 77 assertion failures (1 unexpected),
zero skipped. Recovery suite: 11 executed, original 8 passed, all new 3 failed,
20 assertions (1 unexpected). The explicit-gap manifest was rejected; altered
journals moved healthy audio or changed duration; a truncated CAF body was
counted as 12 durable frames instead of 8. These are behavioral failures after
successful compilation. The missing quarantine file is an unexpected assertion
error caused by the incorrect recovery result, not a build failure.

The schema decision is now explicit: manifest `totalFrames` is the sum of
captured segment frames; segment starts use one global timeline, whose extent
can include gaps. Recovery and playback must consume that same manifest.
Implementation is authorized only after this observed RED. Startup wiring and
shared admission remain separate unimplemented requirements.


39d9eaa/run40073883889: journal/gap regressions pass; every truncated-body recovery/report/quarantine/metadata assertion now passes. Three remaining assertions fail because the independent healthy-file observation helper requests beyond its four-frame EOF and labels the resulting native EOF error as corruption. Actual truncated observation is opened=true/header4/decoded1/readFailed=true. Correct the observer to request only bounded remaining declared frames and mark a short read as failure; preserve all assertions and actual decode/sample-count checks. Production full readback behavior is already correct for the exercised corpus.
