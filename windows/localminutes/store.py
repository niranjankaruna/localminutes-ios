from __future__ import annotations

from contextlib import contextmanager
import math
from pathlib import Path
import sqlite3
import threading
import time

from .files import decode_json, identifier, require_regular


FIELDS = {
    "meeting": ("meetings", "id", {"id": "id", "title": "title", "createdAt": "created_at", "recordingState": "recording_state", "capturedSampleCount": "captured_sample_count"}),
    "segment": ("transcript_segments", "id", {"id": "id", "meetingId": "meeting_id", "sequence": "sequence", "startSample": "start_sample", "endSample": "end_sample", "text": "text", "modelRevision": "model_revision"}),
    "note": ("manual_notes", "meetingId", {"meetingId": "meeting_id", "text": "text", "editRevision": "edit_revision", "modifiedAt": "modified_at"}),
    "document": ("generated_documents", "id", {"id": "id", "meetingId": "meeting_id", "kind": "kind", "originalJson": "original_json", "question": "question", "editedText": "edited_text", "editRevision": "edit_revision", "modelRevision": "model_revision", "promptVersion": "prompt_version", "createdAt": "created_at", "modifiedAt": "modified_at"}),
    "pin": ("meeting_speech_model_pins", "meetingId", {"meetingId": "meeting_id", "selectionJson": "selection_json"}),
    "preference": ("preferred_summaries", "meetingId", {"meetingId": "meeting_id", "documentId": "document_id"}),
}


def validate(kind: str, value: dict) -> None:
    if kind not in FIELDS or not isinstance(value, dict):
        raise ValueError("Unsupported exchange record.")
    for field in FIELDS[kind][2]:
        if field not in value:
            if field == "question":
                value[field] = None
            else:
                raise ValueError("Missing exchange record field.")
        item = value[field]
        if field in {"id", "meetingId", "documentId"}:
            identifier(item)
        elif field in {"createdAt", "modifiedAt"}:
            if isinstance(item, bool) or not isinstance(item, (int, float)) or not math.isfinite(item):
                raise ValueError("Invalid record timestamp.")
        elif field in {"capturedSampleCount", "sequence", "startSample", "endSample", "editRevision"}:
            if type(item) is not int or not 0 <= item < 2**63 - 1:
                raise ValueError("Invalid record count.")
        elif field != "question" or item is not None:
            if not isinstance(item, str) or len(item.encode("utf-8")) > 1048576:
                raise ValueError("Invalid record text.")
    if kind == "meeting" and (not value["title"].strip() or len(value["title"]) > 1000
                              or value["recordingState"] not in {"recording", "completed", "interrupted", "recovered", "failed"}):
        raise ValueError("Invalid meeting.")
    if kind == "segment" and value["endSample"] < value["startSample"]:
        raise ValueError("Invalid transcript range.")
    if kind == "document" and (value["kind"] not in {"summary", "question_answer"} or not isinstance(decode_json(value["originalJson"].encode()), dict)):
        raise ValueError("Invalid generated document.")
    if kind == "pin" and not isinstance(decode_json(value["selectionJson"].encode()), dict):
        raise ValueError("Invalid speech provenance.")


class Store:
    def __init__(self, path: Path):
        require_regular(path)
        path.parent.mkdir(parents=True, exist_ok=True)
        self.lock = threading.RLock()
        self.connection = sqlite3.connect(path, isolation_level=None, check_same_thread=False)
        self.connection.row_factory = sqlite3.Row
        version = self.scalar("PRAGMA user_version")
        if version not in (0, 1):
            self.connection.close()
            raise ValueError("Unsupported Windows library version.")
        self.connection.executescript("PRAGMA foreign_keys=ON; PRAGMA synchronous=FULL; PRAGMA busy_timeout=1000;")
        if version == 0:
            schema = Path(__file__).parent / "resources" / "schema.sql"
            self.connection.executescript("BEGIN IMMEDIATE;\n" + schema.read_text(encoding="utf-8") + "\nCOMMIT;")

    def execute(self, sql: str, args=()) -> int:
        with self.lock:
            return self.connection.execute(sql, args).rowcount

    def scalar(self, sql: str, args=()):
        with self.lock:
            row = self.connection.execute(sql, args).fetchone()
            return row[0] if row else None

    def query(self, sql: str, args=()) -> list[dict]:
        with self.lock:
            return [dict(row) for row in self.connection.execute(sql, args)]

    @contextmanager
    def transaction(self, *, dry_run=False):
        with self.lock:
            self.connection.execute("BEGIN IMMEDIATE")
            try:
                yield
                self.connection.execute("ROLLBACK" if dry_run else "COMMIT")
            except BaseException:
                if self.connection.in_transaction:
                    self.connection.execute("ROLLBACK")
                raise

    def records(self, kind: str, where="", args=(), order="") -> list[dict]:
        table, _, columns = FIELDS[kind]
        expression = ",".join(f'{column} AS "{field}"' for field, column in columns.items())
        rows = self.query(f"SELECT {expression} FROM {table} {where} {order}", args)
        for row in rows:
            if kind == "document" and isinstance(row["originalJson"], bytes):
                row["originalJson"] = row["originalJson"].decode("utf-8")
        return rows

    def get(self, kind: str, key: str) -> dict | None:
        _, primary, columns = FIELDS[kind]
        rows = self.records(kind, f"WHERE {columns[primary]}=?", (identifier(key),))
        return rows[0] if rows else None

    def insert(self, kind: str, value: dict) -> None:
        validate(kind, value)
        table, _, columns = FIELDS[kind]
        values = [value[key].encode("utf-8") if key == "originalJson" else value[key] for key in columns]
        self.execute(f"INSERT INTO {table}({','.join(columns.values())}) VALUES({','.join('?' for _ in columns)})", values)

    def meetings(self, search="") -> list[dict]:
        return self.records("meeting", "WHERE instr(lower(title),lower(?))>0", (search,), "ORDER BY created_at DESC,id")

    def create(self, title: str, state="completed") -> dict:
        value = dict(id=identifier(), title=title.strip(), createdAt=time.time(), recordingState=state, capturedSampleCount=0)
        self.insert("meeting", value)
        return value

    def transcript(self, meeting: str) -> list[dict]:
        return self.records("segment", "WHERE meeting_id=?", (identifier(meeting),), "ORDER BY sequence")

    def documents(self, meeting: str) -> list[dict]:
        return self.records("document", "WHERE meeting_id=?", (identifier(meeting),), "ORDER BY created_at DESC,id")

    def summary(self, meeting: str) -> dict | None:
        preferred = self.get("preference", meeting)
        documents = [doc for doc in self.documents(meeting) if doc["kind"] == "summary"]
        return next((doc for doc in documents if preferred and doc["id"] == preferred["documentId"]), documents[0] if documents else None)

    def save_note(self, meeting: str, text: str, revision: int) -> dict:
        with self.lock:
            previous = self.get("note", meeting)
            if (previous or {}).get("editRevision", 0) != revision:
                raise ValueError("Notes changed elsewhere. Reload before saving.")
            value = dict(meetingId=meeting, text=text, editRevision=revision + 1, modifiedAt=time.time())
            validate("note", value)
            self.execute("INSERT INTO manual_notes VALUES(?,?,?,?) ON CONFLICT(meeting_id) DO UPDATE SET text=excluded.text,edit_revision=excluded.edit_revision,modified_at=excluded.modified_at", tuple(value.values()))
            return value

    def save_document(self, value: dict) -> None:
        with self.transaction():
            self.insert("document", value)
            if value["kind"] == "summary":
                self.prefer(value["meetingId"], value["id"])

    def prefer(self, meeting: str, document: str) -> None:
        self.execute("INSERT INTO preferred_summaries VALUES(?,?) ON CONFLICT(meeting_id) DO UPDATE SET document_id=excluded.document_id", (meeting, document))

    def edit_document(self, value: dict, text: str) -> dict:
        updated = dict(value, editedText=text, editRevision=value["editRevision"] + 1, modifiedAt=time.time())
        validate("document", updated)
        if self.execute("UPDATE generated_documents SET edited_text=?,edit_revision=?,modified_at=? WHERE id=? AND edit_revision=?", (text, updated["editRevision"], updated["modifiedAt"], value["id"], value["editRevision"])) != 1:
            raise ValueError("Document changed elsewhere. Reload before saving.")
        return updated

    def rename(self, meeting: str, title: str) -> None:
        if not title.strip() or len(title) > 1000:
            raise ValueError("Enter a title of up to 1,000 characters.")
        self.execute("UPDATE meetings SET title=? WHERE id=?", (title.strip(), identifier(meeting)))

    def finish(self, meeting: str, frames: int, state="completed") -> None:
        if frames < 0 or state not in {"completed", "interrupted", "recovered", "failed"}:
            raise ValueError("Invalid recording state.")
        self.execute("UPDATE meetings SET captured_sample_count=?,recording_state=? WHERE id=?", (frames, state, identifier(meeting)))

    def backup(self, target: Path) -> None:
        require_regular(target)
        with self.lock, sqlite3.connect(target) as destination:
            self.connection.backup(destination)

    def close(self) -> None:
        with self.lock:
            self.connection.close()
