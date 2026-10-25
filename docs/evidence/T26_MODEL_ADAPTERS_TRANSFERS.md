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

At `1d2f290032bdebcc497d2701eb456caef887124c`,
[run 40212954360](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40212954360)
executed 122 tests, with 12 assertion failures in seven cases (two unexpected
stub errors), zero skips, 23.366 seconds. The unchanged 512 MiB memory test
PASSED: peak before/after both 57,511,936 bytes, additional peak growth zero.
The newly specified pack/Apple/aggregate cases provided behavioral RED. The raw
HTTP case exposed coalesced callbacks: its intermediate-byte assertion remained
RED and is addressed by reporting within the bounded chunk loop, not weakening
the assertion. Full GREEN remains pending.

At the same source,
[native run 40213241251](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40213241251)
verified actual pinned v3 assets (`7dd20fe6b1797d35f5e3307e8b1732d9a178edfe`,
21 files / 483,105,645 bytes) and executed 12 native ASR cases: nine legacy v2
cases passed; three v3 cases failed (two unexpected errors), zero skips,
52.277 seconds. Direct v3 loading explicitly failed `invalidModel`; installed
v3 live/replay failed `invalidManifest`. These are model-contract RED, not
missing fixtures or compilation failures. v3 functionality has no quality-score gate.

Implementation, exact final source, full GREEN and delivery: PENDING.
No new iOS artifact or device result is claimed.

## Review and continuation

Fixtures use generated non-sensitive bytes. No weights, device logs, meeting
content or credentials may enter the repository. Phone download reproduction,
locked live transcription, two-hour runs, signing and renewal remain pending.
Next: push these tests, observe genuine hosted RED, then implement T26.1/T26.2.

## Intermediate exact-source results

At source `fe7aa94f6cd85aeb95644a32789b5f2972167a05`, [run 40215222725](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40215222725) executed 123 model tests: 122 passed, one new publisher-independent pack discovery case failed three assertions, zero skipped, 31.706 seconds. Pack installation/equip, legacy compatibility, raw/aggregate HTTP progress and Apple selection all passed. The unchanged 512 MiB memory regression measured 40,759,296 bytes before and 40,828,928 after: 69,632 bytes additional peak, below 67,108,864. The failing discovery test was committed before implementing the generic repository route.

The native v2/v3 runtime and final UI/Apple checks are still pending at the new implementation.
