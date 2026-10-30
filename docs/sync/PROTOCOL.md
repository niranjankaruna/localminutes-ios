# LocalMinutes local sync version 1

This documents the implemented protocol in the [Python Windows host](../../windows/localminutes/sync.py) and [iPhone client](../../ios/App/LocalSyncController.swift). It uses no hosted service. Windows owns a TCP/TLS listener and the foreground iPhone connection carries either direction of transfer.

## Identity and trust

Each profile has a persistent random UUID (`replicaId`); each launch has a separate `runId`. Meeting IDs remain unchanged between platforms. UUIDs on the wire use uppercase, hyphenated `D` representation. UUIDs and friendly names are not authentication.

Windows creates an ECDSA P-256 self-signed certificate and protects its private identity and peer credentials with Windows DPAPI. Pairing is a five-minute, one-use invitation. Its UTF-8 JSON is base64 encoded after `localminutes://pair/` and contains:

```json
{
  "version": 1,
  "host": "192.168.1.10",
  "port": 47835,
  "fingerprint": "64 lowercase SHA-256 hex characters for the certificate DER",
  "token": "64 lowercase hex characters from 32 cryptographically random bytes",
  "replicaId": "00000000-0000-0000-0000-000000000001",
  "name": "My Windows PC"
}
```

The iPhone validates the address as a private/link-local IPv4 literal and pins the exact certificate fingerprint supplied by the invitation. It sends the token only inside TLS. Windows binds a successfully consumed invitation to the phone's replica ID; later connections must authenticate that same token. A fresh valid invitation can re-pair an existing device. The iPhone stores its pairing in Keychain with device-only, unlocked accessibility. Moving a Windows profile to another user/machine requires re-pairing.

Windows advertises `_localminutes._tcp` through multicast DNS, using service instance `LocalMinutes-<replicaId>` and TXT fields `id` and `v=1`. The iPhone searches for its paired instance before falling back to the invitation's IPv4 address. Discovery records are untrusted routing hints; the pinned TLS certificate and secret remain mandatory. The Windows advertisement was exercised locally; the iOS discovery path still needs physical-device verification.

## Framing

Every control message is four bytes of unsigned big-endian JSON byte length followed by exactly that many UTF-8 bytes. Valid lengths are 2 through 16 MiB. File bytes follow a `put` or `chunk` control message without a second length prefix; its `bytes` field controls the exact read. Chunk size is 1–65,536 bytes. No shell commands, SQL, filesystem paths outside the declared allowlist, or credentials are transferred as meeting content.

One client serializes requests and responses on one connection. Each session starts with `hello` containing `version`, `replicaId`, optional `runId`, `name`, and `token`; the host replies `ready` with its replica ID/name. Authentication precedes all library metadata. Only one peer session is active at a time.

## Snapshot format

A transfer is an immutable directory containing `manifest.json`, `records.jsonl`, and allowed files beneath `Meetings/<UUID>/`. The source owns a copy of all bytes, so subsequent source edits or local deletion cannot invalidate the snapshot.

The manifest has `schemaVersion: 1`, `transferId`, `sourceId`, and `files`. Each file has `relativePath`, signed 64-bit nonnegative `byteCount`, and a lowercase SHA-256 `sha256`. Duplicate names, including case collisions, are rejected. Manifest size is bounded at 16 MiB and file count at 100,000. Each metadata JSON line is bounded at 8 MiB; capture/recovery JSON files are bounded at 16 MiB. Large record collections are represented as multiple JSON lines rather than a UI-sized document list.

Allowed media are `capture-manifest.json`, `recovery-report.json`, `transcription-replay.json`, `segment-000000.caf`-style files and those CAF names inside `RecoveryQuarantine`. Model folders, model binaries, peer credentials, selections, diagnostics and arbitrary files are never enumerated. Original CAF bytes retain their hash, sample format and sample positions.

Every metadata line is `{ "type": "...", "value": { ... } }`, terminated by LF. Blank/truncated lines are rejected. Fields use lower camel case; timestamps are finite Unix seconds, not Foundation reference-date seconds. `originalJson` is the exact original JSON represented as a UTF-8 string, with ordinary outer JSON escaping. Notes/documents remain separate from their source transcripts.

| Record | Fields |
| --- | --- |
| `meeting` | `id`, `title`, `createdAt`, `recordingState`, `capturedSampleCount` |
| `segment` | `id`, `meetingId`, `sequence`, `startSample`, `endSample`, `text`, `modelRevision` |
| `note` | `meetingId`, `text`, `editRevision`, `modifiedAt` |
| `document` | `id`, `meetingId`, `kind`, `originalJson`, nullable `question`, `editedText`, `editRevision`, `modelRevision`, `promptVersion`, `createdAt`, `modifiedAt` |
| `pin` | `meetingId`, `selectionJson` containing historical speech provenance |
| `preference` | `meetingId`, `documentId` referencing a saved summary |

Parents precede children; document rows precede preferences. Exports enumerate every saved document rather than the UI's maximum/history page. Incoming note/document edit revisions never replace local editor revision counters. Imported edits advance local revisions to reject stale UI saves.

## Phone sends to Windows

1. `push` carries the manifest. Host validates identity and replies `accept` or `busy`.
2. For each file, `offset` with `path` returns its persisted byte offset. Already verified complete files return their full byte count; identical available local files can populate staging without network transfer.
3. `put` carries `path`, `offset`, `bytes`, followed by the raw chunk. Host persists the bytes and replies `saved` with the next offset. A complete file must pass its full SHA-256 before publication.
4. `commit` validates the entire staged snapshot and applies it. Host replies `complete` only after the database transaction commits. The receipt includes processed record counts, not a promise that every row was new.

An empty file sends no `put`; the receiver materializes it and validates its digest at commit. Reconnection repeats `push` for the same immutable manifest/transfer ID before asking offsets.

## Windows sends to phone

The Windows button captures a snapshot bound to the currently connected phone. The phone periodically sends `poll`; a pending send to that specific peer returns `offer` with the manifest. Other peers cannot fetch that queued send.

For each needed file, the phone sends `get` with `path` and `offset`. Host replies `chunk` with `bytes`, then the raw bytes. The phone stages, verifies and merges the full snapshot, then sends `received` with the matching transfer ID. Host replies `complete`. The host atomically records its pending snapshot and recipient in the local profile; restart resumes the same immutable transfer. Cancellation clears the pending descriptor and cancels snapshot preparation, but cannot undo an import already committed by the phone.

## Apply semantics and recovery

- Matching mutable content uses the sender's value, even with an older timestamp.
- Receiver-only data stays. Missing records are not tombstones. An explicitly empty note is an update.
- Distinct generated-document IDs remain distinct; a valid summary preference chooses what to display without deleting history. Absent/null preferences do not clear receiver summaries.
- Conflicting immutable source/audio identities are errors. A changed transcript under an existing UUID is not an editable-version conflict.
- Original capture manifests merge compatible segments without shortening the receiver's timeline. Independent cross-platform retranscription is deferred until versioned transcript storage exists.
- Windows writes a recoverable media journal, publishes verified media and commits metadata plus a receipt in one SQLite transaction. Startup reconciles the media journal against the committed receipt before exposing the library.
- iPhone clones its existing library into a private generation, merges and validates there, then atomically changes the active-generation pointer. The previous generation remains available.
- Repeating a committed transfer ID with its original manifest returns the prior result without duplicate records. Reusing an ID with a different manifest is rejected.

The current implementation keeps receipts with the library and retains transfer/rollback folders. A separately durable receipt ledger across manual backup rollback and automatic retention limits remain planned hardening work. Do not describe them as implemented.

## Verification

[Python Windows tests](../../windows/python-tests/) cover real loopback TLS pairing, incorrect-token rejection, interrupted/resumed uploads, both data directions, sender-wins/no-delete behavior, immutable collision rollback, CAF media and queued-send restart/cancellation. [Swift persistence tests](../../ios/Tests/PersistenceTests/LocalSyncPersistenceTests.swift) cover the matching import contract, but require a Mac to execute. A physical iPhone/Windows round trip remains required before release sign-off.
