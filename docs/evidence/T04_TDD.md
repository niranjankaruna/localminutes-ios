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
