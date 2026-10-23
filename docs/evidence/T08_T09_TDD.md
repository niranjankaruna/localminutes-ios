# T08.1 / T09.1 test-first model and meeting persistence slice

Acceptance: the 23 model-installation cases exercise actual file sizes/hashes,
atomic replacement, cancellation, ownership, leases and persisted immutable
metadata. The 15 meeting-store cases exercise an actual SQLite file, schema,
reopening, ordered durable transcript rows, transaction rollback, scoped literal
search and owned deletion. Synthetic bytes/text are original non-sensitive test
data. None is an inference substitute. Actual speech-model evidence is separate
in T10_CANDIDATE.md.

Tests are activated from the reviewed agent drafts without weakening assertions.
Models/ModelInstallationManager.swift and Persistence/SQLiteMeetingStore.swift
remain no-op interfaces. Metadata value constructors and the immutable expected
manifest do not install models or establish recognizer readiness. Production
installation/database behavior is prohibited until actual compatible-host
assertion RED is recorded at the pushed test-first source.

Command: swift test --enable-code-coverage on standard public macos-15-intel,
Xcode26.2. Strict reporting requires all 38 new case names plus prior mandatory
regressions. Expected full discovery:153, not yet observed. Compilation failures,
zero tests and timeouts are not RED. No hosted test result is claimed yet.

Invocation: 2026-10-23-continuation-06, maximum six new runs, one active per
branch. The prior turn made concrete progress: real CPU recognition, verified
public visibility, saved native regression repair and complete test-first drafts.
Current PUBLIC status and authenticated owner were reverified before dispatch;
the officially free standard runner and zero additional-spend policy apply.
No new infrastructure, billing change, model/audio upload or larger runner.

Root integrates and runs CI. Agents may implement their disjoint active source
files only after root supplies actual RED. The native Toggle repair already has
its separate prior RED; it is folded into later complete native regressions.
Full automated GREEN and every unobserved phone gate remain pending. The owner
runs both required125minute physical endurance tests manually.

RED source/run/assertion result: PENDING.
GREEN source/run/result: PENDING.

First sourcef6fb5247bae80aea20a915a00f78634457888d01/run40032541662
failed compilation: XCTestCase.record shadows the test-only global record
fixture helper. Zero tests executed; this is NOT RED. Rename only that helper
and its calls to meetingFixtureRecord; all assertions/no-op production unchanged.
Next run must actually execute the153-case suite before implementation.

## RED — verified before implementation

Source9cb7639fca2d9d50c2e3106a678e267ad104974f,
[run40032742242](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40032742242),
standard macos-15-intel/Xcode26.2:153 actual XCTest executed,116passed,
37failed,77 failure assertions (12 uncaught notImplemented errors),0skipped.
All prior115 cases plus immutable-manifest metadata passed. All22 installer
behavior cases and all15 SQLite cases failed. Strict reporter required their
complete named inventory and agrees with the aggregate. The helper collision
was corrected only by renaming record to meetingFixtureRecord; no assertion
was removed or changed.

Examples of observable RED: actual database file is absent; reopened meeting
is nil; ordered transcript rows are empty; conflicting batches are accepted;
installer returns notImplemented instead of typed checksum/missing-file errors
or a persistent verified installation. These are missing behaviors after
successful compilation, not a tool or zero-test failure. Model bytes remain
synthetic integrity fixtures; no inference claim is derived from them.
Command: swift test --enable-code-coverage. Ignored full log:
.agent-local/T08_T09-9cb7639-red.log. Node/TSAN/native jobs did not execute after
the Swift assertion failure. Root may now authorize implementation in Models
and Persistence only, then require focused and full exact-source GREEN.
