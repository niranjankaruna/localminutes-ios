from __future__ import annotations

import os
from pathlib import Path
import re
import time

from .files import atomic_write, check_cancel, copy_file, decode_json, digest, identifier, json_bytes, read_json, require_regular, safe_path
from .store import FIELDS, validate


MAX_FRAME = 16 * 1024 * 1024
MAX_RECORD = 8 * 1024 * 1024
MEDIA = re.compile(r"Meetings/([0-9A-F-]{36})/(?:capture-manifest\.json|recovery-report\.json|transcription-replay\.json|(?:RecoveryQuarantine/)?segment-[0-9]{6}\.caf)\Z")


def allowed(path: str) -> bool:
    if path == "records.jsonl":
        return True
    match = MEDIA.fullmatch(path)
    if match:
        try:
            identifier(match[1])
            return True
        except ValueError:
            pass
    return False


def validate_manifest(manifest: dict) -> int:
    if manifest.get("schemaVersion") != 1:
        raise ValueError("Unsupported transfer version.")
    identifier(manifest["transferId"])
    identifier(manifest["sourceId"])
    if not isinstance(manifest["files"], list) or not 1 <= len(manifest["files"]) <= 100000:
        raise ValueError("Invalid transfer file count.")
    seen, total = set(), 0
    for entry in manifest["files"]:
        path, size, sha = entry["relativePath"], entry["byteCount"], entry["sha256"]
        if not allowed(path) or path.casefold() in seen or type(size) is not int or size < 0 or not re.fullmatch("[0-9a-f]{64}", sha):
            raise ValueError("Invalid transfer file.")
        if path.endswith(".json") and size > MAX_FRAME:
            raise ValueError("Oversized transfer JSON.")
        total += size
        if total >= 2**63:
            raise ValueError("Oversized transfer.")
        seen.add(path.casefold())
    if "records.jsonl" not in seen:
        raise ValueError("Transfer records are missing.")
    return total


def rows(directory: Path):
    with safe_path(directory, "records.jsonl").open("rb") as stream:
        while line := stream.readline(MAX_RECORD + 2):
            if not line.endswith(b"\n") or not 1 < len(line) <= MAX_RECORD + 1:
                raise ValueError("Oversized or incomplete exchange record.")
            row = decode_json(line)
            validate(row["type"], row["value"])
            if row["type"] == "meeting" and row["value"]["recordingState"] == "recording":
                raise ValueError("Active recordings cannot be transferred.")
            yield row


def validate_snapshot(directory: Path, cancel=None) -> dict:
    manifest = read_json(safe_path(directory, "manifest.json"))
    validate_manifest(manifest)
    for file in manifest["files"]:
        path = safe_path(directory, file["relativePath"])
        if path.stat().st_size != file["byteCount"] or digest(path, cancel) != file["sha256"]:
            raise ValueError("Transfer file checksum mismatch.")
    for _ in rows(directory):
        check_cancel(cancel)
    return manifest


def seal(directory: Path, source_id: str, cancel=None) -> dict:
    entries = []
    for current, folders, names in os.walk(directory, followlinks=False):
        for child in folders + names:
            require_regular(Path(current) / child)
        for name in sorted(names):
            path = Path(current) / name
            relative = path.relative_to(directory).as_posix()
            if not allowed(relative):
                raise ValueError("Unexpected transfer file.")
            entries.append(dict(relativePath=relative, byteCount=path.stat().st_size, sha256=digest(path, cancel)))
    manifest = dict(schemaVersion=1, transferId=identifier(), sourceId=identifier(source_id), files=sorted(entries, key=lambda item: item["relativePath"]))
    validate_manifest(manifest)
    encoded = json_bytes(manifest)
    if len(encoded) > MAX_FRAME:
        raise ValueError("Transfer manifest is too large.")
    atomic_write(directory / "manifest.json", encoded)
    return manifest


def create(profile, store, destination: Path, cancel=None) -> dict:
    require_regular(destination).mkdir(parents=True)
    with store.lock:
        meetings = store.meetings()
        if any(meeting["recordingState"] == "recording" for meeting in meetings):
            raise ValueError("Stop recording before syncing.")
        with (destination / "records.jsonl").open("xb") as stream:
            def write(kind, value):
                check_cancel(cancel)
                data = json_bytes(dict(type=kind, value=value))
                if len(data) > MAX_RECORD:
                    raise ValueError("Exchange record is too large.")
                stream.write(data + b"\n")
            for meeting in meetings:
                key = meeting["id"]
                write("meeting", meeting)
                for segment in store.transcript(key):
                    write("segment", segment)
                if note := store.get("note", key):
                    write("note", note)
                for document in store.documents(key):
                    write("document", document)
                if summary := store.summary(key):
                    write("preference", dict(meetingId=key, documentId=summary["id"]))
            for pin in store.records("pin"):
                write("pin", pin)
            stream.flush()
            os.fsync(stream.fileno())
        for meeting in meetings:
            source = profile.meeting_dir(meeting["id"])
            if not source.exists():
                continue
            for current, folders, files in os.walk(source, followlinks=False):
                for child in folders + files:
                    require_regular(Path(current) / child)
                for name in files:
                    path = Path(current) / name
                    relative = path.relative_to(profile.library).as_posix()
                    if allowed(relative):
                        copy_file(path, safe_path(destination, relative), cancel)
        return seal(destination, profile.identity["replicaId"], cancel)


def apply_rows(store, directory: Path) -> dict:
    counts = dict(meetings=0, notes=0, documents=0, alreadyApplied=False)
    seen = set()
    for row in rows(directory):
        kind, value = row["type"], row["value"]
        key = value[FIELDS[kind][1]]
        if (kind, key) in seen:
            raise ValueError("Duplicate exchange record.")
        seen.add((kind, key))
        previous = store.get(kind, key)
        if kind == "meeting":
            if previous:
                if previous["createdAt"] != value["createdAt"]:
                    raise ValueError("Meeting identity collision.")
                store.execute("UPDATE meetings SET title=?,recording_state=CASE WHEN captured_sample_count<=? THEN ? ELSE recording_state END,captured_sample_count=max(captured_sample_count,?) WHERE id=?",
                              (value["title"], value["capturedSampleCount"], value["recordingState"], value["capturedSampleCount"], key))
            else:
                store.insert(kind, value)
            counts["meetings"] += 1
        elif kind in ("segment", "pin"):
            if previous and any(previous[field] != value[field] for field in FIELDS[kind][2]):
                raise ValueError("Original transcript or speech provenance identity collision.")
            if not previous:
                store.insert(kind, value)
        elif kind == "note":
            store.save_note(key, value["text"], (previous or {}).get("editRevision", 0))
            store.execute("UPDATE manual_notes SET modified_at=? WHERE meeting_id=?", (value["modifiedAt"], key))
            counts["notes"] += 1
        elif kind == "document":
            if previous:
                immutable = ("meetingId", "kind", "originalJson", "question", "modelRevision", "promptVersion", "createdAt")
                if any(previous[field] != value[field] for field in immutable):
                    raise ValueError("Original generated document identity collision.")
                store.execute("UPDATE generated_documents SET edited_text=?,edit_revision=edit_revision+1,modified_at=? WHERE id=?", (value["editedText"], value["modifiedAt"], key))
            else:
                store.insert(kind, dict(value, editRevision=0))
            counts["documents"] += 1
        elif kind == "preference":
            document = store.get("document", value["documentId"])
            if not document or document["meetingId"] != key or document["kind"] != "summary":
                raise ValueError("Invalid summary preference.")
            store.prefer(key, value["documentId"])
    return counts


def merge_capture(incoming: Path, target: Path) -> None:
    new, old = read_json(incoming), read_json(target)
    if new["schemaVersion"] != 1 or old["schemaVersion"] != 1 or new["sessionID"] != old["sessionID"]:
        raise ValueError("Capture identity collision.")
    union = {entry["relativePath"]: entry for entry in old["segments"]}
    for entry in new["segments"]:
        if entry["relativePath"] in union and union[entry["relativePath"]] != entry:
            raise ValueError("Capture segment identity collision.")
        union[entry["relativePath"]] = entry
    segments = sorted(union.values(), key=lambda entry: entry["startFrame"])
    total = segments[-1]["startFrame"] + segments[-1]["frameCount"] if segments else 0
    atomic_write(target, json_bytes(dict(schemaVersion=1, sessionID=new["sessionID"], totalFrames=total, segments=segments)))


def recover(profile, store) -> None:
    journal_path = profile.root / "pending-import.json"
    if not journal_path.exists():
        return
    journal = read_json(journal_path)
    committed = store.scalar("SELECT digest FROM sync_receipts WHERE transfer_id=?", (identifier(journal["transferId"]),))
    if committed and committed != journal["digest"]:
        raise ValueError("Import recovery identity mismatch.")
    if not committed:
        rollback = safe_path(profile.root, "rollback/" + journal["transferId"])
        for relative in journal["replaced"]:
            if not allowed(relative):
                raise ValueError("Invalid import journal.")
            copy_file(safe_path(rollback, relative), safe_path(profile.library, relative))
        for relative in journal["added"]:
            if not allowed(relative):
                raise ValueError("Invalid import journal.")
            safe_path(profile.library, relative).unlink(missing_ok=True)
    journal_path.unlink()


def apply(profile, store, source: Path, cancel=None) -> dict:
    from .audio import Timeline
    manifest = validate_snapshot(source, cancel)
    sha = digest(source / "manifest.json", cancel)
    with store.lock:
        prior = store.scalar("SELECT digest FROM sync_receipts WHERE transfer_id=?", (manifest["transferId"],))
        if prior:
            if prior != sha:
                raise ValueError("Transfer identity was reused.")
            return dict(meetings=0, notes=0, documents=0, alreadyApplied=True)
        if any(meeting["recordingState"] == "recording" for meeting in store.meetings()):
            raise ValueError("Stop recording before receiving data.")
        with store.transaction(dry_run=True):
            apply_rows(store, source)
        check_cancel(cancel)
        rollback = safe_path(profile.root, "rollback/" + manifest["transferId"])
        rollback.mkdir(parents=True, exist_ok=True)
        store.backup(rollback / "before.sqlite")
        replaced, added = [], []
        for entry in manifest["files"]:
            relative = entry["relativePath"]
            if relative == "records.jsonl":
                continue
            target = safe_path(profile.library, relative)
            if target.exists():
                if digest(target, cancel) == entry["sha256"]:
                    continue
                if relative.endswith(".caf"):
                    raise ValueError("Original audio identity collision.")
                copy_file(target, safe_path(rollback, relative), cancel)
                replaced.append(relative)
            else:
                added.append(relative)
        journal = profile.root / "pending-import.json"
        if journal.exists():
            raise ValueError("An earlier import needs recovery.")
        atomic_write(journal, json_bytes(dict(transferId=manifest["transferId"], digest=sha, replaced=replaced, added=added)))
        try:
            for relative in replaced + added:
                check_cancel(cancel)
                incoming, target = safe_path(source, relative), safe_path(profile.library, relative)
                if relative.endswith("/capture-manifest.json") and target.exists():
                    merge_capture(incoming, target)
                else:
                    copy_file(incoming, target, cancel)
            for entry in manifest["files"]:
                if entry["relativePath"].endswith("/capture-manifest.json"):
                    Timeline(safe_path(profile.library, entry["relativePath"]).parent)
            check_cancel(cancel)
            with store.transaction():
                receipt = apply_rows(store, source)
                store.execute("INSERT INTO sync_receipts VALUES(?,?,?,?)", (manifest["transferId"], manifest["sourceId"], sha, time.time()))
            journal.unlink()
            return receipt
        except BaseException:
            recover(profile, store)
            raise
