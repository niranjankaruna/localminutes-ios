# T04 app/extension and unsigned package TDD evidence

Requirements: R03; task children T04.1–T04.4 retain the complete parent scope.
No iOS app, real adapter, model or retained IPA exists at the start of this slice.

## T04.1 RED — observed locally and verified on hosted macOS

Acceptance: device app/extension IDs and configuration are checked; arm64
simulator products and unsafe archive paths are rejected; real file checksums
are verified. Unit boundary fixtures are synthetic metadata/log formats, not
claimed native build evidence. Apple-tool collection is an injected boundary;
real adapter integration must later read actual compiled device products.

Tests: `scripts/tests/ios-artifacts.test.mjs`; minimal validator/collector/hash
interfaces in `scripts/ios-artifacts.mjs` deliberately have no behavior.
Command: `node --test scripts/tests/ios-artifacts.test.mjs`, Windows Node v24.21.0.
Expected: valid metadata is rejected as not implemented; hash is empty; negative
cases fail their required error assertions. Actual result: **25 executed,
0 passed, 25 failed, 0 skipped**, exit 1. Checksum assertion observed an empty
string rather than the known SHA-256 of a real temporary `abc` file. Metadata
and rejection tests reached the compiling module and failed for missing
validation behavior, not syntax, tools or test discovery.

Production behavior will follow only observed RED and its pushed test-first
commit. Current workflow discovers all scripts/tests unit files; no failure is
hidden. Native build/configuration and packaging need their own real integration
RED/GREEN. Artifact delivery remains blocked on storage headroom verification.

Hosted confirmation: test-first source
`4ef9d870253c363106c141ff9b5b96986e8143bf`, run
[39979891163](https://github.com/niranjankaruna/localminutes-ios/actions/runs/39979891163),
completed 15:39:10 UTC. Actual: **20 XCTest passed; 33 Node tests executed,
8 passed, 25 failed, 0 skipped**, exit 1. Always-run XCTest evidence reporting
also passed. This is missing validation behavior, not a compile/tool failure.

## T04.1 expanded RED — local observation before implementation

Read-only review identified missing mixed-platform, package/executable, exact
native-tool argument and canonical-path cases. Expanded tests now contain
35 cases. Windows command `node --test scripts/tests/ios-artifacts.test.mjs`
actually executed **35, 0 passed, 35 failed, 0 skipped**, exit 1. The real-file
hash assertion still observed empty output instead of the known SHA-256. No
production validation has been written. The next test-first commit preserves
these assertions and will be pushed before implementation.

Boundary limitation: archive entry strings validate names and structure, not
ZIP entry types or symlink targets. T04.3 must test the real packaging input
for links, then inspect the actual created archive; these fixtures do not
establish native-build or symlink safety.

Hosted expanded RED: source `5f962d6d72eab6a35eb378771cda64e473da77b3`,
run [39981007435](https://github.com/niranjankaruna/localminutes-ios/actions/runs/39981007435),
completed 15:48:22 UTC. **20 XCTest passed; 43 Node executed, 8 passed,
35 failed, 0 skipped.** No validation behavior existed in this source.

## T04.1 implementation / T04.2 native RED preparation

After the pushed RED above, implemented metadata validation, canonical archive
names, bounded direct native-tool invocation without a shell, and streaming
SHA-256 verification. Windows regression command
`node --test --test-reporter=tap scripts/tests/*.test.mjs`: **43 passed,
0 failed, 0 skipped**. This is local script GREEN only; exact source hosted
GREEN remains pending.

T04.2 requirement R03 observable acceptance: two native tests must inspect
real processed app/extension plists and Mach-O build-platform load commands,
matching versions and subordinate stable bundle IDs. Both device Release and
simulator Debug builds must actually succeed. The device test must then fail
with `Compiled app must enable Live Activities before this native gate can pass`
because the minimal configuration has `NSSupportsLiveActivities: false`.
The second test rejects real simulator products for device packaging. Native
missing-tool/compile failures will not be recorded as RED.

Minimal compiling interfaces only: app-owned coordinator, SwiftUI text entry,
shared Codable/Hashable ActivityAttributes and WidgetBundle/ActivityConfiguration
presentation. There is no recording adapter, Action Button, Stop control,
inference, meeting UI, signing, installation or runtime activity proof yet.
XcodeGen archive is pinned to publisher SHA and size, verified before execution.
Native job is bounded to 15 minutes after the 10-minute core job; no upload or
cache allocation. Existing included quota and $0 hard stop remain in force.

## T04.1 GREEN / T04.2 RED — verified native products

Source `2711186a6ed71de089838900ee4c63cbe78397ce`, run
[39981859388](https://github.com/niranjankaruna/localminutes-ios/actions/runs/39981859388),
completed 15:56:15 UTC. Core job GREEN: **20 XCTest and 43 Node tests passed,
0 failed/skipped**. This verifies T04.1 implementation at the exact source.
Pinned XcodeGen archive passed actual SHA-256 and byte-size checks; runtime
reported Version: 2.46.0. Actual device Release and simulator Debug app+extension
builds both succeeded using Xcode26.2, SDK26.2, no signing.
Native integration: **2 executed, 1 passed, 1 failed, 0 skipped**. Device test
failed the intended assertion `Compiled app must enable Live Activities before
this native gate can pass`, actual false vs expected true. The simulator test
passed and rejected the real simulator executable as a device package. This
is native configuration RED after working compilation, not missing tools.
The minimal interfaces are not a recording feature or installable release.

T04.1 review: independent read-only diff review found no blocking issue in
validation or process invocation. Simulator metadata coverage was strengthened
before the native RED push. Archive names remain a names-only boundary; T04.3
must verify actual ZIP types, real bytes and input links.

## T04.2 implementation / T04.3 RED preparation

After the native RED above, change only NSSupportsLiveActivities to true.
The next commit also adds an unimplemented packaging interface plus **13 native
packaging tests**. These will fail after the two existing build checks pass.
No packaging implementation or source-stamp behavior exists yet. Expected
positive failure: no real IPA/manifest is produced. Negative assertions require
specific rejection of simulator input, wrong Git/source stamps, symlinks,
signing/private fixtures and existing outputs. Archive inspection uses a real
ZIP standard-library reader, CRC checks and executable hashes compared with
actual compiled device binaries. All added fixture content is synthetic.
The exact source and native RED counts will be recorded after the hosted run.

## T04.2 GREEN / T04.3 RED — verified

Test-first source `a3f5849d882dbb4bb1dea43028e12f5ed7e63837`, run
[39983105414](https://github.com/niranjankaruna/localminutes-ios/actions/runs/39983105414),
completed 16:04:56 UTC. Both real device/simulator builds and **both native
configuration tests passed**. Core regressions also passed (20 XCTest and
43 Node). Packaging command `node --test scripts/native-tests/package.test.mjs`
executed **13 tests, 0 passed, 13 failed, 0 skipped**, exit 1. Actual failures
were `T04.3 not implemented` from the minimal interface, including the positive
real-archive case and specific error assertions. Real build files were available;
this was not a missing SDK, fixture, compile or discovery failure.

The tests-first commit was pushed before any packaging behavior. Review added
independent device Info.plist byte hashes, exact archive byte size, nested
extension links/private files, output containment and recursive-output rejection.
T04.3 implementation begins only after this recorded native RED. No IPA exists
from this failing run. T04.4 retention is still blocked by storage headroom.

## T04.3 implementation prepared after RED

Added actual app-tree audit with recursive link/private/signing rejection,
workspace/output containment, source verification against Git and processed
app/extension stamps, direct unsigned-signature inspection, device validation,
staged copying, ZIP creation and central-directory/CRC inspection, then an
archive SHA-256, companion checksum and source/build manifest. Only owned,
resolved workspace directories may be cleaned up. Native processes use direct
argument arrays, bounded timeouts and no shell interpolation. No meeting/model
files, Apple credentials, entitlement changes or artifact uploads were added.

Source stamp settings are passed to both actual Xcode builds; old/misattributed
products are rejected. Windows script regressions remain **43/43 passed**;
syntax inspection is not native packaging GREEN. Exact-source macOS validation
is pending the sixth allowed run. The final workflow step creates a real IPA
on the ephemeral runner and logs only its manifest/checksum; no retained
artifact or download link is claimed.

`docs/WINDOWS_INSTALL.md` was drafted from current official Sideloadly and Apple
sources and independently checked. It is installation guidance, not observed
signing/device evidence. Extension and renewal gates remain NOT_RUN.

## T04.3 review regressions — meaningful Windows RED before fixes

Independent review found missing database sidecar/private-directory rejection
and canonical output containment through an ancestor alias. Added
`scripts/tests/package-audit.test.mjs` before fixing either. Existing audit/path
logic was exposed as a portable boundary without changing its behavior.
Fixtures are ordinary synthetic files, not plists/binaries or native evidence.

Command: `node --test --test-reporter=tap scripts/tests/package-audit.test.mjs`,
Windows 11 / Node24.21.0. Actual **8 executed, 1 passed, 7 failed, 0 skipped**.
Every failure is `Missing expected exception`: .db-wal/.db-shm, transcripts,
recordings, device-evidence, diagnostics-raw, and an output ancestor junction
resolving into the input app. The initial sandbox denied junction creation;
that tool error was NOT RED. Authorized execution outside the sandbox created
and removed only the owned workspace fixture junction and proved the actual
alias assertion failure. Full script suite: **51 executed, 44 passed, 7 failed,
0 skipped**, exit 1. No tests were skipped or weakened.

This regression test-first change will be the sixth/final new CI run. Fixes
follow only its push. Native archive GREEN and actual IPA creation may therefore
remain pending the next invocation; no seventh run is authorized here. The
partial implementation has not produced an IPA or passed the 13 native archive
tests. Preserve all failed runs and continue from this precise checkpoint.
