from __future__ import annotations

from pathlib import Path
import sqlite3

from . import exchange
from .files import atomic_write, check_cancel, copy_file, digest, identifier, json_bytes, read_json, remove_owned_tree, require_regular, safe_path
from .store import FIELDS


def delete_meeting(profile, store, meeting_id: str) -> None:
    meeting_id = identifier(meeting_id)
    with store.lock:
        meeting = store.get("meeting", meeting_id)
        if meeting and meeting["recordingState"] == "recording":
            raise ValueError("Stop recording before deleting this meeting.")
        marker = safe_path(profile.root, "deletions/" + meeting_id + ".json")
        atomic_write(marker, json_bytes(meeting_id))
        _finish_deletion(profile, store, meeting_id)


def _finish_deletion(profile, store, meeting_id):
    directory = safe_path(profile.root, "deletions")
    source, quarantine = profile.meeting_dir(meeting_id), safe_path(directory, meeting_id)
    if source.exists():
        if quarantine.exists():
            raise ValueError("Deletion quarantine already exists.")
        source.rename(quarantine)
    store.execute("DELETE FROM meetings WHERE id=?", (meeting_id,))
    remove_owned_tree(quarantine, directory)
    safe_path(directory, meeting_id + ".json").unlink(missing_ok=True)


def recover_deletions(profile, store):
    directory = safe_path(profile.root, "deletions")
    if directory.exists():
        for marker in directory.glob("*.json"):
            meeting_id = identifier(read_json(marker, 128))
            if marker.name != meeting_id + ".json":
                raise ValueError("Invalid deletion journal.")
            _finish_deletion(profile, store, meeting_id)


def convert_ios_backup(source: Path, destination: Path, source_id: str, cancel=None):
    manifest = read_json(safe_path(source, "manifest.json"), 1048576)
    version = manifest["databaseUserVersion"]
    if manifest["schemaVersion"] != 1 or type(version) is not int or not 1 <= version <= 6 or not 1 <= len(manifest["files"]) <= 16384:
        raise ValueError("Unsupported iPhone backup.")
    payload, total, seen = safe_path(source, "payload"), 0, set()
    for entry in manifest["files"]:
        relative, size = entry["relativePath"], entry["byteCount"]
        if relative in seen or (relative != "meetings.sqlite" and not exchange.allowed(relative)) or relative == "records.jsonl" or type(size) is not int or not 0 <= size <= 536870912:
            raise ValueError("Invalid backup file.")
        seen.add(relative)
        total += size
        path = safe_path(payload, relative)
        if total > 8589934592 or path.stat().st_size != size or digest(path, cancel) != entry["sha256"]:
            raise ValueError("Backup integrity check failed.")
    if total != manifest["totalByteCount"] or "meetings.sqlite" not in seen:
        raise ValueError("Incomplete backup.")
    require_regular(destination).mkdir(parents=True)
    database_path = safe_path(payload, "meetings.sqlite")
    connection = sqlite3.connect(database_path.as_uri() + "?mode=ro", uri=True)
    connection.row_factory = sqlite3.Row
    try:
        connection.executescript("PRAGMA trusted_schema=OFF; PRAGMA query_only=ON;")
        if connection.execute("PRAGMA user_version").fetchone()[0] != version or connection.execute("PRAGMA quick_check").fetchone()[0] != "ok" or connection.execute("PRAGMA foreign_key_check").fetchone():
            raise ValueError("Backup database validation failed.")
        with (destination / "records.jsonl").open("xb") as stream:
            for kind in ("meeting", "segment", "note", "document", "preference", "pin"):
                if (kind == "note" and version < 2) or (kind in ("document", "preference") and version < 4) or (kind == "pin" and version < 5):
                    continue
                table, _, columns = FIELDS[kind]
                expressions = ",".join(f'{column} AS "{field}"' for field, column in columns.items())
                query = f"SELECT {expressions} FROM {table}"
                if kind == "preference" and version < 6:
                    query = "SELECT meeting_id AS meetingId,id AS documentId FROM generated_documents AS d WHERE kind='summary' AND id=(SELECT id FROM generated_documents WHERE meeting_id=d.meeting_id AND kind='summary' ORDER BY created_at DESC,id LIMIT 1)"
                for record in connection.execute(query):
                    check_cancel(cancel)
                    value = dict(record)
                    if kind == "document" and isinstance(value["originalJson"], bytes):
                        value["originalJson"] = value["originalJson"].decode("utf-8")
                    data = json_bytes(dict(type=kind, value=value))
                    if len(data) > exchange.MAX_RECORD:
                        raise ValueError("Backup record is too large.")
                    stream.write(data + b"\n")
    finally:
        connection.close()
    for entry in manifest["files"]:
        if entry["relativePath"] != "meetings.sqlite":
            copy_file(safe_path(payload, entry["relativePath"]), safe_path(destination, entry["relativePath"]), cancel)
    exchange.seal(destination, source_id, cancel)
    return destination


def document_evidence(document, segments):
    from .files import decode_json
    original = decode_json(document["originalJson"].encode("utf-8"))
    lookup = {segment["id"]: segment for segment in segments}
    found = {}
    def walk(item, depth=0):
        if depth > 32:
            raise ValueError("Document nesting exceeds its limit.")
        if isinstance(item, dict):
            if "source_id" in item and "quote" in item:
                source = lookup.get(item["source_id"])
                if source and item.get("start_sample") == source["startSample"] and item.get("end_sample") == source["endSample"] and item["quote"] == source["text"]:
                    found[source["id"]] = source
            for value in item.values():
                walk(value, depth + 1)
        elif isinstance(item, list):
            for value in item:
                walk(value, depth + 1)
    walk(original)
    return list(found.values())
