from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import sys
import threading
import uuid


def identifier(value: str | None = None) -> str:
    if value is None:
        return str(uuid.uuid4()).upper()
    if not isinstance(value, str) or str(uuid.UUID(value)).upper() != value:
        raise ValueError("Invalid record identifier.")
    return value


def check_cancel(cancel: threading.Event | None) -> None:
    if cancel is not None and cancel.is_set():
        raise InterruptedError("Operation cancelled. Saved data is retained.")


def require_regular(path: Path) -> Path:
    path = Path(os.path.abspath(path))
    for part in [path, *path.parents]:
        try:
            info = part.lstat()
        except FileNotFoundError:
            continue
        if stat.S_ISLNK(info.st_mode) or info.st_file_attributes & stat.FILE_ATTRIBUTE_REPARSE_POINT:
            raise ValueError("Linked application files are not supported.")
        if not (stat.S_ISREG(info.st_mode) or stat.S_ISDIR(info.st_mode)):
            raise ValueError("Expected a regular application file.")
        if stat.S_ISREG(info.st_mode) and info.st_nlink != 1:
            raise ValueError("Hard-linked application files are not supported.")
    return path


def safe_path(root: Path, relative: str) -> Path:
    if not isinstance(relative, str) or "\\" in relative:
        raise ValueError("Invalid relative path.")
    parts = relative.split("/")
    reserved = {"CON", "PRN", "AUX", "NUL", *(f"COM{i}" for i in range(1, 10)), *(f"LPT{i}" for i in range(1, 10))}
    if any(not p or p in (".", "..") or p.endswith((".", " ")) or any(ord(c) < 32 or c in ':*?"<>|' for c in p)
           or p.split(".")[0].upper() in reserved for p in parts):
        raise ValueError("Invalid relative path.")
    return require_regular(require_regular(root).joinpath(*parts))


def json_bytes(value: object) -> bytes:
    return json.dumps(value, ensure_ascii=False, allow_nan=False, separators=(",", ":")).encode("utf-8")


def read_json(path: Path, limit: int = 16 * 1024 * 1024):
    require_regular(path)
    with path.open("rb") as stream:
        raw = stream.read(limit + 1)
    if len(raw) > limit:
        raise ValueError("JSON file exceeds its size limit.")
    return decode_json(raw)


def decode_json(data: bytes):
    def invalid(value):
        raise ValueError("Non-finite JSON number.")
    return json.loads(data, parse_constant=invalid)


def atomic_write(path: Path, data: bytes) -> None:
    require_regular(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + "." + uuid.uuid4().hex + ".tmp")
    try:
        with temporary.open("xb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def digest(path: Path, cancel: threading.Event | None = None) -> str:
    require_regular(path)
    value = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(131072):
            check_cancel(cancel)
            value.update(chunk)
    return value.hexdigest()


def copy_file(source: Path, target: Path, cancel: threading.Event | None = None) -> None:
    require_regular(source)
    require_regular(target)
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_name(target.name + "." + uuid.uuid4().hex + ".tmp")
    try:
        with source.open("rb") as incoming, temporary.open("xb") as outgoing:
            while chunk := incoming.read(131072):
                check_cancel(cancel)
                outgoing.write(chunk)
            outgoing.flush()
            os.fsync(outgoing.fileno())
        os.replace(temporary, target)
    finally:
        temporary.unlink(missing_ok=True)


def assets() -> Path:
    return Path(getattr(sys, "_MEIPASS", Path(__file__).resolve().parent.parent))


def runtime_path() -> Path:
    if getattr(sys, "frozen", False):
        return assets() / "runtime" / "llama"
    return assets() / ".native" / "llama-cuda"


def default_data_root() -> Path:
    roaming = os.environ.get("APPDATA")
    if not roaming:
        raise RuntimeError("Windows APPDATA is unavailable.")
    return Path(roaming) / "LocalMinutes"


def remove_owned_tree(path: Path, owner: Path) -> None:
    path, owner = require_regular(path), require_regular(owner)
    if path == owner or not path.is_relative_to(owner):
        raise ValueError("Cleanup target is outside its owned directory.")
    if not path.exists():
        return
    pending = [path]
    while pending:
        for child in pending.pop().iterdir():
            require_regular(child)
            if child.is_dir():
                pending.append(child)
    shutil.rmtree(path)


class Profile:
    def __init__(self, root: Path | None = None):
        import msvcrt
        self.root = require_regular(root or default_data_root())
        self.root.mkdir(parents=True, exist_ok=True)
        self._lock = safe_path(self.root, "profile.lock").open("a+b")
        try:
            self._lock.seek(0)
            msvcrt.locking(self._lock.fileno(), msvcrt.LK_NBLCK, 1)
        except OSError:
            self._lock.close()
            raise RuntimeError("LocalMinutes is already using this data folder.") from None
        try:
            self.library = self.root / "library"
            self.meetings = self.library / "Meetings"
            self.models = self.root / "models"
            self.database = self.library / "meetings.sqlite"
            for folder in (self.library, self.meetings, self.models, self.root / "identity"):
                require_regular(folder).mkdir(parents=True, exist_ok=True)
            identity = self.root / "identity" / "device.json"
            if identity.exists():
                self.identity = read_json(identity, 4096)
                identifier(self.identity["replicaId"])
            else:
                self.identity = {"replicaId": identifier(), "deviceName": "My Windows PC"}
                atomic_write(identity, json_bytes(self.identity))
            self.run_id = identifier()
        except BaseException:
            self.close()
            raise

    def meeting_dir(self, meeting_id: str) -> Path:
        return safe_path(self.meetings, identifier(meeting_id))

    def close(self) -> None:
        if not self._lock.closed:
            import msvcrt
            self._lock.seek(0)
            msvcrt.locking(self._lock.fileno(), msvcrt.LK_UNLCK, 1)
            self._lock.close()
