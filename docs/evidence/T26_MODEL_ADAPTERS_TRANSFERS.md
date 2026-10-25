# T26: model adapters, bounded transfer memory and detailed progress

Owner request: create an upgradeable Parakeet adapter, fix download memory spikes,
and show detailed download progress. The reported Phi-3 phone termination occurred
during download or verification; its exact termination reason remains unknown.

## Acceptance

- T26.1: actual Darwin installer verification and reopen of a 512 MiB synthetic
  file add less than 64 MiB to peak process memory. Preserve checksum rejection,
  cancellation, resumable prefixes, atomic installation and prior models.
- T26.2: real HTTP delegates publish bytes, total, observed speed, estimated time
  remaining, resumed bytes and separate verification/install stages. The app shows
  current file and aggregate progress without queued per-chunk UI work.
- T26.3: a versioned Parakeet model pack selects a supported TDT configuration
  independently of a single repository/revision. Preserve the legacy v2 pin,
  validate every pack's own artifacts, use actual local inference, and reject an
  unknown decoder contract explicitly. Live/replay retain the captured pack.

## RED — before production behavior

Initial tests: `LargeModelTransferTests.testLargeDownloadVerificationAndReopenKeepPeakMemoryIndependentOfFileSize`
and `ModelTransferProgressTests.testActualHTTPTransferReportsByteProgressThenVerificationBeforeCompletion`.
The progress overload is a compileable test-first interface which delegates to
the existing transport and deliberately implements no progress reporting.
Command: `swift test --package-path .agent-local/model-tests` on hosted macOS.
Source: `20da4e8e8e68ea9b7add81d1c6d4b18bdedb1ae1`, committed and pushed before behavior.
[Run 40209885118](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40209885118)
completed FAILURE: 115 tests executed, 113 passed, 2 failed with 6 assertion
failures, zero skipped, 37.885 seconds. The memory assertion measured a
536,870,912-byte file, peak before 40,591,360 bytes, peak after 1,656,266,752
bytes: growth 1,615,675,392 bytes, exceeding the unchanged 67,108,864-byte bound.
The real HTTP progress case verified output bytes but failed five progress
assertions because no events were emitted. This is behavioral RED, not a
compiler/tool failure. It reproduces a Darwin large-file risk; it does not
establish the owner's unobserved iPhone termination reason.

## GREEN

Implementation, source SHA, actual tests/counts, native integration and CI: PENDING.
No new iOS artifact or device result is claimed.

## Review and continuation

Fixtures use generated non-sensitive bytes. No weights, device logs, meeting
content or credentials may enter the repository. Phone download reproduction,
locked live transcription, two-hour runs, signing and renewal remain pending.
Next: push these tests, observe genuine hosted RED, then implement T26.1/T26.2.
