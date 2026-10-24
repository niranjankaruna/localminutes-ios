# MVP2 reliability and data — 24 October 2026

Status IN_PROGRESS. Delivered MVP1 remains source4aec851/run40117673355;
these changes do not alter the already delivered IPA or any physical gate.

## Observable acceptance and tests-first RED

Summary resume reopens a protected validated map prefix, binds exact source,
model/prompt/runtime/plan/budgets and revalidates every cached map before reuse.
Downloads retain bounded verified partial files and strong-ETag range state,
then use existing full-hash/atomic installation. Archives round-trip actual
closed SQLite/CAF bytes with strict path/hash/limits and fresh destinations;
SQLite native backup includes committed WAL without mutating its source.
Recovery requires a capture-time speech installation pin, preserves originals
and global ranges, and rejects a changed checkpoint cursor without skipping
untranscribed audio. Schema5 adds only immutable speech pins; legacy data stays.

Test-first31513b1/checkpoint34ab9e9 are pushed before these implementations.
Exact observed RED source **34ab9e9dd36a73ffa6fcf6e5e717d2b72f4353f1**,
[run40119556084](https://github.com/niranjankaruna/localminutes-ios/actions/runs/40119556084),
standard macos-15-intel/Xcode26.2, exact commands in mvp2-red workflow mode.

| Actual suite | Result |
|---|---|
| DownloadResumeTests | 11executed,2PASS/9FAIL,56assertions,0skip,2.484s |
| MeetingArchiveTests | 10executed,0PASS/10FAIL,31assertions,0skip,0.506s |
| SQLiteSnapshotTests | 5executed,0PASS/5FAIL,9assertions,0skip,0.293s |
| SummaryResumePipelineTests | 4executed,0PASS/4FAIL,60assertions,0skip,0.322s |
| SelectedModelRecoveryTests | 5executed,0PASS/5FAIL,12assertions,0skip,18.424s |
| TranscriptionReplayCheckpointIntegrityTests | 2executed,1PASS/1FAIL,1assertion,0skip,27.710s |

Portable job120947908921:30executed2PASS28FAIL156assertions0skip3.606s.
Recovery job120947908779:7executed1PASS6FAIL13assertions0skip46.133s.
Total37executed3PASS34FAIL169assertions0skip. This is behavioral failure after
successful compilation/real SQLite/CAF/actual speech fixture setup, not a tool
failure, zero tests or skipped fake/native substitute.

Examples: cancelled transfer has no durable checkpoint; source-aware summary
resume returns nil prefix and regenerates2maps instead of1; SQLite snapshot
throws notImplemented; archive notImplemented differs from integrityMismatch;
Whisper preparation saves no captured pin, schema remains4 instead of5, and
mutating only cursor allows actual remaining speech to be skipped. All observed
failures precede the corresponding production implementation. Runtime and HTTP
doubles exist only at orchestration/transport boundaries; actual speech tests
use reviewed model bytes and licensed audio, not supplied recognizer strings.

## Implementation and review pending GREEN

Root implements bounded directory archives/restore with protected staging,
no-follow regular-file handles, streaming hash/copy and exclusive publication.
Independent review found one additional traversal gap: empty meeting folders
are not counted by regular-file limits. A DB-only regression is added before
that repair; initial fixture's3files would have made a2file limit falsely pass.
Next run intentionally observes that new RED while verifying initial repairs.

Native SQLite backup uses the SQLite backup API, bounded pages/busy retries,
closed synced output and exclusive rename; original connection/WAL remains.
Summary maps use actual byte digests, grounded decoding and atomic prefix save.
HTTP resume owns one serial file/delegate queue, retained hashes/strongETag,
strict206/200 handling and only installer-staging publication. Captured speech
pin persists before ingress, is immutable and bound to full installation;
replay loads captured Whisper rather than today's Equip selection. Journalv2
binds cursor to its proof; checksum is integrity checking, not authentication.

Current-schema-only test expectations advance4→5 for the real pin-table
migration; historical v1/v2/v3 fixture versions/data assertions remain unchanged.
Snapshot checks independently compare source version with snapshot version.
The manually constructed legacy4 archive remains4. The strict current-schema
test reporter name is updated with the renamed test. No oracle deletion/skip or
weakened content, privacy, checksum or model-quality rule is authorized.

App resume/recovery/download/cache/Files wiring, backup/restore admission/UI,
full endurance diagnostics and package delivery are still required before MVP2
is delivered. Separate service-integration tests are being prepared; initial
primitive GREEN alone cannot establish usable app behavior or code completion.
All physical-device gates remain NOT_RUN; no human signing/device action is
needed for current safe coding/hosted checks.
