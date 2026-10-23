# T04 app/extension and unsigned package TDD evidence

Requirements: R03; task children T04.1–T04.4 retain the complete parent scope.
No iOS app, real adapter, model or retained IPA exists at the start of this slice.

## T04.1 RED — observed locally; hosted confirmation pending

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
