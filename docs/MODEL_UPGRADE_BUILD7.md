# LocalMinutes 1.0 — build 7

Unsigned iPhone development candidate, delivered on 25 October 2026.
Physical-phone validation is still pending.

| Item | Verified value |
| --- | --- |
| App source | `6c02ccdd911017a613de2052e5fee1e611b953f7` |
| Version / build | 1.0 / 7 |
| Package | `LocalMinutes-1.0-6c02ccdd911017a613de2052e5fee1e611b953f7-unsigned.ipa` |
| Size | 15,088,983 bytes |
| SHA-256 | `4adfea3a38463b69423d58e4d8f1b2434f65ceeb2483e091eb26a0987ec0f967` |
| Minimum OS / architecture | iOS 18.0 / arm64 |
| App bundle ID | `com.niranjankaruna.localminutes` |
| Embedded extension | `com.niranjankaruna.localminutes.LiveActivity` |
| Signing | Unsigned; install with iLoader |

Local package and receipts are in `.agent-local/delivery/build7-6c02ccd/`.
The authenticated owner draft `mvp-preview-6c02ccdd9110` remains unpublished.
Both app and extension contain the verified build/source identity. The ZIP CRC,
package SHA-256 and dependency-receipt checksum pass. No model weights or meeting
files are bundled. The v3 model-pack descriptor is included.

## Changes

- Versioned Parakeet Core ML model packs with v2/v3 TDT contracts, preserved legacy
  v2 installation, immutable checksums/licenses and captured-model replay.
- Bounded file buffers during download and verification. The unchanged 512 MiB
  Darwin regression adds 40,960 bytes of peak memory at this exact source.
- Download bytes, percentage, speed, ETA, file/count, resumed bytes and distinct
  verification/installation stages.
- Native iPhone model rows with expandable file details, the requested section
  removals, and This iPhone at the end.
- Apple Intelligence summary/meeting-question provider with actual availability,
  persistent selection, on-device FoundationModels and OS-managed provenance.
  Actual Apple inference on the owner's phone remains untested.

## Verification

At this exact app source, [run 40220017845](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40220017845)
passed 123 model and 67 script cases, zero failures/skips. In
[run 40220308515](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40220308515),
12 native app and six native UI cases passed, including Apple startup restoration
and largest-text model controls. The package job passed three actual-IPA native
hygiene checks and one compiled Release fixture-exclusion check, zero skips.
The downloaded package also passed all three hygiene cases on Windows/Python
3.12.14, plus explicit ZIP, identity, descriptor and receipt checks.

The original model job stopped on DNS before testing. Attempt 2 passed 15 actual
v2/v3/Apple-JSON cases and 195 core/storage/summary/coordinator regressions, zero
failures/skips. The workflow now concludes SUCCESS at the exact source above;
attempt 1 remains recorded as a setup failure, not behavioral RED. Original
model-quality failures are preserved; automated quality benchmarks were not used
as a delivery gate.

## Install and validate

Use [Windows iLoader installation](WINDOWS_INSTALL.md) over the existing app with
the same Apple Account and bundle IDs. Keep the app installed during renewal and
check that meetings and models remain after updating; preservation requires phone
evidence. Follow the [model-upgrade checklist](MODEL_UPGRADE_DEVICE_CHECKLIST.md)
and [physical-device checklist](MVP4_DEVICE_CHECKLIST.md).

Pending phone gates include actual chosen-model/Apple inference offline, Live
Activity and free extension signing, Action Button warm/locked/cold-start behavior,
two 125-minute recordings with at least 120 locked minutes each, file protection
and in-place seven-day renewal. No `VERIFIED_COMPLETE` claim is made.

The owner cancelled the later screenshot request. Its temporary capture files were
deleted; no screenshot workflow or new screenshot test remains in the repository.
